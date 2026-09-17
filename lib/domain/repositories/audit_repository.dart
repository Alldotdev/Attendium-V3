import '../../core/result/result.dart';
import '../../core/errors/failures.dart';
import '../entities/audit_log.dart';

/// Contract for immutable audit logging.
abstract class AuditRepository {
  Future<Result<void, Failure>> logAction(AuditLogEntity log);
  Future<Result<List<AuditLogEntity>, Failure>> getLogsForEntity(String entityType, String entityId);
  Future<Result<List<AuditLogEntity>, Failure>> getRecentLogs({int limit = 100, int offset = 0});
}
