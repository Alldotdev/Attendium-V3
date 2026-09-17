import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../core/errors/failures.dart';
import '../../core/result/result.dart';
import 'ai_contract_validator.dart';
import 'ai_models.dart';
import 'ai_provider.dart';

/// Anthropic Claude AI Provider using Messages API with multimodal vision.
class ClaudeProvider implements AiProvider {
  final String apiKey;
  final String modelName;
  final http.Client _client;

  ClaudeProvider({
    required this.apiKey,
    this.modelName = 'claude-3-5-sonnet-20241022',
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  String get providerName => 'claude';

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
7. Return ONLY valid JSON conforming to the canonical schema:
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
Do NOT include markdown backticks (```json) or conversational text outside the JSON.
''';

  @override
  Future<Result<AiExtractionPayload, Failure>> extractAttendance({
    required Uint8List documentBytes,
    required String mimeType,
    String? userPromptContext,
  }) async {
    if (apiKey.isEmpty) {
      return const Err(ValidationFailure('Anthropic Claude API key is missing. Please configure it in Settings or the Scan dialog.'));
    }

    try {
      final base64Doc = base64Encode(documentBytes);

      // Map mime types to Claude supported media types
      String mediaType = mimeType;
      if (mediaType == 'image/jpg') mediaType = 'image/jpeg';
      if (!['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'application/pdf'].contains(mediaType)) {
        mediaType = 'image/jpeg';
      }

      final promptText = 'Extract all student attendance rows visibly present in this document according to the required schema. '
          'The document may be a handwritten paper sheet, notebook page, printed sheet, or screenshot. '
          'If the list shows roll numbers (e.g. "F24-588", "- 552", "693") or student names written on lines or paper, extract each entry as a row. '
          'For prefix roll dashes like "- 552", extract the roll number ("552" or "-552"). '
          'If the list records attendees without explicit absent marks, mark raw_attendance as "P". '
          '${userPromptContext != null ? 'Context: $userPromptContext' : ''}';

      final candidateModels = [
        modelName,
        if (modelName != 'claude-3-5-sonnet-20241022') 'claude-3-5-sonnet-20241022',
        if (modelName != 'claude-3-5-sonnet-latest') 'claude-3-5-sonnet-latest',
        if (modelName != 'claude-3-haiku-20240307') 'claude-3-haiku-20240307',
      ];

      http.Response? response;
      int? lastStatusCode;
      String? lastResponseBody;

      for (final model in candidateModels) {
        final requestBody = {
          'model': model,
          'max_tokens': 4096,
          'system': systemInstruction,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image',
                  'source': {
                    'type': 'base64',
                    'media_type': mediaType,
                    'data': base64Doc,
                  }
                },
                {
                  'type': 'text',
                  'text': promptText,
                }
              ]
            }
          ]
        };

        final res = await _client.post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
          },
          body: jsonEncode(requestBody),
        );

        lastStatusCode = res.statusCode;
        lastResponseBody = res.body;

        if (res.statusCode == 200) {
          response = res;
          break;
        }

        // If not a 404, don't try alternate models (e.g. invalid key or rate limit)
        if (res.statusCode != 404) {
          break;
        }
      }

      if (response == null) {
        return Err(AiExtractionFailure('Claude API error ($lastStatusCode): $lastResponseBody'));
      }

      final responseJson = jsonDecode(response.body) as Map<String, dynamic>;
      final contentBlocks = responseJson['content'] as List?;
      if (contentBlocks == null || contentBlocks.isEmpty) {
        return const Err(AiExtractionFailure('Claude returned empty content blocks'));
      }

      final textBlock = contentBlocks.firstWhere(
        (b) => b['type'] == 'text',
        orElse: () => null,
      );

      final text = textBlock?['text'] as String?;
      if (text == null || text.trim().isEmpty) {
        return const Err(AiExtractionFailure('Claude text content was empty'));
      }

      return AiContractValidator.validate(text);
    } catch (e) {
      return Err(AiExtractionFailure('Network or parsing error calling Claude: $e'));
    }
  }
}
