/// Attendance shortage alert notification.
class AttendanceAlertEntity {
  final String id;
  final String studentId;
  final String classroomId;
  final String alertType; // 'at_risk', 'short_attendance', 'debarred'
  final double percentage;
  final double threshold;
  final bool acknowledged;
  final DateTime createdAt;

  const AttendanceAlertEntity({
    required this.id,
    required this.studentId,
    required this.classroomId,
    required this.alertType,
    required this.percentage,
    required this.threshold,
    this.acknowledged = false,
    required this.createdAt,
  });
}
