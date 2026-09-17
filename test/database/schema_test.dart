import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:attendium/infrastructure/database/app_database.dart';

void main() {
  group('Database Schema & Constraint Verification', () {
    late AppDatabase appDb;
    late Database db;

    setUp(() {
      appDb = AppDatabase.inMemory();
      db = appDb.rawDb;
    });

    tearDown(() {
      appDb.close();
    });

    test('Foreign keys pragma is active (PRAGMA foreign_keys = 1)', () {
      final rows = db.select('PRAGMA foreign_keys;');
      expect(rows.first['foreign_keys'], 1);
    });

    test('All 14 tables exist in sqlite_master', () {
      final rows = db.select("SELECT name FROM sqlite_master WHERE type='table';");
      final tableNames = rows.map((r) => r['name'] as String).toSet();

      final requiredTables = [
        'users',
        'academic_terms',
        'classrooms',
        'students',
        'enrollments',
        'student_aliases',
        'course_sessions',
        'attendance_records',
        'attendance_policies',
        'audit_logs',
        'import_jobs',
        'extraction_rows',
        'attendance_alerts',
        'backup_jobs',
      ];

      for (final table in requiredTables) {
        expect(tableNames.contains(table), true, reason: 'Table $table must exist');
      }
    });

    test('Foreign key enforcement blocks invalid references', () {
      // Inserting academic_term with non-existent user_id must throw SqliteException
      expect(
        () => db.execute(
          "INSERT INTO academic_terms (id, user_id, name, start_date, end_date, created_at, updated_at) "
          "VALUES ('term1', 'non_existent_user', 'Fall 2026', 1000, 2000, 1000, 1000);",
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('Cascade deletion works properly', () {
      // 1. Insert user
      db.execute(
        "INSERT INTO users (id, email, display_name, created_at, updated_at) "
        "VALUES ('u1', 'prof@univ.edu', 'Prof. Smith', 1000, 1000);",
      );

      // 2. Insert term
      db.execute(
        "INSERT INTO academic_terms (id, user_id, name, start_date, end_date, created_at, updated_at) "
        "VALUES ('t1', 'u1', 'Fall 2026', 1000, 2000, 1000, 1000);",
      );

      // 3. Insert classroom
      db.execute(
        "INSERT INTO classrooms (id, user_id, academic_term_id, course_code, course_name, section, instructor_name, created_at, updated_at) "
        "VALUES ('c1', 'u1', 't1', 'CS-101', 'Intro to CS', 'A', 'Prof. Smith', 1000, 1000);",
      );

      // 4. Insert session
      db.execute(
        "INSERT INTO course_sessions (id, classroom_id, session_date, created_at, updated_at) "
        "VALUES ('s1', 'c1', '2026-09-01', 1000, 1000);",
      );

      expect(db.select("SELECT * FROM course_sessions WHERE id='s1';").length, 1);

      // 5. Delete classroom -> course_session should cascade delete
      db.execute("DELETE FROM classrooms WHERE id='c1';");
      expect(db.select("SELECT * FROM course_sessions WHERE id='s1';").isEmpty, true);
    });

    test('AttendanceRecords unique constraint prevents duplicate student attendance in same session', () {
      // Setup hierarchy
      db.execute("INSERT INTO users (id, email, display_name, created_at, updated_at) VALUES ('u1', 'p@u.edu', 'Prof', 1, 1);");
      db.execute("INSERT INTO academic_terms (id, user_id, name, start_date, end_date, created_at, updated_at) VALUES ('t1', 'u1', 'T1', 1, 2, 1, 1);");
      db.execute("INSERT INTO classrooms (id, user_id, academic_term_id, course_code, course_name, section, instructor_name, created_at, updated_at) VALUES ('c1', 'u1', 't1', 'CS', 'CS', 'A', 'Prof', 1, 1);");
      db.execute("INSERT INTO course_sessions (id, classroom_id, session_date, created_at, updated_at) VALUES ('s1', 'c1', '2026-09-01', 1, 1);");
      db.execute("INSERT INTO students (id, roll_number, full_name, normalized_name, enrolled_at, created_at, updated_at) VALUES ('st1', '001', 'Alice', 'alice', 1, 1, 1);");

      // First record succeeds
      db.execute("INSERT INTO attendance_records (id, session_id, student_id, status, created_at, updated_at) VALUES ('r1', 's1', 'st1', 'present', 1, 1);");

      // Duplicate record for same (session_id, student_id) must fail with SqliteException
      expect(
        () => db.execute("INSERT INTO attendance_records (id, session_id, student_id, status, created_at, updated_at) VALUES ('r2', 's1', 'st1', 'absent', 2, 2);"),
        throwsA(isA<SqliteException>()),
      );
    });
  });
}
