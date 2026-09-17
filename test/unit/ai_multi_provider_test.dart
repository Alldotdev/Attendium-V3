import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:attendium/infrastructure/ai/claude_provider.dart';
import 'package:attendium/infrastructure/ai/gemini_provider.dart';
import 'package:attendium/infrastructure/ai/openai_provider.dart';

void main() {
  group('GeminiProvider Autonomous Discovery & Self-Healing Tests', () {
    test('Gemini automatically queries models.list and retries on suggested preview model', () async {
      final requestedUrls = <String>[];

      final mockClient = MockClient((request) async {
        requestedUrls.add(request.url.toString());

        // 1. models.list endpoint call
        if (request.url.path.endsWith('/models') && request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'models': [
                {
                  'name': 'models/gemini-2.5-pro',
                  'supportedGenerationMethods': ['generateContent'],
                },
                {
                  'name': 'models/gemini-1.5-flash',
                  'supportedGenerationMethods': ['generateContent'],
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        // 2. If called with gemini-2.5-pro, simulate Google's exact 404 deprecation error with suggested model
        if (request.url.path.contains('gemini-2.5-pro:generateContent')) {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 404,
                'message': 'This model models/gemini-2.5-pro is no longer available to new users. Please update your code to use models/gemini-3.1-pro-preview for the latest features and improvements.',
                'status': 'NOT_FOUND',
              }
            }),
            404,
            headers: {'content-type': 'application/json'},
          );
        }

        // 3. When called with gemini-3.1-pro-preview (the dynamically suggested model), return success!
        if (request.url.path.contains('gemini-3.1-pro-preview:generateContent')) {
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'text': jsonEncode({
                          'course_info': {'course_code': 'CS-101'},
                          'rows': [
                            {
                              'row_index': 1,
                              'raw_roll': '588',
                              'raw_name': 'Ali',
                              'raw_attendance': 'P',
                              'visual_confidence': 0.95,
                            }
                          ]
                        })
                      }
                    ]
                  }
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('Not Found', 404);
      });

      final provider = GeminiProvider(
        apiKey: 'test-api-key',
        modelName: 'gemini-2.5-pro',
        client: mockClient,
      );

      final result = await provider.extractAttendance(
        documentBytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
      );

      expect(result.isSuccess, true);
      final payload = result.successOrNull!;
      expect(payload.rows.length, 1);
      expect(payload.rows.first.rawRoll, '588');

      // Verify that the suggested model (gemini-3.1-pro-preview) was dynamically queued and called
      expect(
        requestedUrls.any((u) => u.contains('gemini-3.1-pro-preview:generateContent')),
        true,
      );
      // Verify cached working model
      expect(provider.activeModelName, 'gemini-3.1-pro-preview');
    });
  });

  group('ClaudeProvider Tests', () {
    test('ClaudeProvider correctly constructs messages payload and extracts rows', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), 'https://api.anthropic.com/v1/messages');
        expect(request.headers['x-api-key'], 'ant-key-123');
        expect(request.headers['anthropic-version'], '2023-06-01');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], 'claude-3-5-sonnet-20241022');
        final messages = body['messages'] as List;
        expect(messages.first['role'], 'user');

        return http.Response(
          jsonEncode({
            'content': [
              {
                'type': 'text',
                'text': jsonEncode({
                  'course_info': {'course_code': 'CS-202'},
                  'rows': [
                    {
                      'row_index': 1,
                      'raw_roll': 'F24-588',
                      'raw_name': 'Usman Khan',
                      'raw_attendance': 'P',
                      'visual_confidence': 0.99,
                    }
                  ]
                })
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final provider = ClaudeProvider(
        apiKey: 'ant-key-123',
        client: mockClient,
      );

      final result = await provider.extractAttendance(
        documentBytes: Uint8List.fromList([10, 20, 30]),
        mimeType: 'image/png',
      );

      expect(result.isSuccess, true);
      final payload = result.successOrNull!;
      expect(payload.rows.first.rawRoll, 'F24-588');
      expect(payload.rows.first.rawName, 'Usman Khan');
    });
  });

  group('OpenAiProvider Customizable Endpoint Tests', () {
    test('OpenAiProvider respects custom base URL for Cursor / OpenRouter / Groq', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), 'https://openrouter.ai/api/v1/chat/completions');
        expect(request.headers['Authorization'], 'Bearer or-key-999');

        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'course_info': null,
                    'rows': [
                      {
                        'row_index': 1,
                        'raw_roll': '552',
                        'raw_name': null,
                        'raw_attendance': 'P',
                        'visual_confidence': 0.90,
                      }
                    ]
                  })
                }
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final provider = OpenAiProvider(
        apiKey: 'or-key-999',
        baseUrl: 'https://openrouter.ai/api/v1',
        modelName: 'google/gemini-2.5-flash',
        client: mockClient,
      );

      final result = await provider.extractAttendance(
        documentBytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
      );

      expect(result.isSuccess, true);
      expect(result.successOrNull!.rows.first.rawRoll, '552');
    });
  });
}
