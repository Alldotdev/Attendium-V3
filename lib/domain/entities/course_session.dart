import '../enums/session_type.dart';

/// Classroom session / lecture entity.
class CourseSessionEntity {
  final String id;
  final String classroomId;
  final String sessionDate; // 'YYYY-MM-DD'
  final String? startTime;  // 'HH:MM'
  final String? endTime;    // 'HH:MM'
  final String? topic;
  final SessionType sessionType;
  final double creditWeight;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CourseSessionEntity({
    required this.id,
    required this.classroomId,
    required this.sessionDate,
    this.startTime,
    this.endTime,
    this.topic,
    this.sessionType = SessionType.lecture,
    this.creditWeight = 1.0,
    required this.createdAt,
    required this.updatedAt,
  });

  CourseSessionEntity copyWith({
    String? id,
    String? classroomId,
    String? sessionDate,
    String? startTime,
    String? endTime,
    String? topic,
    SessionType? sessionType,
    double? creditWeight,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CourseSessionEntity(
      id: id ?? this.id,
      classroomId: classroomId ?? this.classroomId,
      sessionDate: sessionDate ?? this.sessionDate,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      topic: topic ?? this.topic,
      sessionType: sessionType ?? this.sessionType,
      creditWeight: creditWeight ?? this.creditWeight,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
