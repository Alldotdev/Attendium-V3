import '../../core/result/result.dart';
import '../../core/errors/failures.dart';
import '../entities/backup_job.dart';

/// Contract for zero-knowledge encrypted database snapshots and restore.
abstract class BackupRepository {
  Future<Result<BackupJobEntity, Failure>> createBackupJob(BackupJobEntity job);
  Future<Result<List<BackupJobEntity>, Failure>> getBackupHistory();
  Future<Result<void, Failure>> updateBackupJob(BackupJobEntity job);
}
