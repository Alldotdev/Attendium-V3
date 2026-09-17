import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendium/infrastructure/ai/ai_contract_validator.dart';
import 'package:attendium/infrastructure/ai/deterministic_local_provider.dart';
import 'package:attendium/infrastructure/document/document_hasher.dart';
import 'package:attendium/infrastructure/document/tabular_parser.dart';

void main() {
  group('AiContractValidator Tests (Directive Section 41)', () {
    test('Valid canonical JSON passes validation with correct ordering', () {
      final validJson = jsonEncode({
        'course_info': {
          'course_code': 'CS-301',
          'course_name': 'Operating Systems',
          'date': '2026-09-17',
          'instructor': 'Prof. Linus',
        },
        'rows': [
          {
            'row_index': 2,
            'raw_roll': 'CS-002',
            'raw_name': 'Bob Vance',
            'raw_attendance': 'A',
            'visual_confidence': 0.94,
            'evidence': 'A mark at row 2',
          },
          {
            'row_index': 1,
            'raw_roll': 'CS-001',
            'raw_name': 'Alice Cooper',
            'raw_attendance': 'P',
            'visual_confidence': 0.99,
            'evidence': 'P mark at row 1',
          }
        ]
      });

      final result = AiContractValidator.validate(validJson);
      expect(result.isSuccess, true);
      final payload = result.successOrNull!;
      expect(payload.courseInfo?.courseCode, 'CS-301');
      expect(payload.rows.length, 2);
      // Verify row order was sorted by row_index
      expect(payload.rows[0].rowIndex, 1);
      expect(payload.rows[1].rowIndex, 2);
      expect(payload.rows[0].rawName, 'Alice Cooper');
    });

    test('Rejects hallucinated unexpected root property', () {
      final invalidJson = jsonEncode({
        'hallucinated_property': 'injected_text',
        'rows': []
      });

      final result = AiContractValidator.validate(invalidJson);
      expect(result.isFailure, true);
      expect(result.errorOrNull?.message.contains('Unexpected root key'), true);
    });

    test('Rejects hallucinated unexpected row property', () {
      final invalidJson = jsonEncode({
        'rows': [
          {
            'row_index': 1,
            'visual_confidence': 0.9,
            'hallucinated_column': 'should fail',
          }
        ]
      });

      final result = AiContractValidator.validate(invalidJson);
      expect(result.isFailure, true);
      expect(result.errorOrNull?.message.contains('Unexpected key'), true);
    });

    test('Rejects invalid confidence range (e.g. 1.5)', () {
      final invalidJson = jsonEncode({
        'rows': [
          {
            'row_index': 1,
            'visual_confidence': 1.5,
          }
        ]
      });

      final result = AiContractValidator.validate(invalidJson);
      expect(result.isFailure, true);
      expect(result.errorOrNull?.message.contains('visual_confidence must be between 0.0 and 1.0'), true);
    });
  });

  group('TabularParser Tests', () {
    test('Parses CSV with header detection', () {
      const csvData = '''Roll Number,Full Name,Attendance,Date
CS-101,John Doe,Present,2026-09-01
CS-102,Jane Roe,Absent,2026-09-01
''';

      final result = TabularParser.parseCsv(csvData);
      expect(result.isSuccess, true);
      final parse = result.successOrNull!;
      expect(parse.totalRows, 2);
      expect(parse.rows[0].roll, 'CS-101');
      expect(parse.rows[0].name, 'John Doe');
      expect(parse.rows[0].attendance, 'Present');
      expect(parse.rows[1].roll, 'CS-102');
      expect(parse.rows[1].attendance, 'Absent');
    });
  });

  group('DocumentHasher Tests', () {
    test('Computes deterministic SHA-256 hash', () {
      final hash1 = DocumentHasher.hashString('Attendium Document Content');
      final hash2 = DocumentHasher.hashString('Attendium Document Content');
      final hash3 = DocumentHasher.hashString('Different Content');

      expect(hash1, hash2);
      expect(hash1, isNot(hash3));
      expect(hash1.length, 64);
    });
  });

  group('DeterministicLocalProvider Tests', () {
    test('Extracts tabular data into validated canonical payload', () async {
      final provider = DeterministicLocalProvider();
      const csv = 'Roll,Name,Status\nCS-01,Carl Sagan,P\nCS-02,Richard Feynman,L\n';
      final bytes = Uint8List.fromList(utf8.encode(csv));

      final result = await provider.extractAttendance(
        documentBytes: bytes,
        mimeType: 'text/csv',
      );

      expect(result.isSuccess, true);
      final payload = result.successOrNull!;
      expect(payload.rows.length, 2);
      expect(payload.rows[0].rawRoll, 'CS-01');
      expect(payload.rows[0].rawName, 'Carl Sagan');
      expect(payload.rows[0].visualConfidence, greaterThanOrEqualTo(0.95));
    });
  });
}
