/// Canonical Data Transfer Objects for AI extraction responses.
/// Strictly conforms to Section 14 and Section 41 of the directive.
library;

class AiCourseInfo {
  final String? courseCode;
  final String? courseName;
  final String? date;
  final String? instructor;

  const AiCourseInfo({
    this.courseCode,
    this.courseName,
    this.date,
    this.instructor,
  });

  factory AiCourseInfo.fromJson(Map<String, dynamic> json) {
    return AiCourseInfo(
      courseCode: json['course_code'] as String?,
      courseName: json['course_name'] as String?,
      date: json['date'] as String?,
      instructor: json['instructor'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'course_code': courseCode,
    'course_name': courseName,
    'date': date,
    'instructor': instructor,
  };
}

class AiExtractedRow {
  final int rowIndex;
  final String? rawRoll;
  final String? rawName;
  final String? rawAttendance; // e.g. "P", "A", "Late", "Present"
  final double visualConfidence; // 0.0 to 1.0
  final String? evidence;
  final String? sourceRegion;

  const AiExtractedRow({
    required this.rowIndex,
    this.rawRoll,
    this.rawName,
    this.rawAttendance,
    required this.visualConfidence,
    this.evidence,
    this.sourceRegion,
  });

  factory AiExtractedRow.fromJson(Map<String, dynamic> json) {
    return AiExtractedRow(
      rowIndex: json['row_index'] as int? ?? 0,
      rawRoll: json['raw_roll'] as String?,
      rawName: json['raw_name'] as String?,
      rawAttendance: json['raw_attendance'] as String?,
      visualConfidence: (json['visual_confidence'] as num?)?.toDouble() ?? 0.0,
      evidence: json['evidence'] as String?,
      sourceRegion: json['source_region'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'row_index': rowIndex,
    'raw_roll': rawRoll,
    'raw_name': rawName,
    'raw_attendance': rawAttendance,
    'visual_confidence': visualConfidence,
    'evidence': evidence,
    'source_region': sourceRegion,
  };
}

class AiExtractionPayload {
  final AiCourseInfo? courseInfo;
  final List<AiExtractedRow> rows;
  final String rawResponseJson;

  const AiExtractionPayload({
    this.courseInfo,
    required this.rows,
    required this.rawResponseJson,
  });
}
