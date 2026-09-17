import '../enums/audit_action.dart';

/// Immutable audit log entry mandated by Section 42 of directive.
class AuditLogEntity {
  final String id;
  final String? userId;
  final String entityType; // 'attendance_record', 'student', 'session', etc.
  final String entityId;
  final AuditAction action;
  final String? beforeJson;
  final String? afterJson;
  final String reason;
  final String source;
  final DateTime createdAt;

  const AuditLogEntity({
    required this.id,
    this.userId,
    required this.entityType,
    required this.entityId,
    required this.action,
    this.beforeJson,
    this.afterJson,
    required this.reason,
    required this.source,
    required this.createdAt,
  });
}
