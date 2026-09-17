import '../../core/constants/app_constants.dart';

/// Classroom-specific attendance policy entity.
class AttendancePolicyEntity {
  final String id;
  final String classroomId;
  final double minimumPercentage;
  final double lateWeight;
  final bool excusedCounted;
  final double shortThreshold;
  final double debarThreshold;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AttendancePolicyEntity({
    required this.id,
    required this.classroomId,
    this.minimumPercentage = AppConstants.defaultAttendanceThreshold,
    this.lateWeight = AppConstants.defaultLateWeight,
    this.excusedCounted = AppConstants.defaultExcusedCounted,
    this.shortThreshold = 65.0,
    this.debarThreshold = AppConstants.defaultDebarThreshold,
    required this.createdAt,
    required this.updatedAt,
  });
}
