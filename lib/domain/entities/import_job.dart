import '../enums/import_status.dart';

/// Multimodal document import job.
class ImportJobEntity {
  final String id;
  final String classroomId;
  final String filename;
  final String mimeType;
  final String fileHash; // SHA-256 for duplicate detection (Section 46)
  final String sourceType; // 'pdf', 'image', 'csv', 'xlsx', 'txt'
  final ImportJobStatus processingStatus;
  final String? rawExtractionJson;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ImportJobEntity({
    required this.id,
    required this.classroomId,
    required this.filename,
    required this.mimeType,
    required this.fileHash,
    required this.sourceType,
    this.processingStatus = ImportJobStatus.pending,
    this.rawExtractionJson,
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  ImportJobEntity copyWith({
    String? id,
    String? classroomId,
    String? filename,
    String? mimeType,
    String? fileHash,
    String? sourceType,
    ImportJobStatus? processingStatus,
    String? rawExtractionJson,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ImportJobEntity(
      id: id ?? this.id,
      classroomId: classroomId ?? this.classroomId,
      filename: filename ?? this.filename,
      mimeType: mimeType ?? this.mimeType,
      fileHash: fileHash ?? this.fileHash,
      sourceType: sourceType ?? this.sourceType,
      processingStatus: processingStatus ?? this.processingStatus,
      rawExtractionJson: rawExtractionJson ?? this.rawExtractionJson,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
