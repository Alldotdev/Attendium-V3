import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../core/errors/failures.dart';
import '../../core/result/result.dart';
import 'ai_contract_validator.dart';
import 'ai_models.dart';
import 'ai_provider.dart';

/// Gemini AI Provider with autonomous model discovery, self-healing retries,
/// and automatic caching so users never encounter 404/model deprecation errors.
class GeminiProvider implements AiProvider {
  final String apiKey;
  final String modelName;
  final http.Client _client;

  /// Global in-memory cache mapping apiKey -> working model name
  static final Map<String, String> _workingModelCache = {};

  GeminiProvider({
    required this.apiKey,
    this.modelName = 'auto',
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  String get providerName => 'gemini';

  /// Returns the currently cached or designated working model for this key
  String get activeModelName => _workingModelCache[apiKey] ?? (modelName != 'auto' ? modelName : 'gemini-1.5-flash');

  static const String systemInstruction = '''
You are Attendium's specialized academic attendance-document extraction engine.
Your task is to accurately extract student attendance information visibly present in the supplied document or photo.
The document can be:
- A printed tabular attendance sheet or report.
- A handwritten paper sheet, notebook page, or photo of physical paper with lists of roll numbers or names.
- A screenshot or sign-in sheet.

EXTRACTION RULES:
1. Preserve row order as visually laid out on the page from top to bottom.
2. Read handwritten text carefully. Distinguish digits (e.g. 1 vs 7 vs I, 5 vs S, 0 vs O, 8 vs B).
3. If the first entries establish a roll number pattern (e.g. "F24-588", "F24-1319") and subsequent entries only have leading dashes or suffixes (e.g. "- 552", "- 693", "651"), extract each individual entry. For "- 552", set raw_roll to "552" or "F24-552".
4. If an entry has a student name, extract it into raw_name. If only roll numbers are listed, set raw_name to null.
5. If the document is a paper list of attendee roll numbers or sign-in list without explicit absent marks, every listed student is Present; set raw_attendance to "P". If explicit marks like "A", "Absent", "L", "Late", "E" appear, extract them.
6. Extract header information like date (e.g. "16/sep/2026") into course_info.
7. Return ONLY schema-valid JSON conforming to the canonical schema:
{
  "course_info": {
    "course_code": string|null,
    "course_name": string|null,
    "date": string|null,
    "instructor": string|null
  },
  "rows": [
    {
      "row_index": integer (1-based),
      "raw_roll": string|null,
      "raw_name": string|null,
      "raw_attendance": string|null,
      "visual_confidence": number (between 0.70 and 1.0),
      "evidence": string|null,
      "source_region": string|null
    }
  ]
}
Do NOT include any extra keys or markdown outside the JSON.
''';

  @override
  Future<Result<AiExtractionPayload, Failure>> extractAttendance({
    required Uint8List documentBytes,
    required String mimeType,
    String? userPromptContext,
  }) async {
    if (apiKey.isEmpty) {
      return const Err(ValidationFailure('Gemini API key is missing. Please configure it in Settings or the Scan dialog.'));
    }

    try {
      final base64Doc = base64Encode(documentBytes);

      final promptText = 'Extract all student attendance rows visibly present in this document according to the required schema. '
          'The document may be a handwritten paper sheet, notebook page, printed sheet, or screenshot. '
          'If the list shows roll numbers (e.g. "F24-588", "- 552", "693") or student names written on lines or paper, extract each entry as a row. '
          'For prefix roll dashes like "- 552", extract the roll number ("552" or "-552"). '
          'If the list records attendees without explicit absent marks, mark raw_attendance as "P". '
          '${userPromptContext != null ? 'Context: $userPromptContext' : ''}';

      // 1. Build Candidate Models list starting with dynamic discovery
      final candidates = await _resolveCandidateModels();

      http.Response? successfulResponse;
      int? lastStatusCode;
      String? lastResponseBody;

      for (int i = 0; i < candidates.length; i++) {
        final currentModel = candidates[i];
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$currentModel:generateContent?key=$apiKey',
        );

        // Try first with structured schema
        final bodyWithSchema = _buildRequestBody(base64Doc, mimeType, promptText, includeSchema: true);
        var res = await _client.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(bodyWithSchema),
        );

        // If rejected due to schema configuration, retry without schema (plain JSON instruction)
        if (res.statusCode == 400 && res.body.contains('schema')) {
          final bodyWithoutSchema = _buildRequestBody(base64Doc, mimeType, promptText, includeSchema: false);
          res = await _client.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(bodyWithoutSchema),
          );
        }

        lastStatusCode = res.statusCode;
        lastResponseBody = res.body;

        if (res.statusCode == 200) {
          successfulResponse = res;
          _workingModelCache[apiKey] = currentModel;
          break;
        }

        // If Google provides an explicit suggestion in the error message (e.g. "Please update your code to use models/gemini-3.1-pro-preview"),
        // extract the suggested model and queue it immediately!
        final suggested = _extractSuggestedModel(res.body);
        if (suggested != null && !candidates.contains(suggested)) {
          candidates.insert(i + 1, suggested);
        }

        // If it's a critical auth or quota error (401, 403, 429), stop looping to avoid wasting calls
        if (res.statusCode == 401 || res.statusCode == 403 || res.statusCode == 429) {
          break;
        }
      }

      if (successfulResponse == null) {
        return Err(AiExtractionFailure('Gemini API error ($lastStatusCode): $lastResponseBody'));
      }

      final responseJson = jsonDecode(successfulResponse.body) as Map<String, dynamic>;
      final candidatesList = responseJson['candidates'] as List?;
      if (candidatesList == null || candidatesList.isEmpty) {
        return const Err(AiExtractionFailure('Gemini returned no candidates'));
      }

      final candidate = candidatesList.first as Map<String, dynamic>;
      final content = candidate['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      final text = parts?.first?['text'] as String?;

      if (text == null || text.trim().isEmpty) {
        return const Err(AiExtractionFailure('Gemini candidate had empty content text'));
      }

      return AiContractValidator.validate(text);
    } catch (e) {
      return Err(AiExtractionFailure('Network or parsing error calling Gemini: $e'));
    }
  }

