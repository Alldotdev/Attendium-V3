import 'dart:convert';
import '../../core/errors/failures.dart';
import '../../core/result/result.dart';
import 'ai_models.dart';

/// Validates raw AI JSON responses against the canonical Attendium schema (Section 41).
class AiContractValidator {
  const AiContractValidator._();

  static const Set<String> allowedPayloadKeys = {'course_info', 'rows'};
  static const Set<String> allowedCourseKeys = {'course_code', 'course_name', 'date', 'instructor'};
  static const Set<String> allowedRowKeys = {
    'row_index',
    'raw_roll',
    'raw_name',
    'raw_attendance',
    'visual_confidence',
    'evidence',
    'source_region',
  };

  /// Parses and strictly validates JSON string from AI model.
  static Result<AiExtractionPayload, Failure> validate(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        return const Err(AiExtractionFailure('AI response root must be a JSON object'));
      }

      // Check for unexpected root keys
      for (final key in decoded.keys) {
        if (!allowedPayloadKeys.contains(key)) {
          return Err(AiExtractionFailure('Unexpected root key in AI response: $key'));
        }
      }

      // Validate course_info
      AiCourseInfo? courseInfo;
      if (decoded.containsKey('course_info') && decoded['course_info'] != null) {
        final cJson = decoded['course_info'];
        if (cJson is! Map<String, dynamic>) {
          return const Err(AiExtractionFailure('course_info must be a JSON object'));
        }
        for (final key in cJson.keys) {
          if (!allowedCourseKeys.contains(key)) {
            return Err(AiExtractionFailure('Unexpected key in course_info: $key'));
          }
        }
        courseInfo = AiCourseInfo.fromJson(cJson);
      }

      // Validate rows
      if (!decoded.containsKey('rows') || decoded['rows'] is! List) {
        return const Err(AiExtractionFailure('AI response must contain a "rows" array'));
      }

      final rawRowsList = decoded['rows'] as List;
      final validatedRows = <AiExtractedRow>[];

      for (int i = 0; i < rawRowsList.length; i++) {
        final rowItem = rawRowsList[i];
        if (rowItem is! Map<String, dynamic>) {
          return Err(AiExtractionFailure('Row at index $i is not a JSON object'));
        }

        // Check for unexpected row keys
        for (final key in rowItem.keys) {
          if (!allowedRowKeys.contains(key)) {
            return Err(AiExtractionFailure('Unexpected key "$key" in row at index $i'));
          }
        }

        // Validate row_index
        final rowIndex = rowItem['row_index'];
        if (rowIndex == null || rowIndex is! int) {
          return Err(AiExtractionFailure('Row at index $i must have an integer "row_index"'));
        }

        // Validate visual_confidence
        final conf = rowItem['visual_confidence'];
        if (conf == null || conf is! num) {
          return Err(AiExtractionFailure('Row at index $i must have a numeric "visual_confidence"'));
        }
        final doubleConf = conf.toDouble();
        if (doubleConf < 0.0 || doubleConf > 1.0) {
          return Err(AiExtractionFailure('Row at index $i visual_confidence must be between 0.0 and 1.0'));
        }

        validatedRows.add(AiExtractedRow.fromJson(rowItem));
      }

      // Ensure rows are sorted by row_index
      validatedRows.sort((a, b) => a.rowIndex.compareTo(b.rowIndex));

      return Success(AiExtractionPayload(
        courseInfo: courseInfo,
        rows: validatedRows,
        rawResponseJson: jsonString,
      ));
    } catch (e) {
      return Err(AiExtractionFailure('Failed to parse AI response JSON: $e'));
    }
  }
}
