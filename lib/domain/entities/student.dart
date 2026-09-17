/// Master student identity entity.
class StudentEntity {
  final String id;
  final String? classroomId;
  final String rollNumber;
  final String fullName;
  final String normalizedName;
  final String? email;
  final String status;
  final DateTime enrolledAt;
  final DateTime? withdrawnAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const StudentEntity({
    required this.id,
    this.classroomId,
    required this.rollNumber,
    required this.fullName,
    required this.normalizedName,
    this.email,
    this.status = 'enrolled',
    required this.enrolledAt,
    this.withdrawnAt,
    required this.createdAt,
    required this.updatedAt,
  });

  StudentEntity copyWith({
    String? id,
    String? classroomId,
    String? rollNumber,
    String? fullName,
    String? normalizedName,
    String? email,
    String? status,
    DateTime? enrolledAt,
    DateTime? withdrawnAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StudentEntity(
      id: id ?? this.id,
      classroomId: classroomId ?? this.classroomId,
      rollNumber: rollNumber ?? this.rollNumber,
      fullName: fullName ?? this.fullName,
      normalizedName: normalizedName ?? this.normalizedName,
      email: email ?? this.email,
      status: status ?? this.status,
      enrolledAt: enrolledAt ?? this.enrolledAt,
      withdrawnAt: withdrawnAt ?? this.withdrawnAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
