import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import '../../../core/errors/failures.dart';
import '../../../core/result/result.dart';
import '../../../domain/entities/attendance_policy.dart';
import '../../../domain/entities/attendance_record.dart';
import '../../../domain/entities/audit_log.dart';
import '../../../domain/enums/attendance_status.dart';
import '../../../domain/enums/audit_action.dart';
import '../../../domain/repositories/attendance_repository.dart';
import '../app_database.dart';
import 'audit_dao.dart';

class AttendanceDao implements AttendanceRepository {
  final AppDatabase appDb;
  final AuditDao auditDao;

  AttendanceDao(this.appDb, this.auditDao);

  Database get _db => appDb.rawDb;

  @override
  Future<Result<List<AttendanceRecordEntity>, Failure>> getRecordsForSession(String sessionId) async {
    try {
      final rows = _db.select(
        'SELECT * FROM attendance_records WHERE session_id = ?;',
        [sessionId],
      );
      final list = rows.map((r) => _mapRecord(r)).toList();
      return Success(list);
    } catch (e) {
      return Err(DatabaseFailure('Failed to get attendance records for session: $e'));
    }
  }

  @override
  Future<Result<List<AttendanceRecordEntity>, Failure>> getRecordsForStudent(String studentId, String classroomId) async {
    try {
      final rows = _db.select('''
        SELECT ar.*
        FROM attendance_records ar
        INNER JOIN course_sessions cs ON ar.session_id = cs.id
        WHERE ar.student_id = ? AND cs.classroom_id = ?
        ORDER BY cs.session_date ASC;
      ''', [studentId, classroomId]);
      final list = rows.map((r) => _mapRecord(r)).toList();
      return Success(list);
    } catch (e) {
      return Err(DatabaseFailure('Failed to get student attendance records: $e'));
    }
  }

  @override
  Future<Result<List<AttendanceRecordEntity>, Failure>> getAllRecordsForClassroom(String classroomId) async {
    try {
      final rows = _db.select('''
        SELECT ar.*
        FROM attendance_records ar
        INNER JOIN course_sessions cs ON ar.session_id = cs.id
        WHERE cs.classroom_id = ?
        ORDER BY cs.session_date ASC;
      ''', [classroomId]);
      final list = rows.map((r) => _mapRecord(r)).toList();
      return Success(list);
    } catch (e) {
      return Err(DatabaseFailure('Failed to get all records for classroom: $e'));
    }
  }

  @override
  Future<Result<void, Failure>> recordBatchAttendance({
    required String sessionId,
    required List<AttendanceRecordEntity> records,
    required String source,
  }) async {
    try {
      appDb.transaction(() {
        for (final r in records) {
          _db.execute('''
            INSERT INTO attendance_records (id, session_id, student_id, status, credit_weight, source, confidence_score, notes, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(session_id, student_id) DO UPDATE SET
              status = excluded.status,
              credit_weight = excluded.credit_weight,
              source = excluded.source,
              confidence_score = excluded.confidence_score,
              notes = excluded.notes,
              updated_at = excluded.updated_at;
          ''', [
            r.id,
            sessionId,
            r.studentId,
            r.status.value,
            r.creditWeight,
            source,
            r.confidenceScore,
            r.notes,
            r.createdAt.millisecondsSinceEpoch,
            DateTime.now().millisecondsSinceEpoch,
          ]);
        }

        // Record batch audit trail entry
        auditDao.logActionSync(AuditLogEntity(
          id: 'aud_batch_${sessionId}_${DateTime.now().millisecondsSinceEpoch}',
          userId: 'usr_system',
          entityType: 'attendance_record',
          entityId: sessionId,
          action: AuditAction.bulkUpdate,
          beforeJson: null,
          afterJson: jsonEncode({'session_id': sessionId, 'record_count': records.length}),
          reason: 'Batch attendance committed via $source',
          source: source,
          createdAt: DateTime.now(),
        ));
      });
      return const Success(null);
    } catch (e) {
      return Err(DatabaseFailure('Failed to commit batch attendance: $e'));
    }
  }

