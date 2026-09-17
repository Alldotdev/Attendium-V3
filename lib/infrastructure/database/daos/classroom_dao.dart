import 'package:sqlite3/sqlite3.dart';
import '../../../core/errors/failures.dart';
import '../../../core/result/result.dart';
import '../../../domain/entities/academic_term.dart';
import '../../../domain/entities/classroom.dart';
import '../../../domain/enums/term_status.dart';
import '../../../domain/repositories/classroom_repository.dart';
import '../app_database.dart';

class ClassroomDao implements ClassroomRepository {
  final AppDatabase appDb;

  ClassroomDao(this.appDb);

  Database get _db => appDb.rawDb;

  @override
  Future<Result<List<AcademicTermEntity>, Failure>> getTerms(String userId) async {
    try {
      final rows = _db.select(
        'SELECT * FROM academic_terms WHERE user_id = ? ORDER BY start_date DESC;',
        [userId],
      );
      final list = rows.map((r) => AcademicTermEntity(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        name: r['name'] as String,
        startDate: DateTime.fromMillisecondsSinceEpoch(r['start_date'] as int),
        endDate: DateTime.fromMillisecondsSinceEpoch(r['end_date'] as int),
        status: TermStatus.fromString(r['status'] as String?),
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      )).toList();
      return Success(list);
    } catch (e) {
      return Err(DatabaseFailure('Failed to get academic terms: $e'));
    }
  }

  @override
  Future<Result<AcademicTermEntity, Failure>> createTerm(AcademicTermEntity term) async {
    try {
      _db.execute(
        'INSERT INTO academic_terms (id, user_id, name, start_date, end_date, status, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
        [
          term.id,
          term.userId,
          term.name,
          term.startDate.millisecondsSinceEpoch,
          term.endDate.millisecondsSinceEpoch,
          term.status.value,
          term.createdAt.millisecondsSinceEpoch,
          term.updatedAt.millisecondsSinceEpoch,
        ],
      );
      return Success(term);
    } catch (e) {
      return Err(DatabaseFailure('Failed to create academic term: $e'));
    }
  }

  @override
  Future<Result<void, Failure>> updateTerm(AcademicTermEntity term) async {
    try {
      _db.execute(
        'UPDATE academic_terms SET name = ?, start_date = ?, end_date = ?, status = ?, updated_at = ? '
        'WHERE id = ?;',
        [
          term.name,
          term.startDate.millisecondsSinceEpoch,
          term.endDate.millisecondsSinceEpoch,
          term.status.value,
          DateTime.now().millisecondsSinceEpoch,
          term.id,
        ],
      );
      return const Success(null);
    } catch (e) {
      return Err(DatabaseFailure('Failed to update academic term: $e'));
    }
  }

  @override
  Future<Result<void, Failure>> deleteTerm(String termId) async {
    try {
      _db.execute('DELETE FROM academic_terms WHERE id = ?;', [termId]);
      return const Success(null);
    } catch (e) {
      return Err(DatabaseFailure('Failed to delete academic term: $e'));
    }
  }

  @override
  Future<Result<List<ClassroomEntity>, Failure>> getClassroomsForTerm(String termId) async {
    try {
      final rows = _db.select(
        'SELECT * FROM classrooms WHERE academic_term_id = ? ORDER BY course_code ASC, section ASC;',
        [termId],
      );
      final list = rows.map((r) => ClassroomEntity(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        academicTermId: r['academic_term_id'] as String,
        courseCode: r['course_code'] as String,
        courseName: r['course_name'] as String,
        section: r['section'] as String,
        instructorName: r['instructor_name'] as String,
        defaultCreditHours: (r['default_credit_hours'] as num).toDouble(),
        attendanceThreshold: (r['attendance_threshold'] as num).toDouble(),
        status: r['status'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      )).toList();
      return Success(list);
    } catch (e) {
      return Err(DatabaseFailure('Failed to get classrooms for term: $e'));
    }
  }

  @override
  Future<Result<ClassroomEntity?, Failure>> getClassroomById(String classroomId) async {
    try {
      final rows = _db.select(
        'SELECT * FROM classrooms WHERE id = ? LIMIT 1;',
        [classroomId],
      );
      if (rows.isEmpty) return const Success(null);
      final r = rows.first;
      return Success(ClassroomEntity(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        academicTermId: r['academic_term_id'] as String,
        courseCode: r['course_code'] as String,
        courseName: r['course_name'] as String,
        section: r['section'] as String,
        instructorName: r['instructor_name'] as String,
        defaultCreditHours: (r['default_credit_hours'] as num).toDouble(),
        attendanceThreshold: (r['attendance_threshold'] as num).toDouble(),
        status: r['status'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      ));
    } catch (e) {
      return Err(DatabaseFailure('Failed to get classroom by id: $e'));
    }
  }

  @override
  Future<Result<ClassroomEntity, Failure>> createClassroom(ClassroomEntity c) async {
    try {
      _db.execute(
        'INSERT INTO classrooms (id, user_id, academic_term_id, course_code, course_name, section, '
        'instructor_name, default_credit_hours, attendance_threshold, status, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          c.id,
          c.userId,
          c.academicTermId,
          c.courseCode,
          c.courseName,
          c.section,
          c.instructorName,
          c.defaultCreditHours,
          c.attendanceThreshold,
          c.status,
          c.createdAt.millisecondsSinceEpoch,
          c.updatedAt.millisecondsSinceEpoch,
        ],
      );
      return Success(c);
    } catch (e) {
      return Err(DatabaseFailure('Failed to create classroom: $e'));
    }
  }

  @override
  Future<Result<void, Failure>> updateClassroom(ClassroomEntity c) async {
    try {
      _db.execute(
        'UPDATE classrooms SET course_code = ?, course_name = ?, section = ?, instructor_name = ?, '
        'default_credit_hours = ?, attendance_threshold = ?, status = ?, updated_at = ? WHERE id = ?;',
        [
          c.courseCode,
          c.courseName,
          c.section,
          c.instructorName,
          c.defaultCreditHours,
          c.attendanceThreshold,
          c.status,
          DateTime.now().millisecondsSinceEpoch,
          c.id,
        ],
      );
      return const Success(null);
    } catch (e) {
      return Err(DatabaseFailure('Failed to update classroom: $e'));
    }
  }

  @override
  Future<Result<void, Failure>> deleteClassroom(String classroomId) async {
    try {
      _db.execute('DELETE FROM classrooms WHERE id = ?;', [classroomId]);
      return const Success(null);
    } catch (e) {
      return Err(DatabaseFailure('Failed to delete classroom: $e'));
    }
  }
}
