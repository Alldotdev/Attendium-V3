import 'dart:math';
import '../../core/constants/app_constants.dart';
import '../enums/attendance_classification.dart';
import '../enums/attendance_status.dart';

/// Policy configuration for calculating attendance.
class AttendancePolicyConfig {
  final double minimumPercentage;
  final double lateWeight;
  final bool excusedCounted;
  final double debarThreshold;
  final double atRiskDelta;

  const AttendancePolicyConfig({
    this.minimumPercentage = AppConstants.defaultAttendanceThreshold,
    this.lateWeight = AppConstants.defaultLateWeight,
    this.excusedCounted = AppConstants.defaultExcusedCounted,
    this.debarThreshold = AppConstants.defaultDebarThreshold,
    this.atRiskDelta = AppConstants.atRiskThresholdDelta,
  });
}

/// Record unit representing a session record for a student.
class SessionRecordInput {
  final String sessionId;
  final AttendanceStatus status;
  final double sessionCreditWeight;

  const SessionRecordInput({
    required this.sessionId,
    required this.status,
    this.sessionCreditWeight = 1.0,
  });
}

/// Comprehensive attendance calculation report for a student.
class AttendanceCalculationResult {
  final int totalSessions;
  final int presentCount;
  final int lateCount;
  final int excusedCount;
  final int absentCount;
  final int unmarkedCount;
  final double weightedAttended;
  final double weightedCounted;
  final double percentage;
  final AttendanceClassification classification;
  final int classesNeededForThreshold;
  final int absencesAllowedBeforeThreshold;

  const AttendanceCalculationResult({
    required this.totalSessions,
    required this.presentCount,
    required this.lateCount,
    required this.excusedCount,
    required this.absentCount,
    required this.unmarkedCount,
    required this.weightedAttended,
    required this.weightedCounted,
    required this.percentage,
    required this.classification,
    required this.classesNeededForThreshold,
    required this.absencesAllowedBeforeThreshold,
  });

  bool get isSafe => classification == AttendanceClassification.safe;
  bool get isAtRisk => classification == AttendanceClassification.atRisk;
  bool get isShort => classification == AttendanceClassification.short;
  bool get isDebarred => classification == AttendanceClassification.debarred;
}

/// Authoritative Attendance Calculation Engine.
class AttendanceCalculator {
  const AttendanceCalculator._();

  /// Calculates complete attendance statistics for a student's session records.
  static AttendanceCalculationResult calculate({
    required List<SessionRecordInput> records,
    AttendancePolicyConfig policy = const AttendancePolicyConfig(),
  }) {
    int presentCount = 0;
    int lateCount = 0;
    int excusedCount = 0;
    int absentCount = 0;
    int unmarkedCount = 0;

    double weightedAttended = 0.0;
    double weightedCounted = 0.0;

    for (final record in records) {
      final weight = record.sessionCreditWeight;
      switch (record.status) {
        case AttendanceStatus.present:
          presentCount++;
          weightedAttended += (1.0 * weight);
          weightedCounted += (1.0 * weight);
          break;
        case AttendanceStatus.late:
          lateCount++;
          weightedAttended += (policy.lateWeight * weight);
          weightedCounted += (1.0 * weight);
          break;
        case AttendanceStatus.excused:
          excusedCount++;
          if (policy.excusedCounted) {
            // If counted, it is added to denominator without adding to numerator
            weightedCounted += (1.0 * weight);
          }
          // If excusedCounted is false, it is excluded from denominator entirely
          break;
        case AttendanceStatus.absent:
          absentCount++;
          weightedCounted += (1.0 * weight);
          break;
        case AttendanceStatus.unmarked:
          unmarkedCount++;
          weightedCounted += (1.0 * weight);
          break;
      }
    }

    final double percentage = weightedCounted > 0
        ? ((weightedAttended / weightedCounted) * 100.0).clamp(0.0, 100.0)
        : 100.0; // 100% when no counted sessions yet

    final classification = AttendanceClassification.fromPercentage(
      percentage: percentage,
      minimumThreshold: policy.minimumPercentage,
      atRiskDelta: policy.atRiskDelta,
      debarThreshold: policy.debarThreshold,
    );

    // Calculate needed consecutive sessions (assuming 1 credit each) to reach minimumThreshold
    final int needed = _calculateConsecutiveNeeded(
      attended: weightedAttended,
      counted: weightedCounted,
      thresholdPct: policy.minimumPercentage,
    );

    // Calculate allowed absences (assuming 1 credit each) before falling below minimumThreshold
    final int allowed = _calculateAllowedAbsences(
      attended: weightedAttended,
      counted: weightedCounted,
      thresholdPct: policy.minimumPercentage,
    );

    return AttendanceCalculationResult(
      totalSessions: records.length,
      presentCount: presentCount,
      lateCount: lateCount,
      excusedCount: excusedCount,
      absentCount: absentCount,
      unmarkedCount: unmarkedCount,
      weightedAttended: weightedAttended,
      weightedCounted: weightedCounted,
      percentage: percentage,
      classification: classification,
      classesNeededForThreshold: needed,
      absencesAllowedBeforeThreshold: allowed,
    );
  }

  /// (A + X) / (C + X) >= T  =>  X >= (T*C - A) / (1 - T)
  static int _calculateConsecutiveNeeded({
    required double attended,
    required double counted,
    required double thresholdPct,
  }) {
    if (counted == 0) return 0;
    final double t = thresholdPct / 100.0;
    final currentPct = (attended / counted);
    if (currentPct >= t) return 0;
    if (t >= 1.0) return 999; // mathematically impossible to reach 100% if any missing

    final double numerator = (t * counted) - attended;
    final double denominator = 1.0 - t;
    if (denominator <= 0) return 0;

    return max(0, (numerator / denominator).ceil());
  }

  /// A / (C + Y) >= T  =>  Y <= (A - T*C) / T
  static int _calculateAllowedAbsences({
    required double attended,
    required double counted,
    required double thresholdPct,
  }) {
    if (counted == 0) return 0;
    final double t = thresholdPct / 100.0;
    final currentPct = (attended / counted);
    if (currentPct < t || t <= 0) return 0;

    final double numerator = attended - (t * counted);
    final double denominator = t;

    return max(0, (numerator / denominator).floor());
  }
}
