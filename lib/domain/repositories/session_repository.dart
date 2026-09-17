import '../../core/result/result.dart';
import '../../core/errors/failures.dart';
import '../entities/course_session.dart';

/// Contract for course session management.
abstract class SessionRepository {
  Future<Result<List<CourseSessionEntity>, Failure>> getSessionsForClassroom(String classroomId);
  Future<Result<CourseSessionEntity?, Failure>> getSessionById(String sessionId);
  Future<Result<CourseSessionEntity, Failure>> createSession(CourseSessionEntity session);
  Future<Result<void, Failure>> updateSession(CourseSessionEntity session);
  Future<Result<void, Failure>> deleteSession(String sessionId);
}
