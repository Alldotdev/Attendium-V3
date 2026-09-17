import 'package:sqlite3/sqlite3.dart';
import '../../../core/errors/failures.dart';
import '../../../core/result/result.dart';
import '../../../domain/entities/extraction_row.dart';
import '../../../domain/entities/import_job.dart';
import '../../../domain/enums/import_status.dart';
import '../../../domain/repositories/import_repository.dart';
import '../app_database.dart';

class ImportDao implements ImportRepository {
  final AppDatabase appDb;

  ImportDao(this.appDb);

  Database get _db => appDb.rawDb;

  @override
  Future<Result<ImportJobEntity, Failure>> createImportJob(ImportJobEntity job) async {
    try {
      _db.execute(
        'INSERT INTO import_jobs (id, classroom_id, filename, mime_type, file_hash, source_type, '
        'processing_status, raw_extraction_json, error_message, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          job.id,
          job.classroomId,
          job.filename,
          job.mimeType,
          job.fileHash,
          job.sourceType,
          job.processingStatus.value,
          job.rawExtractionJson,
          job.errorMessage,
          job.createdAt.millisecondsSinceEpoch,
          job.updatedAt.millisecondsSinceEpoch,
        ],
      );
      return Success(job);
    } catch (e) {
      return Err(DatabaseFailure('Failed to create import job: $e'));
    }
  }

  @override
  Future<Result<ImportJobEntity?, Failure>> getImportJobByHash(String fileHash) async {
    try {
      final rows = _db.select('SELECT * FROM import_jobs WHERE file_hash = ? LIMIT 1;', [fileHash]);
      if (rows.isEmpty) return const Success(null);
      return Success(_mapJob(rows.first));
    } catch (e) {
      return Err(DatabaseFailure('Failed to get import job by hash: $e'));
    }
  }

  @override
  Future<Result<ImportJobEntity?, Failure>> getImportJobById(String jobId) async {
    try {
      final rows = _db.select('SELECT * FROM import_jobs WHERE id = ? LIMIT 1;', [jobId]);
      if (rows.isEmpty) return const Success(null);
      return Success(_mapJob(rows.first));
    } catch (e) {
      return Err(DatabaseFailure('Failed to get import job by id: $e'));
    }
  }

  @override
  Future<Result<void, Failure>> updateImportJob(ImportJobEntity job) async {
    try {
      _db.execute(
        'UPDATE import_jobs SET processing_status = ?, raw_extraction_json = ?, error_message = ?, updated_at = ? '
        'WHERE id = ?;',
        [
          job.processingStatus.value,
          job.rawExtractionJson,
          job.errorMessage,
          DateTime.now().millisecondsSinceEpoch,
          job.id,
        ],
      );
      return const Success(null);
    } catch (e) {
      return Err(DatabaseFailure('Failed to update import job: $e'));
    }
  }

  @override
  Future<Result<List<ExtractionRowEntity>, Failure>> getExtractionRows(String importJobId) async {
    try {
      final rows = _db.select(
        'SELECT * FROM extraction_rows WHERE import_job_id = ? ORDER BY row_index ASC;',
        [importJobId],
      );
      final list = rows.map((r) => _mapRow(r)).toList();
      return Success(list);
    } catch (e) {
      return Err(DatabaseFailure('Failed to get extraction rows: $e'));
    }
  }

  @override
  Future<Result<void, Failure>> saveExtractionRows(List<ExtractionRowEntity> rows) async {
    try {
      appDb.transaction(() {
        for (final r in rows) {
          _db.execute('''
            INSERT INTO extraction_rows (id, import_job_id, row_index, raw_roll, raw_name, raw_attendance,
              normalized_roll, normalized_name, matched_student_id, match_score, ai_confidence,
              review_state, evidence_json, source_region, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              matched_student_id = excluded.matched_student_id,
              match_score = excluded.match_score,
              review_state = excluded.review_state,
              updated_at = excluded.updated_at;
          ''', [
            r.id,
            r.importJobId,
            r.rowIndex,
            r.rawRoll,
            r.rawName,
            r.rawAttendance,
            r.normalizedRoll,
            r.normalizedName,
            r.matchedStudentId,
            r.matchScore,
            r.aiConfidence,
            r.reviewState.code,
            r.evidenceJson,
            r.sourceRegion,
            r.createdAt.millisecondsSinceEpoch,
            DateTime.now().millisecondsSinceEpoch,
          ]);
        }
      });
      return const Success(null);
    } catch (e) {
      return Err(DatabaseFailure('Failed to save extraction rows: $e'));
    }
  }

  @override
  Future<Result<void, Failure>> updateExtractionRow(ExtractionRowEntity r) async {
    try {
      _db.execute('''
        UPDATE extraction_rows SET
          raw_roll = ?,
          raw_name = ?,
          raw_attendance = ?,
          matched_student_id = ?,
          match_score = ?,
          review_state = ?,
          updated_at = ?
        WHERE id = ?;
      ''', [
        r.rawRoll,
        r.rawName,
        r.rawAttendance,
        r.matchedStudentId,
        r.matchScore,
        r.reviewState.code,
        DateTime.now().millisecondsSinceEpoch,
        r.id,
      ]);
      return const Success(null);
    } catch (e) {
      return Err(DatabaseFailure('Failed to update extraction row: $e'));
    }
  }

  ImportJobEntity _mapJob(Row r) {
    return ImportJobEntity(
      id: r['id'] as String,
      classroomId: r['classroom_id'] as String,
      filename: r['filename'] as String,
      mimeType: r['mime_type'] as String,
      fileHash: r['file_hash'] as String,
      sourceType: r['source_type'] as String,
      processingStatus: ImportJobStatus.fromString(r['processing_status'] as String?),
      rawExtractionJson: r['raw_extraction_json'] as String?,
      errorMessage: r['error_message'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
    );
  }

  ExtractionRowEntity _mapRow(Row r) {
    return ExtractionRowEntity(
      id: r['id'] as String,
      importJobId: r['import_job_id'] as String,
      rowIndex: r['row_index'] as int,
      rawRoll: r['raw_roll'] as String?,
      rawName: r['raw_name'] as String?,
      rawAttendance: r['raw_attendance'] as String?,
      normalizedRoll: r['normalized_roll'] as String?,
      normalizedName: r['normalized_name'] as String?,
      matchedStudentId: r['matched_student_id'] as String?,
      matchScore: (r['match_score'] as num).toDouble(),
      aiConfidence: (r['ai_confidence'] as num).toDouble(),
      reviewState: RowReviewState.fromString(r['review_state'] as String?),
      evidenceJson: r['evidence_json'] as String?,
      sourceRegion: r['source_region'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
    );
  }
}
