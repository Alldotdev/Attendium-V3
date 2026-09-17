import 'dart:convert';
import 'dart:typed_data';
import 'package:attendium/domain/entities/academic_term.dart';
import 'package:attendium/domain/entities/attendance_record.dart';
import 'package:attendium/domain/entities/classroom.dart';
import 'package:attendium/domain/entities/course_session.dart';
import 'package:attendium/domain/entities/student.dart';
import 'package:attendium/domain/enums/attendance_status.dart';
import 'package:attendium/domain/enums/session_type.dart';
import 'package:attendium/domain/enums/term_status.dart';
import 'package:attendium/domain/services/fuzzy_matcher.dart';
import 'package:attendium/infrastructure/ai/deterministic_local_provider.dart';
import 'package:attendium/infrastructure/database/app_database.dart';
import 'package:attendium/infrastructure/database/daos/attendance_dao.dart';
import 'package:attendium/infrastructure/database/daos/audit_dao.dart';
import 'package:attendium/infrastructure/database/daos/classroom_dao.dart';
import 'package:attendium/infrastructure/database/daos/session_dao.dart';
import 'package:attendium/infrastructure/database/daos/student_dao.dart';
import 'package:attendium/infrastructure/document/document_hasher.dart';
import 'package:attendium/infrastructure/export/excel_generator.dart';
import 'package:attendium/infrastructure/export/pdf_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('End-to-End Import Pipeline Integration Test', () {
    late AppDatabase db;
    late ClassroomDao classroomDao;
    late StudentDao studentDao;
    late SessionDao sessionDao;
    late AttendanceDao attendanceDao;
    late AuditDao auditDao;

    setUp(() async {
      db = AppDatabase.inMemory();
      classroomDao = ClassroomDao(db);
      studentDao = StudentDao(db);
      sessionDao = SessionDao(db);
      auditDao = AuditDao(db);
      attendanceDao = AttendanceDao(db, auditDao);

      // Seed User, Term & Classroom
      final now = DateTime.now();
      db.rawDb.execute(
        'INSERT INTO users (id, google_subject, email, display_name, institution_name, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?);',
        ['usr_test', 'sub_test', 'test@attendium.local', 'Dr. Turing', 'Institute', now.millisecondsSinceEpoch, now.millisecondsSinceEpoch],
      );

      await classroomDao.createTerm(AcademicTermEntity(
        id: 'term_test',
        userId: 'usr_test',
        name: 'Test Term',
        startDate: now.subtract(const Duration(days: 30)),
        endDate: now.add(const Duration(days: 60)),
        status: TermStatus.active,
        createdAt: now,
        updatedAt: now,
      ));

      await classroomDao.createClassroom(ClassroomEntity(
        id: 'cls_test',
        userId: 'usr_test',
        academicTermId: 'term_test',
        courseCode: 'CS-301',
        courseName: 'Database Systems',
        section: 'Sec A',
        instructorName: 'Dr. Turing',
        createdAt: now,
        updatedAt: now,
      ));

      // Seed Roster of 4 students with aliases
      final students = [
        StudentEntity(id: 's1', rollNumber: 'CS-101', fullName: 'Alice Johnson', normalizedName: 'alice johnson', enrolledAt: now, createdAt: now, updatedAt: now),
        StudentEntity(id: 's2', rollNumber: 'CS-102', fullName: 'Bob Smith', normalizedName: 'bob smith', enrolledAt: now, createdAt: now, updatedAt: now),
        StudentEntity(id: 's3', rollNumber: 'CS-103', fullName: 'Carlos Rivera', normalizedName: 'carlos rivera', enrolledAt: now, createdAt: now, updatedAt: now),
        StudentEntity(id: 's4', rollNumber: 'CS-104', fullName: 'Diana Prince', normalizedName: 'diana prince', enrolledAt: now, createdAt: now, updatedAt: now),
      ];

      for (final s in students) {
        await studentDao.createStudent(s);
        await studentDao.enrollStudentInClassroom(s.id, 'cls_test', s.rollNumber);
      }

      await studentDao.addAlias('s1', 'Alicia Johnson', 'manual');
    });

    tearDown(() {
      db.close();
    });

    test('Full Pipeline: CSV Ingest -> SHA256 -> AI Extract -> Fuzzy Match -> Commit to SQLite -> Export XLSX/PDF', () async {
      // 1. Prepare raw CSV document with slight OCR variations
      final csvContent = '''
Roll Number,Student Name,Attendance,Visual Confidence
CS-101,Alice Johnson,Present,0.98
CS-1O2,Bob Smith,Late,0.95
CS-103,Carlos R.,Absent,0.88
CS-999,Unknown Person,Present,0.70
''';
      final csvBytes = Uint8List.fromList(utf8.encode(csvContent));

      // 2. Hash Document for duplicate detection
      final hash = DocumentHasher.hashBytes(csvBytes);
      expect(hash, isNotEmpty);
      expect(hash.length, equals(64));

      // 3. Multimodal / Local AI Extraction
      final aiProvider = DeterministicLocalProvider();
      final extractRes = await aiProvider.extractAttendance(
        documentBytes: csvBytes,
        mimeType: 'text/csv',
      );
      expect(extractRes.isSuccess, isTrue);
      final payload = extractRes.successOrNull!;
      expect(payload.rows.length, equals(4));

      // 4. Deterministic Fuzzy Matching against Classroom Roster
      final roster = (await studentDao.getStudentsForClassroom('cls_test')).successOrNull!;
      final candidates = <StudentMatchCandidate>[];
      for (final s in roster) {
        final aliases = (await studentDao.getAliasesForStudent(s.id)).successOrNull!.map((a) => a.alias).toList();
        candidates.add(StudentMatchCandidate(
          id: s.id,
          rollNumber: s.rollNumber,
          fullName: s.fullName,
          normalizedName: s.normalizedName,
          aliases: aliases,
          isEnrolledInClassroom: true,
        ));
      }

      const matcher = FuzzyMatcher();
      final matchedRecords = <AttendanceRecordEntity>[];
      final now = DateTime.now();

      // Create target session
      final session = CourseSessionEntity(
        id: 'sess_import_test',
        classroomId: 'cls_test',
        sessionDate: '2026-09-17',
        topic: 'Integration Test Session',
        sessionType: SessionType.lecture,
        creditWeight: 1.0,
        createdAt: now,
        updatedAt: now,
      );
      await sessionDao.createSession(session);

      for (final row in payload.rows) {
        final matches = matcher.match(
          rawRoll: row.rawRoll,
          rawName: row.rawName,
          candidates: candidates,
        );

        if (matches.isNotEmpty && matches.first.isMatched) {
          final top = matches.first;
          final status = AttendanceStatus.fromString(row.rawAttendance);
          matchedRecords.add(AttendanceRecordEntity(
            id: '${session.id}_${top.candidate!.id}',
            sessionId: session.id,
            studentId: top.candidate!.id,
            status: status,
            source: 'ai_import',
            confidenceScore: top.finalScore,
            notes: 'Imported with confidence band: ${top.band.name}',
            createdAt: now,
            updatedAt: now,
          ));
        }
      }

      // Expected: CS-101 (Alice), CS-1O2 (Bob with OCR fix), CS-103 (Carlos R. fuzzy) matched
      // CS-999 is unknown and correctly omitted
      expect(matchedRecords.length, equals(3));

      // 5. Commit batch to SQLite transactionally
      final commitRes = await attendanceDao.recordBatchAttendance(
        sessionId: session.id,
        records: matchedRecords,
        source: 'ai_import',
      );
      expect(commitRes.isSuccess, isTrue);

      // Verify records stored in SQLite
      final dbRecords = (await attendanceDao.getRecordsForSession(session.id)).successOrNull!;
      expect(dbRecords.length, equals(3));

      // Verify Alice is Present
      final aliceRecord = dbRecords.firstWhere((r) => r.studentId == 's1');
      expect(aliceRecord.status, equals(AttendanceStatus.present));

      // Verify Bob is Late
      final bobRecord = dbRecords.firstWhere((r) => r.studentId == 's2');
      expect(bobRecord.status, equals(AttendanceStatus.late));

      // Verify Carlos is Absent
      final carlosRecord = dbRecords.firstWhere((r) => r.studentId == 's3');
      expect(carlosRecord.status, equals(AttendanceStatus.absent));

      // 6. Verify Audit Trail was recorded for the batch commit
      final auditLogs = (await auditDao.getRecentLogs()).successOrNull!;
      expect(auditLogs, isNotEmpty);
      expect(auditLogs.any((log) => log.source == 'ai_import'), isTrue);

      // 7. Verify Excel Report generation with the committed data
      final classroom = (await classroomDao.getClassroomById('cls_test')).successOrNull!;
      final excelRes = ExcelGenerator.generateClassroomReport(
        classroom: classroom,
        students: roster,
        sessions: [session],
        records: dbRecords,
        auditLogs: auditLogs,
      );
      expect(excelRes.isSuccess, isTrue);
      final excelBytes = excelRes.successOrNull!;
      expect(excelBytes.length, greaterThan(1000));

      // 8. Verify PDF Report generation
      final pdfRes = await PdfGenerator.generateClassroomPdf(
        institutionName: 'Attendium Academic System',
        classroom: classroom,
        students: roster,
        sessions: [session],
        records: dbRecords,
      );
      expect(pdfRes.isSuccess, isTrue);
      final pdfBytes = pdfRes.successOrNull!;
      expect(pdfBytes.length, greaterThan(1000));
      // Starts with %PDF
      expect(pdfBytes.sublist(0, 4), equals(utf8.encode('%PDF')));
    });
  });
}
