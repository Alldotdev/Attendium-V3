import '../enums/import_status.dart';

/// Single extracted row from an ingested document during human-in-the-loop review.
class ExtractionRowEntity {
  final String id;
  final String importJobId;
  final int rowIndex;
  final String? rawRoll;
  final String? rawName;
  final String? rawAttendance;
  final String? normalizedRoll;
  final String? normalizedName;
  final String? matchedStudentId;
  final double matchScore;
  final double aiConfidence;
  final RowReviewState reviewState;
  final String? evidenceJson;
  final String? sourceRegion;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ExtractionRowEntity({
    required this.id,
    required this.importJobId,
    required this.rowIndex,
    this.rawRoll,
    this.rawName,
    this.rawAttendance,
    this.normalizedRoll,
    this.normalizedName,
    this.matchedStudentId,
    this.matchScore = 0.0,
    this.aiConfidence = 0.0,
    this.reviewState = RowReviewState.reviewRequired,
    this.evidenceJson,
    this.sourceRegion,
    required this.createdAt,
    required this.updatedAt,
  });

  ExtractionRowEntity copyWith({
    String? id,
    String? importJobId,
    int? rowIndex,
    String? rawRoll,
    String? rawName,
    String? rawAttendance,
    String? normalizedRoll,
    String? normalizedName,
    String? matchedStudentId,
    double? matchScore,
    double? aiConfidence,
    RowReviewState? reviewState,
    String? evidenceJson,
    String? sourceRegion,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExtractionRowEntity(
      id: id ?? this.id,
      importJobId: importJobId ?? this.importJobId,
      rowIndex: rowIndex ?? this.rowIndex,
      rawRoll: rawRoll ?? this.rawRoll,
      rawName: rawName ?? this.rawName,
      rawAttendance: rawAttendance ?? this.rawAttendance,
      normalizedRoll: normalizedRoll ?? this.normalizedRoll,
      normalizedName: normalizedName ?? this.normalizedName,
      matchedStudentId: matchedStudentId ?? this.matchedStudentId,
      matchScore: matchScore ?? this.matchScore,
      aiConfidence: aiConfidence ?? this.aiConfidence,
      reviewState: reviewState ?? this.reviewState,
      evidenceJson: evidenceJson ?? this.evidenceJson,
      sourceRegion: sourceRegion ?? this.sourceRegion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
