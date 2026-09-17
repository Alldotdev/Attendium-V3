/// Explicit junction enrollment entity linking students to classrooms.
class EnrollmentEntity {
  final String id;
  final String studentId;
  final String classroomId;
  final String rollNumber;
  final DateTime enrolledAt;
  final DateTime? withdrawnAt;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EnrollmentEntity({
    required this.id,
    required this.studentId,
    required this.classroomId,
    required this.rollNumber,
    required this.enrolledAt,
    this.withdrawnAt,
    this.status = 'active',
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isActive => status == 'active';
}