  @override
  Future<Result<void, Failure>> updateSingleAttendanceRecord({
    required AttendanceRecordEntity updatedRecord,
    required String reason,
    required String userId,
  }) async {
    try {
      return await appDb.transaction(() {
        // Fetch before state for audit log
        final beforeRows = _db.select(
          'SELECT * FROM attendance_records WHERE session_id = ? AND student_id = ? LIMIT 1;',
          [updatedRecord.sessionId, updatedRecord.studentId],
        );

        String? beforeJson;
        if (beforeRows.isNotEmpty) {
          final b = beforeRows.first;
          beforeJson = jsonEncode({
            'id': b['id'],
            'status': b['status'],
            'notes': b['notes'],
            'source': b['source'],
          });
        }

        final now = DateTime.now();
        // Upsert record
        _db.execute('''
          INSERT INTO attendance_records (id, session_id, student_id, status, credit_weight, source, confidence_score, notes, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, 'manual_edit', ?, ?, ?, ?)
          ON CONFLICT(session_id, student_id) DO UPDATE SET
            status = excluded.status,
            notes = excluded.notes,
            source = 'manual_edit',
            updated_at = excluded.updated_at;
        ''', [
          updatedRecord.id,
          updatedRecord.sessionId,
          updatedRecord.studentId,
          updatedRecord.status.value,
          updatedRecord.creditWeight,
          updatedRecord.confidenceScore,
          updatedRecord.notes,
          updatedRecord.createdAt.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch,
        ]);

        final afterJson = jsonEncode({
          'id': updatedRecord.id,
          'status': updatedRecord.status.value,
          'notes': updatedRecord.notes,
          'source': 'manual_edit',
        });

        // Insert immutable audit log entry
        auditDao.logActionSync(AuditLogEntity(
          id: '${updatedRecord.id}_${now.millisecondsSinceEpoch}',
          userId: userId,
          entityType: 'attendance_record',
          entityId: updatedRecord.id,
          action: AuditAction.statusChange,
          beforeJson: beforeJson,
          afterJson: afterJson,
          reason: reason,
          source: 'manual_edit',
          createdAt: now,
        ));

        return const Success(null);
      });
    } catch (e) {
      return Err(DatabaseFailure('Failed to update attendance record with audit: $e'));
    }
  }

  @override
  Future<Result<AttendancePolicyEntity, Failure>> getPolicyForClassroom(String classroomId) async {
    try {
      final rows = _db.select(
        'SELECT * FROM attendance_policies WHERE classroom_id = ? LIMIT 1;',
        [classroomId],
      );
      if (rows.isEmpty) {
        // Return default policy
        return Success(AttendancePolicyEntity(
          id: 'default_$classroomId',
          classroomId: classroomId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      }
      final r = rows.first;
      return Success(AttendancePolicyEntity(
        id: r['id'] as String,
        classroomId: r['classroom_id'] as String,
        minimumPercentage: (r['minimum_percentage'] as num).toDouble(),
        lateWeight: (r['late_weight'] as num).toDouble(),
        excusedCounted: (r['excused_counted'] as int) == 1,
        shortThreshold: (r['short_threshold'] as num).toDouble(),
        debarThreshold: (r['debar_threshold'] as num).toDouble(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      ));
    } catch (e) {
      return Err(DatabaseFailure('Failed to get attendance policy: $e'));
    }
  }

  @override
  Future<Result<void, Failure>> savePolicy(AttendancePolicyEntity p) async {
    try {
      _db.execute('''
        INSERT INTO attendance_policies (id, classroom_id, minimum_percentage, late_weight, excused_counted, short_threshold, debar_threshold, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          minimum_percentage = excluded.minimum_percentage,
          late_weight = excluded.late_weight,
          excused_counted = excluded.excused_counted,
          short_threshold = excluded.short_threshold,
          debar_threshold = excluded.debar_threshold,
          updated_at = excluded.updated_at;
      ''', [
        p.id,
        p.classroomId,
        p.minimumPercentage,
        p.lateWeight,
        p.excusedCounted ? 1 : 0,
        p.shortThreshold,
        p.debarThreshold,
        p.createdAt.millisecondsSinceEpoch,
        DateTime.now().millisecondsSinceEpoch,
      ]);
      return const Success(null);
    } catch (e) {
      return Err(DatabaseFailure('Failed to save attendance policy: $e'));
    }
  }

  AttendanceRecordEntity _mapRecord(Row r) {
    return AttendanceRecordEntity(
      id: r['id'] as String,
      sessionId: r['session_id'] as String,
      studentId: r['student_id'] as String,
      status: AttendanceStatus.fromString(r['status'] as String?),
      creditWeight: (r['credit_weight'] as num).toDouble(),
      source: r['source'] as String,
      confidenceScore: r['confidence_score'] != null ? (r['confidence_score'] as num).toDouble() : null,
      notes: r['notes'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
    );
  }
}
