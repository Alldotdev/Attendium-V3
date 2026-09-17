import 'dart:typed_data';
import '../../core/errors/failures.dart';
import '../../core/result/result.dart';
import 'ai_models.dart';

/// Abstract AI Provider interface.
/// Allows swapping Gemini, OpenAI, or local deterministic engines without changing domain logic.
abstract class AiProvider {
  String get providerName;

  Future<Result<AiExtractionPayload, Failure>> extractAttendance({
    required Uint8List documentBytes,
    required String mimeType,
    String? userPromptContext,
  });
}
