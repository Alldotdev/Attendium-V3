import 'package:sqlite3/sqlite3.dart';
import '../../../core/errors/failures.dart';
import '../../../core/result/result.dart';
import '../../../domain/entities/student.dart';
import '../../../domain/entities/student_alias.dart';
import '../../../domain/repositories/student_repository.dart';
import '../app_database.dart';

class StudentDao implements StudentRepository {
  final AppDatabase appDb;

  StudentDao(this.appDb);

  Database get _db => appDb.rawDb;

  @override
  Future<Result<List<StudentEntity>, Failure>> getStudentsForClassroom(String classroomId) async {
    try {
      final rows = _db.select('''
        SELECT s.*, e.roll_number as enrolled_roll
        FROM students s
        INNER JOIN enrollments e ON s.id = e.student_id
        WHERE e.classroom_id = ? AND e.status = 'active'
        ORDER BY e.roll_number ASC, s.full_name ASC;
      ''', [classroomId]);

      final list = rows.map((r) => StudentEntity(
        id: r['id'] as String,
        classroomId: classroomId,
        rollNumber: (r['enrolled_roll'] as String?) ?? (r['roll_number'] as String),
        fullName: r['full_name'] as String,
        normalizedName: r['normalized_name'] as String,
        email: r['email'] as String?,
        status: r['status'] as String,
        enrolledAt: DateTime.fromMillisecondsSinceEpoch(r['enrolled_at'] as int),
        withdrawnAt: r['withdrawn_at'] != null ? DateTime.fromMillisecondsSinceEpoch(r['withdrawn_at'] as int) : null,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      )).toList();

      return Success(list);
    } catch (e) {
      return Err(DatabaseFailure('Failed to get students for classroom: $e'));
    }
  }

  @override
  Future<Result<StudentEntity?, Failure>> getStudentById(String studentId) async {
    try {
      final rows = _db.select('SELECT * FROM students WHERE id = ? LIMIT 1;', [studentId]);
      if (rows.isEmpty) return const Success(null);
      final r = rows.first;
      return Success(StudentEntity(
        id: r['id'] as String,
        classroomId: r['classroom_id'] as String?,
        rollNumber: r['roll_number'] as String,
        fullName: r['full_name'] as String,
        normalizedName: r['normalized_name'] as String,
        email: r['email'] as String?,
        status: r['status'] as String,
        enrolledAt: DateTime.fromMillisecondsSinceEpoch(r['enrolled_at'] as int),
        withdrawnAt: r['withdrawn_at'] != null ? DateTime.fromMillisecondsSinceEpoch(r['withdrawn_at'] as int) : null,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      ));
    } catch (e) {
      return Err(DatabaseFailure('Failed to get student by id: $e'));
    }
  }

  @override
  Future<Result<StudentEntity?, Failure>> getStudentByRoll(String classroomId, String rollNumber) async {
    try {
      final rows = _db.select('''
        SELECT s.*, e.roll_number as enrolled_roll
        FROM students s
        INNER JOIN enrollments e ON s.id = e.student_id
        WHERE e.classroom_id = ? AND (e.roll_number = ? OR s.roll_number = ?)
        LIMIT 1;
      ''', [classroomId, rollNumber, rollNumber]);

      if (rows.isEmpty) return const Success(null);
      final r = rows.first;
      return Success(StudentEntity(
        id: r['id'] as String,
        classroomId: classroomId,
        rollNumber: (r['enrolled_roll'] as String?) ?? (r['roll_number'] as String),
        fullName: r['full_name'] as String,
        normalizedName: r['normalized_name'] as String,
        email: r['email'] as String?,
        status: r['status'] as String,
        enrolledAt: DateTime.fromMillisecondsSinceEpoch(r['enrolled_at'] as int),
        withdrawnAt: r['withdrawn_at'] != null ? DateTime.fromMillisecondsSinceEpoch(r['withdrawn_at'] as int) : null,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      ));
    } catch (e) {
      return Err(DatabaseFailure('Failed to get student by roll: $e'));
    }
  }

