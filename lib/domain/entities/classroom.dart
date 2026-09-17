import '../../core/constants/app_constants.dart';

/// Classroom / course section entity.
class ClassroomEntity {
  final String id;
  final String userId;
  final String academicTermId;
  final String courseCode;
  final String courseName;
  final String section;
  final String instructorName;
  final double defaultCreditHours;
  final double attendanceThreshold;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ClassroomEntity({
    required this.id,
    required this.userId,
    required this.academicTermId,
    required this.courseCode,
    required this.courseName,
    required this.section,
    required this.instructorName,
    this.defaultCreditHours = 3.0,
    this.attendanceThreshold = AppConstants.defaultAttendanceThreshold,
    this.status = 'active',
    required this.createdAt,
    required this.updatedAt,
  });

  String get displayName => '$courseCode ($section) — $courseName';

  ClassroomEntity copyWith({
    String? id,
    String? userId,
    String? academicTermId,
    String? courseCode,
    String? courseName,
    String? section,
    String? instructorName,
    double? defaultCreditHours,
    double? attendanceThreshold,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ClassroomEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      academicTermId: academicTermId ?? this.academicTermId,
      courseCode: courseCode ?? this.courseCode,
      courseName: courseName ?? this.courseName,
      section: section ?? this.section,
      instructorName: instructorName ?? this.instructorName,
      defaultCreditHours: defaultCreditHours ?? this.defaultCreditHours,
      attendanceThreshold: attendanceThreshold ?? this.attendanceThreshold,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
