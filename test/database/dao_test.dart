import 'package:flutter_test/flutter_test.dart';
import 'package:attendium/domain/entities/academic_term.dart';
import 'package:attendium/domain/entities/attendance_record.dart';
import 'package:attendium/domain/entities/classroom.dart';
import 'package:attendium/domain/entities/course_session.dart';
import 'package:attendium/domain/entities/student.dart';
import 'package:attendium/domain/enums/attendance_status.dart';
import 'package:attendium/domain/enums/audit_action.dart';
import 'package:attendium/domain/enums/session_type.dart';
import 'package:attendium/domain/enums/term_status.dart';
import 'package:attendium/infrastructure/database/app_database.dart';
import 'package:attendium/infrastructure/database/daos/attendance_dao.dart';
import 'package:attendium/infrastructure/database/daos/audit_dao.dart';
import 'package:attendium/infrastructure/database/daos/classroom_dao.dart';
import 'package:attendium/infrastructure/database/daos/student_dao.dart';
import 'package:attendium/infrastructure/database/daos/session_dao.dart';

void main() {
  group('DAO End-to-End Repository Tests', () {
    late AppDatabase appDb;
    late ClassroomDao classroomDao;
    late StudentDao studentDao;
    late SessionDao sessionDao;
    late AuditDao auditDao;
    late AttendanceDao attendanceDao;

    setUp(() {
      appDb = AppDatabase.inMemory();
      classroomDao = ClassroomDao(appDb);
      studentDao = StudentDao(appDb);
      sessionDao = SessionDao(appDb);
      auditDao = AuditDao(appDb);
      attendanceDao = AttendanceDao(appDb, auditDao);

      // Seed a user
      appDb.rawDb.execute(
        "INSERT INTO users (id, email, display_name, created_at, updated_at) "
        "VALUES ('user1', 'prof@univ.edu', 'Prof. Alan Turing', 1000, 1000);",
      );
    });

    tearDown(() {
      appDb.close();
    });

    test('Full Term, Classroom, Student, and Session workflow', () async {
      // 1. Create term
      final term = AcademicTermEntity(
        id: 'term_fall2026',
        userId: 'user1',
        name: 'Fall 2026',
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 12, 20),
        status: TermStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final termResult = await classroomDao.createTerm(term);
      expect(termResult.isSuccess, true);

      // 2. Create classroom
      final classroom = ClassroomEntity(
        id: 'class_cs101',
        userId: 'user1',
        academicTermId: 'term_fall2026',
        courseCode: 'CS-101',
        courseName: 'Intro to Computer Science',
        section: 'A',
        instructorName: 'Prof. Alan Turing',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final classResult = await classroomDao.createClassroom(classroom);
      expect(classResult.isSuccess, true);

      // 3. Create students
      final student1 = StudentEntity(
        id: 'stud_1',
        classroomId: 'class_cs101',
        rollNumber: 'CS-001',
        fullName: 'Ada Lovelace',
        normalizedName: 'ada lovelace',
        enrolledAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final studentResult = await studentDao.createStudent(student1);
      expect(studentResult.isSuccess, true);

      // Verify student is enrolled in classroom
      final enrolled = await studentDao.getStudentsForClassroom('class_cs101');
      expect(enrolled.isSuccess, true);
      expect(enrolled.successOrNull?.length, 1);
      expect(enrolled.successOrNull?.first.fullName, 'Ada Lovelace');

      // 4. Create session
      final session = CourseSessionEntity(
        id: 'sess_1',
        classroomId: 'class_cs101',
        sessionDate: '2026-09-02',
        topic: 'Introduction to Algorithms',
        creditWeight: 1.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final sessResult = await sessionDao.createSession(session);
      expect(sessResult.isSuccess, true);

      // 5. Record batch attendance
      final record = AttendanceRecordEntity(
        id: 'rec_1',
        sessionId: 'sess_1',
        studentId: 'stud_1',
        status: AttendanceStatus.present,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final batchResult = await attendanceDao.recordBatchAttendance(
        sessionId: 'sess_1',
        records: [record],
        source: 'manual_grid',
      );
      expect(batchResult.isSuccess, true);

      // Verify attendance record exists
      final records = await attendanceDao.getRecordsForSession('sess_1');
      expect(records.isSuccess, true);
      expect(records.successOrNull?.length, 1);
      expect(records.successOrNull?.first.status, AttendanceStatus.present);

      // 6. Update attendance record with reason & audit logging (Section 42)
      final updated = record.copyWith(status: AttendanceStatus.late);
      final editResult = await attendanceDao.updateSingleAttendanceRecord(
        updatedRecord: updated,
        reason: 'Arrived 15 minutes late due to transit delay',
        userId: 'user1',
      );
      expect(editResult.isSuccess, true);

      // Verify updated status
      final updatedRecords = await attendanceDao.getRecordsForSession('sess_1');
      expect(updatedRecords.successOrNull?.first.status, AttendanceStatus.late);

      // Verify audit log entry was created
      final logs = await auditDao.getLogsForEntity('attendance_record', 'rec_1');
      expect(logs.isSuccess, true);
      expect(logs.successOrNull?.length, 1);
      final log = logs.successOrNull!.first;
      expect(log.action, AuditAction.statusChange);
      expect(log.reason, 'Arrived 15 minutes late due to transit delay');
      expect(log.beforeJson?.contains('present'), true);
      expect(log.afterJson?.contains('late'), true);
    });

    test('Classroom, Student, and Session CRUD Operations (Edit & Delete)', () async {
      // 1. Create term & classroom
      final term = AcademicTermEntity(
        id: 'term_crud',
        userId: 'user1',
        name: 'Spring 2026',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 5, 30),
        status: TermStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await classroomDao.createTerm(term);

      final classroom = ClassroomEntity(
        id: 'class_crud',
        userId: 'user1',
        academicTermId: 'term_crud',
        courseCode: 'MATH-101',
        courseName: 'Calculus I',
        section: 'B',
        instructorName: 'Prof. Euler',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await classroomDao.createClassroom(classroom);

      // 2. Edit classroom
      final updatedClass = classroom.copyWith(
        courseName: 'Calculus I - Advanced',
        attendanceThreshold: 80.0,
      );
      final updateRes = await classroomDao.updateClassroom(updatedClass);
      expect(updateRes.isSuccess, true);
      final fetchedClass = await classroomDao.getClassroomById('class_crud');
      expect(fetchedClass.successOrNull?.courseName, 'Calculus I - Advanced');
      expect(fetchedClass.successOrNull?.attendanceThreshold, 80.0);

      // 3. Create two students
      final s1 = StudentEntity(
        id: 'stud_crud_1',
        classroomId: 'class_crud',
        rollNumber: 'M-101',
        fullName: 'Carl Gauss',
        normalizedName: 'carl gauss',
        enrolledAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final s2 = StudentEntity(
        id: 'stud_crud_2',
        classroomId: 'class_crud',
        rollNumber: 'M-102',
        fullName: 'Bernhard Riemann',
        normalizedName: 'bernhard riemann',
        enrolledAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await studentDao.createStudent(s1);
      await studentDao.createStudent(s2);

      var roster = await studentDao.getStudentsForClassroom('class_crud');
      expect(roster.successOrNull?.length, 2);

      // 4. Remove s1 from classroom
      final removeRes = await studentDao.removeStudentFromClassroom('stud_crud_1', 'class_crud');
      expect(removeRes.isSuccess, true);
      roster = await studentDao.getStudentsForClassroom('class_crud');
      expect(roster.successOrNull?.length, 1);
      expect(roster.successOrNull?.first.id, 'stud_crud_2');

      // 5. Delete s2 permanently
      final deleteStudRes = await studentDao.deleteStudent('stud_crud_2');
      expect(deleteStudRes.isSuccess, true);
      final fetchedS2 = await studentDao.getStudentById('stud_crud_2');
      expect(fetchedS2.successOrNull, isNull);

      // 6. Create session and delete it
      final session = CourseSessionEntity(
        id: 'sess_crud_1',
        classroomId: 'class_crud',
        sessionDate: '2026-03-01',
        topic: 'Limits and Derivatives',
        sessionType: SessionType.lecture,
        creditWeight: 1.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await sessionDao.createSession(session);
      var sessions = await sessionDao.getSessionsForClassroom('class_crud');
      expect(sessions.successOrNull?.length, 1);

      final delSessRes = await sessionDao.deleteSession('sess_crud_1');
      expect(delSessRes.isSuccess, true);
      sessions = await sessionDao.getSessionsForClassroom('class_crud');
      expect(sessions.successOrNull?.isEmpty, true);

      // 7. Delete classroom
      final delClassRes = await classroomDao.deleteClassroom('class_crud');
      expect(delClassRes.isSuccess, true);
      final fetchedDeletedClass = await classroomDao.getClassroomById('class_crud');
      expect(fetchedDeletedClass.successOrNull, isNull);
    });
  });
}
