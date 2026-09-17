import 'package:sqlite3/sqlite3.dart';
import '../../../core/errors/failures.dart';
import '../../../core/result/result.dart';
import '../../../domain/entities/audit_log.dart';
import '../../../domain/enums/audit_action.dart';
import '../../../domain/repositories/audit_repository.dart';
import '../app_database.dart';

class AuditDao implements AuditRepository {
  final AppDatabase appDb;

  AuditDao(this.appDb);

  Database get _db => appDb.rawDb;

  void logActionSync(AuditLogEntity log) {
    _db.execute(
      'INSERT INTO audit_logs (id, user_id, entity_type, entity_id, action, before_json, after_json, reason, source, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        log.id,
        log.userId,
        log.entityType,
        log.entityId,
        log.action.value,
        log.beforeJson,
        log.afterJson,
        log.reason,
        log.source,
        log.createdAt.millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<Result<void, Failure>> logAction(AuditLogEntity log) async {
    try {
      logActionSync(log);
      return const Success(null);
    } catch (e) {
      return Err(DatabaseFailure('Failed to write audit log: $e'));
    }
  }

  @override
  Future<Result<List<AuditLogEntity>, Failure>> getLogsForEntity(String entityType, String entityId) async {
    try {
      final rows = _db.select(
        'SELECT * FROM audit_logs WHERE entity_type = ? AND entity_id = ? ORDER BY created_at DESC;',
        [entityType, entityId],
      );
      final list = rows.map((r) => _mapAudit(r)).toList();
      return Success(list);
    } catch (e) {
      return Err(DatabaseFailure('Failed to get audit logs for entity: $e'));
    }
  }

  @override
  Future<Result<List<AuditLogEntity>, Failure>> getRecentLogs({int limit = 100, int offset = 0}) async {
    try {
      final rows = _db.select(
        'SELECT * FROM audit_logs ORDER BY created_at DESC LIMIT ? OFFSET ?;',
        [limit, offset],
      );
      final list = rows.map((r) => _mapAudit(r)).toList();
      return Success(list);
    } catch (e) {
      return Err(DatabaseFailure('Failed to get recent audit logs: $e'));
    }
  }

  AuditLogEntity _mapAudit(Row r) {
    return AuditLogEntity(
      id: r['id'] as String,
      userId: r['user_id'] as String?,
      entityType: r['entity_type'] as String,
      entityId: r['entity_id'] as String,
      action: AuditAction.fromString(r['action'] as String?),
      beforeJson: r['before_json'] as String?,
      afterJson: r['after_json'] as String?,
      reason: r['reason'] as String,
      source: r['source'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
    );
  }
}
