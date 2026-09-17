import 'package:flutter_test/flutter_test.dart';
import 'package:attendium/domain/enums/attendance_classification.dart';
import 'package:attendium/domain/enums/attendance_status.dart';
import 'package:attendium/domain/services/attendance_calculator.dart';

void main() {
  group('AttendanceCalculator Tests', () {
    test('100% Present calculation', () {
      final records = List.generate(
        10,
        (i) => SessionRecordInput(
          sessionId: 's$i',
          status: AttendanceStatus.present,
        ),
      );

      final result = AttendanceCalculator.calculate(records: records);

      expect(result.totalSessions, 10);
      expect(result.presentCount, 10);
      expect(result.percentage, 100.0);
      expect(result.classification, AttendanceClassification.safe);
      expect(result.classesNeededForThreshold, 0);
      // At 75% threshold, with 10 attended out of 10, allowed absences = floor((10 - 7.5)/0.75) = floor(3.33) = 3
      expect(result.absencesAllowedBeforeThreshold, 3);
    });

    test('Late weight calculation (0.5 weight)', () {
      // 8 Present (8 points), 2 Late (1 point), 0 Absent => 9 points / 10 counted = 90%
      final records = [
        ...List.generate(
          8,
          (i) => SessionRecordInput(
            sessionId: 'p$i',
            status: AttendanceStatus.present,
          ),
        ),
        ...List.generate(
          2,
          (i) => SessionRecordInput(
            sessionId: 'l$i',
            status: AttendanceStatus.late,
          ),
        ),
      ];

      final result = AttendanceCalculator.calculate(
        records: records,
        policy: const AttendancePolicyConfig(lateWeight: 0.5),
      );

      expect(result.totalSessions, 10);
      expect(result.presentCount, 8);
      expect(result.lateCount, 2);
      expect(result.weightedAttended, 9.0);
      expect(result.weightedCounted, 10.0);
      expect(result.percentage, 90.0);
      expect(result.classification, AttendanceClassification.safe);
    });

    test('Excused exclusion vs inclusion', () {
      final records = [
        const SessionRecordInput(sessionId: '1', status: AttendanceStatus.present),
        const SessionRecordInput(sessionId: '2', status: AttendanceStatus.excused),
      ];

      // Excluded: 1 attended / 1 counted = 100%
      final resExcluded = AttendanceCalculator.calculate(
        records: records,
        policy: const AttendancePolicyConfig(excusedCounted: false),
      );
      expect(resExcluded.weightedAttended, 1.0);
      expect(resExcluded.weightedCounted, 1.0);
      expect(resExcluded.percentage, 100.0);

      // Included: 1 attended / 2 counted = 50%
      final resIncluded = AttendanceCalculator.calculate(
        records: records,
        policy: const AttendancePolicyConfig(excusedCounted: true),
      );
      expect(resIncluded.weightedAttended, 1.0);
      expect(resIncluded.weightedCounted, 2.0);
      expect(resIncluded.percentage, 50.0);
    });

    test('Threshold classification boundaries: Safe, At-Risk, Short, Debarred', () {
      // 7 out of 10 = 70% -> With threshold 75%, at-risk delta 10% (65-75%), this is At Risk
      final atRiskRecords = [
        ...List.generate(7, (i) => SessionRecordInput(sessionId: 'p$i', status: AttendanceStatus.present)),
        ...List.generate(3, (i) => SessionRecordInput(sessionId: 'a$i', status: AttendanceStatus.absent)),
      ];
      final resAtRisk = AttendanceCalculator.calculate(records: atRiskRecords);
      expect(resAtRisk.percentage, 70.0);
      expect(resAtRisk.classification, AttendanceClassification.atRisk);
      // To reach 75%: (7 + X)/(10 + X) >= 0.75 => 7 + X >= 7.5 + 0.75X => 0.25X >= 0.5 => X >= 2
      expect(resAtRisk.classesNeededForThreshold, 2);
      expect(resAtRisk.absencesAllowedBeforeThreshold, 0);

      // 6 out of 10 = 60% -> Short attendance (50-64.9%)
      final shortRecords = [
        ...List.generate(6, (i) => SessionRecordInput(sessionId: 'p$i', status: AttendanceStatus.present)),
        ...List.generate(4, (i) => SessionRecordInput(sessionId: 'a$i', status: AttendanceStatus.absent)),
      ];
      final resShort = AttendanceCalculator.calculate(records: shortRecords);
      expect(resShort.percentage, 60.0);
      expect(resShort.classification, AttendanceClassification.short);

      // 4 out of 10 = 40% -> Debarred (< 50%)
      final debarredRecords = [
        ...List.generate(4, (i) => SessionRecordInput(sessionId: 'p$i', status: AttendanceStatus.present)),
        ...List.generate(6, (i) => SessionRecordInput(sessionId: 'a$i', status: AttendanceStatus.absent)),
      ];
      final resDebarred = AttendanceCalculator.calculate(records: debarredRecords);
      expect(resDebarred.percentage, 40.0);
      expect(resDebarred.classification, AttendanceClassification.debarred);
    });
  });
}
