import 'package:flutter_test/flutter_test.dart';
import 'package:attendium/domain/enums/attendance_status.dart';
import 'package:attendium/domain/enums/match_confidence_band.dart';
import 'package:attendium/domain/services/fuzzy_matcher.dart';
import 'package:attendium/domain/services/jaro_winkler_distance.dart';
import 'package:attendium/domain/services/levenshtein_distance.dart';
import 'package:attendium/domain/services/student_normalizer.dart';
import 'package:attendium/infrastructure/document/text_attendance_parser.dart';

void main() {
  group('LevenshteinDistance Tests', () {
    test('Identical strings return distance 0 and similarity 1.0', () {
      expect(LevenshteinDistance.distance('CS-101', 'CS-101'), 0);
      expect(LevenshteinDistance.similarity('CS-101', 'CS-101'), 1.0);
    });

    test('Single substitution distance 1', () {
      expect(LevenshteinDistance.distance('kitten', 'sitten'), 1);
      expect(LevenshteinDistance.similarity('kitten', 'sitten'), closeTo(5 / 6, 0.01));
    });
  });

  group('JaroWinklerDistance Tests', () {
    test('Prefix match bonus', () {
      final sim = JaroWinklerDistance.similarity('martha', 'marhta');
      expect(sim, greaterThan(0.90));
    });

    test('Completely different strings return 0.0', () {
      expect(JaroWinklerDistance.similarity('abc', 'xyz'), 0.0);
    });
  });

  group('StudentNormalizer Tests', () {
    test('Normalizes diacritics and whitespace', () {
      expect(
        StudentNormalizer.normalizeName('  José   María-Gómez  '),
        'jose maria gomez',
      );
    });

    test('Normalizes roll number and applies OCR fixes in digit context', () {
      // 'CS-202O' where O is in digit context -> 'CS2020'
      expect(
        StudentNormalizer.normalizeRoll('CS-202O'),
        'CS2020',
      );
      // 'BCS-I01' where I is between letters/digits -> 'BCS101'
      expect(
        StudentNormalizer.normalizeRoll('BCS-I01'),
        'BCS101',
      );
    });
  });

  group('FuzzyMatcher Tests', () {
    final candidates = [
      const StudentMatchCandidate(
        id: '1',
        rollNumber: 'CS-2026-001',
        fullName: 'Johnathan Alexander Smith',
        normalizedName: 'johnathan alexander smith',
        aliases: ['Johnny Smith', 'John Smith'],
      ),
      const StudentMatchCandidate(
        id: '2',
        rollNumber: 'CS-2026-002',
        fullName: 'Sarah Elizabeth Connor',
        normalizedName: 'sarah elizabeth connor',
      ),
      const StudentMatchCandidate(
        id: '3',
        rollNumber: 'CS-2026-003',
        fullName: 'Muhammad Usman Khan',
        normalizedName: 'muhammad usman khan',
        aliases: ['Usman Khan'],
      ),
    ];

    final matcher = const FuzzyMatcher();

    test('Exact roll and close name achieves autoAccept', () {
      final results = matcher.match(
        rawRoll: 'CS-2026-001',
        rawName: 'John Smith',
        candidates: candidates,
      );

      expect(results.isNotEmpty, true);
      final best = results.first;
      expect(best.candidate?.id, '1');
      expect(best.band, MatchConfidenceBand.autoAccept);
      expect(best.finalScore, greaterThanOrEqualTo(0.95));
    });

    test('OCR corrupted roll resolves to correct candidate', () {
      // 'CS-2026-OO3' has OCR letters O instead of 0
      final results = matcher.match(
        rawRoll: 'CS-2026-OO3',
        rawName: 'Usman Khan',
        candidates: candidates,
      );

      expect(results.isNotEmpty, true);
      final best = results.first;
      expect(best.candidate?.id, '3');
      expect(best.isMatched, true);
    });

    test('Unmatched student returns score below threshold', () {
      final results = matcher.match(
        rawRoll: 'EE-9999-888',
        rawName: 'Unknown Visitor',
        candidates: candidates,
      );

      expect(results.isNotEmpty, true);
      final best = results.first;
      expect(best.band, MatchConfidenceBand.unmatched);
      expect(best.finalScore, lessThan(0.70));
    });

    test('Suffix roll number 588 matches F24-588 with autoAccept confidence', () {
      final candidatesWithF24 = [
        ...candidates,
        const StudentMatchCandidate(
          id: '4',
          rollNumber: 'F24-588',
          fullName: 'Hamza Ali',
          normalizedName: 'hamza ali',
          isEnrolledInClassroom: true,
        ),
      ];

      // Roll-only test with suffix "588"
      final results = matcher.match(
        rawRoll: '588',
        rawName: null,
        candidates: candidatesWithF24,
      );

      expect(results.isNotEmpty, true);
      final best = results.first;
      expect(best.candidate?.id, '4');
      expect(best.band, MatchConfidenceBand.autoAccept);
      expect(best.finalScore, greaterThanOrEqualTo(0.95));
    });

    test('Single-digit roll number 1 matches CS-2026-001 with autoAccept confidence', () {
      final results = matcher.match(
        rawRoll: '1',
        rawName: null,
        candidates: candidates,
      );

      expect(results.isNotEmpty, true);
      final best = results.first;
      expect(best.candidate?.id, '1');
      expect(best.band, MatchConfidenceBand.autoAccept);
      expect(best.finalScore, greaterThanOrEqualTo(0.95));
    });

    test('Name-only input matches candidate with high confidence', () {
      final results = matcher.match(
        rawRoll: null,
        rawName: 'Sarah Elizabeth Connor',
        candidates: candidates,
      );

      expect(results.isNotEmpty, true);
      final best = results.first;
      expect(best.candidate?.id, '2');
      expect(best.band, MatchConfidenceBand.autoAccept);
      expect(best.finalScore, greaterThanOrEqualTo(0.95));
    });
  });

  group('TextAttendanceParser Tests', () {
    test('Parses comma-separated roll numbers with default status', () {
      final entries = TextAttendanceParser.parse('588, 589, 590');
      expect(entries.length, 3);
      expect(entries[0].roll, '588');
      expect(entries[0].status, AttendanceStatus.present);
      expect(entries[1].roll, '589');
      expect(entries[2].roll, '590');
    });

    test('Parses multi-line text with explicit statuses', () {
      const text = '''
F24-588 P
589 A
CS-042 Present
John Smith L
''';
      final entries = TextAttendanceParser.parse(text);
      expect(entries.length, 4);

      expect(entries[0].roll, 'F24-588');
      expect(entries[0].status, AttendanceStatus.present);

      expect(entries[1].roll, '589');
      expect(entries[1].status, AttendanceStatus.absent);

      expect(entries[2].roll, 'CS-042');
      expect(entries[2].status, AttendanceStatus.present);

      expect(entries[3].name, 'John Smith');
      expect(entries[3].status, AttendanceStatus.late);
    });

    test('Parses handwritten notebook list with bullet dashes and matches against roster', () {
      const handwrittenText = '''
16/sep/2026
S
F24-588
F24-1319
- 552
- 693
- 651
- 561
- 570
- 580
- 705
- 541
- 577
- 549
- 701
- 747
- 543
- 716
''';
      final entries = TextAttendanceParser.parse(handwrittenText, defaultStatus: AttendanceStatus.present);
      expect(entries.any((e) => e.roll == 'F24-588'), isTrue);
      expect(entries.any((e) => e.roll == '552'), isTrue);
      expect(entries.any((e) => e.roll == '693'), isTrue);
      expect(entries.any((e) => e.roll == '716'), isTrue);

      // Verify all student entries are marked Present (not Absent despite leading dash)
      for (final e in entries.where((e) => e.roll != null && e.roll!.contains(RegExp(r'\d')))) {
        expect(e.status, AttendanceStatus.present);
      }

      // Match suffix 552 against candidate F24-552
      const candidate552 = StudentMatchCandidate(
        id: 'std_552',
        rollNumber: 'F24-552',
        fullName: 'Zainab Ahmed',
        normalizedName: 'zainab ahmed',
        isEnrolledInClassroom: true,
      );

      final matchRes = const FuzzyMatcher().match(
        rawRoll: '552',
        rawName: null,
        candidates: [candidate552],
      );

      expect(matchRes.isNotEmpty, isTrue);
      expect(matchRes.first.candidate?.id, 'std_552');
      expect(matchRes.first.band, MatchConfidenceBand.autoAccept);
      expect(matchRes.first.finalScore, greaterThanOrEqualTo(0.95));
    });
  });
}


