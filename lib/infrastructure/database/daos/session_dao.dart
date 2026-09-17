import 'package:sqlite3/sqlite3.dart';
import '../../../core/errors/failures.dart';
import '../../../core/result/result.dart';
import '../../../domain/entities/course_session.dart';
import '../../../domain/enums/session_type.dart';
import '../../../domain/repositories/session_repository.dart';
import '../app_database.dart';

class SessionDao implements SessionRepository {
  final AppDatabase appDb;

  SessionDao(this.appDb);

  Database get _db => appDb.rawDb;

  @override
  Future<Result<List<CourseSessionEntity>, Failure>> getSessionsForClassroom(String classroomId) async {
    try {
      final rows = _db.select(
        'SELECT * FROM course_sessions WHERE classroom_id = ? ORDER BY session_date DESC, start_time DESC;',
        [classroomId],
      );
      final list = rows.map((r) => CourseSessionEntity(
        id: r['id'] as String,
        classroomId: r['classroom_id'] as String,
        sessionDate: r['session_date'] as String,
        startTime: r['start_time'] as String?,
        endTime: r['end_time'] as String?,
        topic: r['topic'] as String?,
        sessionType: SessionType.fromString(r['session_type'] as String?),
        creditWeight: (r['credit_weight'] as num).toDouble(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      )).toList();
      return Success(list);
    } catch (e) {
      return Err(DatabaseFailure('Failed to get sessions: $e'));
    }
  }

  @override
  Future<Result<CourseSessionEntity?, Failure>> getSessionById(String sessionId) async {
    try {
      final rows = _db.select('SELECT * FROM course_sessions WHERE id = ? LIMIT 1;', [sessionId]);
      if (rows.isEmpty) return const Success(null);
      final r = rows.first;
      return Success(CourseSessionEntity(
        id: r['id'] as String,
        classroomId: r['classroom_id'] as String,
        sessionDate: r['session_date'] as String,
        startTime: r['start_time'] as String?,
        endTime: r['end_time'] as String?,
        topic: r['topic'] as String?,
        sessionType: SessionType.fromString(r['session_type'] as String?),
        creditWeight: (r['credit_weight'] as num).toDouble(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      ));
    } catch (e) {
      return Err(DatabaseFailure('Failed to get session by id: $e'));
    }
  }

  @override
  Future<Result<CourseSessionEntity, Failure>> createSession(CourseSessionEntity s) async {
    try {
      _db.execute(
        'INSERT INTO course_sessions (id, classroom_id, session_date, start_time, end_time, topic, '
        'session_type, credit_weight, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          s.id,
          s.classroomId,
          s.sessionDate,
          s.startTime,
          s.endTime,
          s.topic,
          s.sessionType.value,
          s.creditWeight,
          s.createdAt.millisecondsSinceEpoch,
          s.updatedAt.millisecondsSinceEpoch,
        ],
      );
      return Success(s);
    } catch (e) {
      return Err(DatabaseFailure('Failed to create session: $e'));
    }
  }

  @override
  Future<Result<void, Failure>> updateSession(CourseSessionEntity s) async {
    try {
      _db.execute(
        'UPDATE course_sessions SET session_date = ?, start_time = ?, end_time = ?, topic = ?, '
        'session_type = ?, credit_weight = ?, updated_at = ? WHERE id = ?;',
        [
          s.sessionDate,
          s.startTime,
          s.endTime,
          s.topic,
          s.sessionType.value,
          s.creditWeight,
          DateTime.now().millisecondsSinceEpoch,
          s.id,
        ],
      );
      return const Success(null);
    } catch (e) {
      return Err(DatabaseFailure('Failed to update session: $e'));
    }
  }

  @override
  Future<Result<void, Failure>> deleteSession(String sessionId) async {
    try {
      _db.execute('DELETE FROM course_sessions WHERE id = ?;', [sessionId]);
      return const Success(null);
    } catch (e) {
      return Err(DatabaseFailure('Failed to delete session: $e'));
    }
  }
}
