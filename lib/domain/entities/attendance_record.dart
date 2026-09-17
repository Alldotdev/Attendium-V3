import '../enums/attendance_status.dart';

/// Single student attendance record in a session.
class AttendanceRecordEntity {
  final String id;
  final String sessionId;
  final String studentId;
  final AttendanceStatus status;
  final double creditWeight;
  final String source; // 'manual_grid', 'ai_import', 'csv_import', 'manual_edit'
  final double? confidenceScore;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AttendanceRecordEntity({
    required this.id,
    required this.sessionId,
    required this.studentId,
    required this.status,
    this.creditWeight = 1.0,
    this.source = 'manual_grid',
    this.confidenceScore,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  AttendanceRecordEntity copyWith({
    String? id,
    String? sessionId,
    String? studentId,
    AttendanceStatus? status,
    double? creditWeight,
    String? source,
    double? confidenceScore,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AttendanceRecordEntity(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      studentId: studentId ?? this.studentId,
      status: status ?? this.status,
      creditWeight: creditWeight ?? this.creditWeight,
      source: source ?? this.source,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