  @override
  Future<Result<StudentEntity, Failure>> createStudent(StudentEntity s) async {
    try {
      _db.execute(
        'INSERT INTO students (id, classroom_id, roll_number, full_name, normalized_name, email, status, '
        'enrolled_at, withdrawn_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          s.id,
          s.classroomId,
          s.rollNumber,
          s.fullName,
          s.normalizedName,
          s.email,
          s.status,
          s.enrolledAt.millisecondsSinceEpoch,
          s.withdrawnAt?.millisecondsSinceEpoch,
          s.createdAt.millisecondsSinceEpoch,
          s.updatedAt.millisecondsSinceEpoch,
        ],
      );

      // If classroomId is provided, also insert into enrollments junction
      if (s.classroomId != null) {
        await enrollStudentInClassroom(s.id, s.classroomId!, s.rollNumber);
      }

      return Success(s);
    } catch (e) {
      return Err(DatabaseFailure('Failed to create student: $e'));
    }
  }

  @override
  Future<Result<void, Failure>> updateStudent(StudentEntity s) async {
    try {
      _db.execute(
        'UPDATE students SET roll_number = ?, full_name = ?, normalized_name = ?, email = ?, status = ?, '
        'withdrawn_at = ?, updated_at = ? WHERE id = ?;',
        [
          s.rollNumber,
          s.fullName,
          s.normalizedName,
          s.email,
          s.status,
          s.withdrawnAt?.millisecondsSinceEpoch,
          DateTime.now().millisecondsSinceEpoch,
          s.id,
        ],
      );
      return const Success(null);
    } catch (e) {
      return Err(DatabaseFailure('Failed to update student: $e'));
    }
  }

  @override
  Future<Result<void, Failure>> enrollStudentInClassroom(String studentId, String classroomId, String rollNumber) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      _db.execute('''
        INSERT INTO enrollments (id, student_id, classroom_id, roll_number, enrolled_at, status, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, 'active', ?, ?)
        ON CONFLICT(student_id, classroom_id) DO UPDATE SET
          roll_number = excluded.roll_number,
          status = 'active',
          withdrawn_at = NULL,
          updated_at = excluded.updated_at;
      ''', [
        '${studentId}_$classroomId',
        studentId,
        classroomId,
        rollNumber,
        now,
        now,
        now,
      ]);
      return const Success(null);
    } catch (e) {
      return Err(DatabaseFailure('Failed to enroll student: $e'));
    }
  }

  @override
  Future<Result<void, Failure>> withdrawStudentFromClassroom(String studentId, String classroomId) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      _db.execute(
        "UPDATE enrollments SET status = 'withdrawn', withdrawn_at = ?, updated_at = ? "
        "WHERE student_id = ? AND classroom_id = ?;",
        [now, now, studentId, classroomId],
      );
      return const Success(null);
    } catch (e) {
      return Err(DatabaseFailure('Failed to withdraw student: $e'));
    }
  }

  @override
  Future<Result<void, Failure>> removeStudentFromClassroom(String studentId, String classroomId) async {
    try {
      _db.execute(
        'DELETE FROM attendance_records WHERE student_id = ? AND session_id IN (SELECT id FROM course_sessions WHERE classroom_id = ?);',
        [studentId, classroomId],
      );
      _db.execute(
        'DELETE FROM enrollments WHERE student_id = ? AND classroom_id = ?;',
        [studentId, classroomId],
      );
      return const Success(null);
    } catch (e) {
      return Err(DatabaseFailure('Failed to remove student from classroom: $e'));
    }
  }

  @override
  Future<Result<void, Failure>> deleteStudent(String studentId) async {
    try {
      _db.execute('DELETE FROM students WHERE id = ?;', [studentId]);
      return const Success(null);
    } catch (e) {
      return Err(DatabaseFailure('Failed to delete student: $e'));
    }
  }

  @override
  Future<Result<List<StudentAliasEntity>, Failure>> getAliasesForStudent(String studentId) async {
    try {
      final rows = _db.select('SELECT * FROM student_aliases WHERE student_id = ?;', [studentId]);
      final list = rows.map((r) => StudentAliasEntity(
        id: r['id'] as String,
        studentId: r['student_id'] as String,
        alias: r['alias'] as String,
        normalizedAlias: r['normalized_alias'] as String,
        source: r['source'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      )).toList();
      return Success(list);
    } catch (e) {
      return Err(DatabaseFailure('Failed to get student aliases: $e'));
    }
  }

  @override
  Future<Result<StudentAliasEntity, Failure>> addAlias(String studentId, String alias, String source) async {
    try {
      final id = '${studentId}_${DateTime.now().millisecondsSinceEpoch}';
      final now = DateTime.now();
      _db.execute(
        'INSERT INTO student_aliases (id, student_id, alias, normalized_alias, source, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?);',
        [id, studentId, alias, alias.toLowerCase().trim(), source, now.millisecondsSinceEpoch],
      );
      return Success(StudentAliasEntity(
        id: id,
        studentId: studentId,
        alias: alias,
        normalizedAlias: alias.toLowerCase().trim(),
        source: source,
        createdAt: now,
      ));
    } catch (e) {
      return Err(DatabaseFailure('Failed to add student alias: $e'));
    }
  }
}