  Map<String, dynamic> _buildRequestBody(
    String base64Doc,
    String mimeType,
    String promptText, {
    required bool includeSchema,
  }) {
    final body = <String, dynamic>{
      'system_instruction': {
        'parts': [
          {'text': systemInstruction}
        ]
      },
      'contents': [
        {
          'parts': [
            {
              'inline_data': {
                'mime_type': mimeType,
                'data': base64Doc,
              }
            },
            {
              'text': promptText,
            }
          ]
        }
      ],
    };

    if (includeSchema) {
      body['generationConfig'] = {
        'response_mime_type': 'application/json',
        'response_schema': {
          'type': 'OBJECT',
          'properties': {
            'course_info': {
              'type': 'OBJECT',
              'properties': {
                'course_code': {'type': 'STRING'},
                'course_name': {'type': 'STRING'},
                'date': {'type': 'STRING'},
                'instructor': {'type': 'STRING'},
              },
            },
            'rows': {
              'type': 'ARRAY',
              'items': {
                'type': 'OBJECT',
                'properties': {
                  'row_index': {'type': 'INTEGER'},
                  'raw_roll': {'type': 'STRING'},
                  'raw_name': {'type': 'STRING'},
                  'raw_attendance': {'type': 'STRING'},
                  'visual_confidence': {'type': 'NUMBER'},
                  'evidence': {'type': 'STRING'},
                  'source_region': {'type': 'STRING'},
                },
                'required': ['row_index', 'visual_confidence'],
              },
            },
          },
          'required': ['rows'],
        },
      };
    } else {
      body['generationConfig'] = {
        'response_mime_type': 'application/json',
      };
    }

    return body;
  }

  /// Automatically discovers available models from the Google API for this user's API key
  Future<List<String>> _resolveCandidateModels() async {
    final list = <String>[];

    // 1. Cached verified model for this key has highest priority
    final cached = _workingModelCache[apiKey];
    if (cached != null) {
      list.add(cached);
    }

    // 2. Explicitly selected model if not 'auto'
    if (modelName.isNotEmpty && modelName != 'auto' && !list.contains(modelName)) {
      list.add(modelName);
    }

    // 3. Query Google models.list endpoint directly for active models supporting generateContent
    final discovered = await discoverAvailableModels(apiKey, client: _client);
    for (final m in discovered) {
      if (!list.contains(m)) list.add(m);
    }

    // 4. Default fallback candidates in ranked preference
    final standardDefaults = [
      'gemini-1.5-flash',
      'gemini-1.5-flash-latest',
      'gemini-2.0-flash',
      'gemini-2.5-flash',
      'gemini-3.1-pro-preview',
      'gemini-1.5-pro',
      'gemini-1.5-pro-latest',
    ];

    for (final d in standardDefaults) {
      if (!list.contains(d)) list.add(d);
    }

    return list;
  }

  /// Extracts any model Google suggests in error text (e.g. "models/gemini-3.1-pro-preview")
  String? _extractSuggestedModel(String? errorBody) {
    if (errorBody == null || errorBody.isEmpty) return null;
    final match = RegExp(r'models\/([a-zA-Z0-9\.\-_]+)').firstMatch(errorBody);
    return match?.group(1);
  }

  /// Static method to query Google Generative Language API and discover supported models for a key
  static Future<List<String>> discoverAvailableModels(String apiKey, {http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final listUrl = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey');
      final res = await c.get(listUrl);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final models = (data['models'] as List?) ?? [];

        final flashModels = <String>[];
        final proOrPreviewModels = <String>[];
        final otherModels = <String>[];

        for (final m in models) {
          final name = (m['name'] as String? ?? '').replaceFirst('models/', '');
          final methods = (m['supportedGenerationMethods'] as List?) ?? [];

          // Only consider models that support generateContent and are not embedding-only
          if (methods.contains('generateContent') && !name.contains('embedding')) {
            if (name.contains('flash')) {
              flashModels.add(name);
            } else if (name.contains('pro') || name.contains('preview')) {
              proOrPreviewModels.add(name);
            } else {
              otherModels.add(name);
            }
          }
        }

        // Return sorted with Flash first (fastest/generous quota), then Pro/Preview, then others
        return [...flashModels, ...proOrPreviewModels, ...otherModels];
      }
    } catch (_) {
      // Network or API listing error; fallback candidates will be used
    }
    return [];
  }
}
