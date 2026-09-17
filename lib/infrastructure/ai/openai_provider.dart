import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../core/errors/failures.dart';
import '../../core/result/result.dart';
import 'ai_contract_validator.dart';
import 'ai_models.dart';
import 'ai_provider.dart';

/// OpenAI / Compatible Provider (supports OpenAI, Cursor proxy, Groq, OpenRouter, Ollama).
class OpenAiProvider implements AiProvider {
  final String apiKey;
  final String modelName;
  final String baseUrl;
  final String _customProviderName;
  final http.Client _client;

  OpenAiProvider({
    required this.apiKey,
    this.modelName = 'gpt-4o',
    String? baseUrl,
    String? providerName,
    http.Client? client,
  })  : baseUrl = (baseUrl != null && baseUrl.trim().isNotEmpty) ? baseUrl.trim() : 'https://api.openai.com/v1',
        _customProviderName = providerName ?? 'openai',
        _client = client ?? http.Client();

  @override
  String get providerName => _customProviderName;

  static const String systemInstruction = '''
You are Attendium's specialized academic attendance-document extraction engine.
Extract only information visibly present in the supplied document or photo.
The document can be a printed attendance sheet or a handwritten paper sheet/notebook page with student roll numbers or names.
1. Preserve row order as visually laid out from top to bottom.
2. Read handwriting carefully. If the first entries establish a roll number pattern (e.g. "F24-588", "F24-1319") and subsequent entries only have leading dashes or suffixes (e.g. "- 552", "- 693", "651"), extract each entry. For "- 552", set raw_roll to "552" or "F24-552".
3. If an entry has only a roll number, set raw_name to null.
4. If the document is an attendee list without explicit absent marks, set raw_attendance to "P".
5. Return only schema-valid JSON matching the schema: {"course_info": {"course_code": string|null, "course_name": string|null, "date": string|null, "instructor": string|null}, "rows": [{"row_index": int, "raw_roll": string|null, "raw_name": string|null, "raw_attendance": string|null, "visual_confidence": number, "evidence": string|null, "source_region": string|null}]}.
''';

  @override
  Future<Result<AiExtractionPayload, Failure>> extractAttendance({
    required Uint8List documentBytes,
    required String mimeType,
    String? userPromptContext,
  }) async {
    if (apiKey.isEmpty) {
      return const Err(ValidationFailure('OpenAI API key is missing. Please configure it in Settings or the Scan dialog.'));
    }

    try {
      final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
      final url = Uri.parse('$cleanBase/chat/completions');
      final base64Doc = base64Encode(documentBytes);

      final imageUrl = 'data:$mimeType;base64,$base64Doc';

      final requestBody = {
        'model': modelName,
        'response_format': {'type': 'json_object'},
        'messages': [
          {'role': 'system', 'content': systemInstruction},
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': 'Extract all student attendance rows visibly present in this document according to the required schema. '
                    'The document may be a handwritten paper sheet, notebook page, printed sheet, or screenshot. '
                    'If the list shows roll numbers (e.g. "F24-588", "- 552", "693") or student names written on lines or paper, extract each entry as a row. '
                    'For prefix roll dashes like "- 552", extract the roll number ("552" or "-552"). '
                    'If the list records attendees without explicit absent marks, mark raw_attendance as "P". '
                    '${userPromptContext != null ? 'Context: $userPromptContext' : ''}',
              },
              {
                'type': 'image_url',
                'image_url': {'url': imageUrl},
              }
            ]
          }
        ]
      };

      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200) {
        return Err(AiExtractionFailure('OpenAI API error (${response.statusCode}): ${response.body}'));
      }

      final responseJson = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = responseJson['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        return const Err(AiExtractionFailure('OpenAI returned no choices'));
      }

      final message = choices.first['message'] as Map<String, dynamic>?;
      final content = message?['content'] as String?;

      if (content == null || content.trim().isEmpty) {
        return const Err(AiExtractionFailure('OpenAI returned empty message content'));
      }

      return AiContractValidator.validate(content);
    } catch (e) {
      return Err(AiExtractionFailure('Network or parsing error calling OpenAI: $e'));
    }
  }
}
