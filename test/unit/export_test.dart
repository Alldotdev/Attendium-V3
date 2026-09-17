import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendium/domain/entities/attendance_record.dart';
import 'package:attendium/domain/entities/audit_log.dart';
import 'package:attendium/domain/entities/classroom.dart';
import 'package:attendium/domain/entities/course_session.dart';
import 'package:attendium/domain/entities/student.dart';
import 'package:attendium/domain/enums/attendance_status.dart';
import 'package:attendium/domain/enums/audit_action.dart';
import 'package:attendium/infrastructure/export/excel_generator.dart';
import 'package:attendium/infrastructure/export/pdf_generator.dart';

void main() {
  group('Export Generator Tests (Section 33 & 34)', () {
    final classroom = ClassroomEntity(
      id: 'c1',
      userId: 'u1',
      academicTermId: 't1',
      courseCode: 'CS-301',
      courseName: 'Operating Systems',
      section: 'B',
      instructorName: 'Dr. Grace Hopper',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final students = [
      StudentEntity(
        id: 's1',
        rollNumber: 'CS-001',
        fullName: 'Grace Hopper',
        normalizedName: 'grace hopper',
        enrolledAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      StudentEntity(
        id: 's2',
        rollNumber: 'CS-002',
        fullName: 'Claude Shannon',
        normalizedName: 'claude shannon',
        enrolledAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    final sessions = [
      CourseSessionEntity(
        id: 'sess1',
        classroomId: 'c1',
        sessionDate: '2026-09-01',
        topic: 'Process Scheduling',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      CourseSessionEntity(
        id: 'sess2',
        classroomId: 'c1',
        sessionDate: '2026-09-03',
        topic: 'Memory Management',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    final records = [
      AttendanceRecordEntity(
        id: 'r1',
        sessionId: 'sess1',
        studentId: 's1',
        status: AttendanceStatus.present,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      AttendanceRecordEntity(
        id: 'r2',
        sessionId: 'sess1',
        studentId: 's2',
        status: AttendanceStatus.late,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      AttendanceRecordEntity(
        id: 'r3',
        sessionId: 'sess2',
        studentId: 's1',
        status: AttendanceStatus.present,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      AttendanceRecordEntity(
        id: 'r4',
        sessionId: 'sess2',
        studentId: 's2',
        status: AttendanceStatus.absent,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    final auditLogs = [
      AuditLogEntity(
        id: 'a1',
        userId: 'u1',
        entityType: 'attendance_record',
        entityId: 'r2',
        action: AuditAction.statusChange,
        reason: 'Student arrived late',
        source: 'manual_grid',
        createdAt: DateTime.now(),
      ),
    ];

    test('ExcelGenerator creates multi-sheet report with valid bytes', () {
      final result = ExcelGenerator.generateClassroomReport(
        classroom: classroom,
        students: students,
        sessions: sessions,
        records: records,
        auditLogs: auditLogs,
      );

      expect(result.isSuccess, true);
      final bytes = result.successOrNull!;
      expect(bytes.isNotEmpty, true);
      // Verify ZIP/XLSX magic header: PK (0x50, 0x4B)
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);
    });

    test('PdfGenerator creates print-ready document starting with %PDF', () async {
      final result = await PdfGenerator.generateClassroomPdf(
        institutionName: 'Stanford Institute of Technology',
        classroom: classroom,
        students: students,
        sessions: sessions,
        records: records,
      );

      expect(result.isSuccess, true);
      final bytes = result.successOrNull!;
      expect(bytes.isNotEmpty, true);
      // Verify PDF file signature: %PDF (0x25, 0x50, 0x44, 0x46)
      final signature = utf8.decode(bytes.sublist(0, 4));
      expect(signature, '%PDF');
    });
  });
}
