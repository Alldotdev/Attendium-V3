import 'package:sqlite3/sqlite3.dart';
import '../../../core/errors/failures.dart';
import '../../../core/result/result.dart';
import '../../../domain/entities/backup_job.dart';
import '../../../domain/repositories/backup_repository.dart';
import '../app_database.dart';

class BackupDao implements BackupRepository {
  final AppDatabase appDb;

  BackupDao(this.appDb);

  Database get _db => appDb.rawDb;

  @override
  Future<Result<BackupJobEntity, Failure>> createBackupJob(BackupJobEntity job) async {
    try {
      _db.execute(
        'INSERT INTO backup_jobs (id, snapshot_hash, encrypted_size, drive_file_id, status, error_message, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
        [
          job.id,
          job.snapshotHash,
          job.encryptedSize,
          job.driveFileId,
          job.status,
          job.errorMessage,
          job.createdAt.millisecondsSinceEpoch,
          job.updatedAt.millisecondsSinceEpoch,
        ],
      );
      return Success(job);
    } catch (e) {
      return Err(DatabaseFailure('Failed to create backup job: $e'));
    }
  }

  @override
  Future<Result<List<BackupJobEntity>, Failure>> getBackupHistory() async {
    try {
      final rows = _db.select('SELECT * FROM backup_jobs ORDER BY created_at DESC;');
      final list = rows.map((r) => BackupJobEntity(
        id: r['id'] as String,
        snapshotHash: r['snapshot_hash'] as String,
        encryptedSize: r['encrypted_size'] as int,
        driveFileId: r['drive_file_id'] as String?,
        status: r['status'] as String,
        errorMessage: r['error_message'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      )).toList();
      return Success(list);
    } catch (e) {
      return Err(DatabaseFailure('Failed to get backup history: $e'));
    }
  }

  @override
  Future<Result<void, Failure>> updateBackupJob(BackupJobEntity job) async {
    try {
      _db.execute(
        'UPDATE backup_jobs SET status = ?, drive_file_id = ?, error_message = ?, updated_at = ? WHERE id = ?;',
        [
          job.status,
          job.driveFileId,
          job.errorMessage,
          DateTime.now().millisecondsSinceEpoch,
          job.id,
        ],
      );
      return const Success(null);
    } catch (e) {
      return Err(DatabaseFailure('Failed to update backup job: $e'));
    }
  }
}
