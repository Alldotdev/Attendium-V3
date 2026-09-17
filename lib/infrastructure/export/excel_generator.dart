import 'dart:typed_data';
import 'package:excel/excel.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/failures.dart';
import '../../core/result/result.dart';
import '../../domain/entities/attendance_record.dart';
import '../../domain/entities/audit_log.dart';
import '../../domain/entities/classroom.dart';
import '../../domain/entities/course_session.dart';
import '../../domain/entities/student.dart';
import '../../domain/enums/attendance_status.dart';
import '../../domain/services/attendance_calculator.dart';

/// Multi-sheet Excel workbook generator adhering to Section 33.
class ExcelGenerator {
  const ExcelGenerator._();

  static Result<Uint8List, Failure> generateClassroomReport({
    required ClassroomEntity classroom,
    required List<StudentEntity> students,
    required List<CourseSessionEntity> sessions,
    required List<AttendanceRecordEntity> records,
    required List<AuditLogEntity> auditLogs,
    AttendancePolicyConfig policy = const AttendancePolicyConfig(),
  }) {
    try {
      final excel = Excel.createExcel();

      // Ensure default sheet is renamed or replaced
      const summarySheetName = 'Attendance Summary';
      const matrixSheetName = 'Session Matrix';
      const statsSheetName = 'Class Statistics';
      const auditSheetName = 'Audit Log';
      const metaSheetName = 'Metadata';

      // 1. Build Index Maps for O(1) Lookups
      // session_id -> student_id -> record
      final recordMap = <String, Map<String, AttendanceRecordEntity>>{};
      for (final r in records) {
        recordMap.putIfAbsent(r.sessionId, () => {})[r.studentId] = r;
      }

      // Calculate statistics per student
      final studentStats = <String, AttendanceCalculationResult>{};
      for (final s in students) {
        final studentRecords = <SessionRecordInput>[];
        for (final sess in sessions) {
          final r = recordMap[sess.id]?[s.id];
          final status = r?.status ?? AttendanceStatus.unmarked;
          studentRecords.add(SessionRecordInput(
            sessionId: sess.id,
            status: status,
            sessionCreditWeight: sess.creditWeight,
          ));
        }
        studentStats[s.id] = AttendanceCalculator.calculate(
          records: studentRecords,
          policy: policy,
        );
      }

      // -------------------------------------------------------------
      // SHEET 1: Attendance Summary
      // -------------------------------------------------------------
      final sheetSummary = excel[summarySheetName];
      sheetSummary.appendRow([
        TextCellValue('Roll Number'),
        TextCellValue('Full Name'),
        TextCellValue('Total Sessions'),
        TextCellValue('Present'),
        TextCellValue('Late'),
        TextCellValue('Excused'),
        TextCellValue('Absent'),
        TextCellValue('Unmarked'),
        TextCellValue('Percentage (%)'),
        TextCellValue('Standing'),
      ]);

      for (final s in students) {
        final calc = studentStats[s.id]!;
        sheetSummary.appendRow([
          TextCellValue(s.rollNumber),
          TextCellValue(s.fullName),
          IntCellValue(calc.totalSessions),
          IntCellValue(calc.presentCount),
          IntCellValue(calc.lateCount),
          IntCellValue(calc.excusedCount),
          IntCellValue(calc.absentCount),
          IntCellValue(calc.unmarkedCount),
          DoubleCellValue(double.parse(calc.percentage.toStringAsFixed(1))),
          TextCellValue(calc.classification.label),
        ]);
      }

      // -------------------------------------------------------------
      // SHEET 2: Session Matrix
      // -------------------------------------------------------------
      final sheetMatrix = excel[matrixSheetName];
      final matrixHeaders = <CellValue>[
        TextCellValue('Roll Number'),
        TextCellValue('Full Name'),
      ];
      for (final sess in sessions) {
        matrixHeaders.add(TextCellValue('${sess.sessionDate} (${sess.sessionType.label})'));
      }
      sheetMatrix.appendRow(matrixHeaders);

      for (final s in students) {
        final rowValues = <CellValue>[
          TextCellValue(s.rollNumber),
          TextCellValue(s.fullName),
        ];
        for (final sess in sessions) {
          final r = recordMap[sess.id]?[s.id];
          final status = r?.status ?? AttendanceStatus.unmarked;
          rowValues.add(TextCellValue(status.code));
        }
        sheetMatrix.appendRow(rowValues);
      }

      // -------------------------------------------------------------
      // SHEET 3: Class Statistics
      // -------------------------------------------------------------
      final sheetStats = excel[statsSheetName];
      sheetStats.appendRow([TextCellValue('Metric'), TextCellValue('Value')]);
      sheetStats.appendRow([TextCellValue('Course Code'), TextCellValue(classroom.courseCode)]);
      sheetStats.appendRow([TextCellValue('Course Name'), TextCellValue(classroom.courseName)]);
      sheetStats.appendRow([TextCellValue('Section'), TextCellValue(classroom.section)]);
      sheetStats.appendRow([TextCellValue('Instructor'), TextCellValue(classroom.instructorName)]);
      sheetStats.appendRow([TextCellValue('Total Students Enrolled'), IntCellValue(students.length)]);
      sheetStats.appendRow([TextCellValue('Total Sessions Conducted'), IntCellValue(sessions.length)]);

      final avgPct = students.isNotEmpty
          ? studentStats.values.map((e) => e.percentage).reduce((a, b) => a + b) / students.length
          : 100.0;
      sheetStats.appendRow([TextCellValue('Class Average Attendance'), TextCellValue('${avgPct.toStringAsFixed(1)}%')]);
      sheetStats.appendRow([TextCellValue('Safe Students (>= ${policy.minimumPercentage}%)'), IntCellValue(studentStats.values.where((e) => e.isSafe).length)]);
      sheetStats.appendRow([TextCellValue('At-Risk Students'), IntCellValue(studentStats.values.where((e) => e.isAtRisk).length)]);
      sheetStats.appendRow([TextCellValue('Short Attendance Students'), IntCellValue(studentStats.values.where((e) => e.isShort).length)]);
      sheetStats.appendRow([TextCellValue('Debarred Students (< ${policy.debarThreshold}%)'), IntCellValue(studentStats.values.where((e) => e.isDebarred).length)]);

      // -------------------------------------------------------------
      // SHEET 4: Audit Log
      // -------------------------------------------------------------
      final sheetAudit = excel[auditSheetName];
      sheetAudit.appendRow([
        TextCellValue('Timestamp'),
        TextCellValue('Action'),
        TextCellValue('User'),
        TextCellValue('Entity'),
        TextCellValue('Reason'),
        TextCellValue('Source'),
      ]);
      for (final a in auditLogs) {
        sheetAudit.appendRow([
          TextCellValue(a.createdAt.toIso8601String()),
          TextCellValue(a.action.label),
          TextCellValue(a.userId ?? 'System'),
          TextCellValue('${a.entityType} (${a.entityId})'),
          TextCellValue(a.reason),
          TextCellValue(a.source),
        ]);
      }

      // -------------------------------------------------------------
      // SHEET 5: Metadata
      // -------------------------------------------------------------
      final sheetMeta = excel[metaSheetName];
      sheetMeta.appendRow([TextCellValue('Property'), TextCellValue('Value')]);
      sheetMeta.appendRow([TextCellValue('System'), TextCellValue(AppConstants.appName)]);
      sheetMeta.appendRow([TextCellValue('Version'), TextCellValue(AppConstants.appVersion)]);
      sheetMeta.appendRow([TextCellValue('Generated At'), TextCellValue(DateTime.now().toIso8601String())]);
      sheetMeta.appendRow([TextCellValue('Notice'), TextCellValue('Authoritative report generated by Attendium Local Database.')]);

      // Remove default 'Sheet1' if it exists and is unused
      if (excel.tables.containsKey('Sheet1') && sheetSummary != excel['Sheet1']) {
        excel.delete('Sheet1');
      }

      final bytes = excel.encode();
      if (bytes == null) {
        return const Err(ExportFailure('Failed to encode Excel file bytes'));
      }

      return Success(Uint8List.fromList(bytes));
    } catch (e) {
      return Err(ExportFailure('Error generating Excel report: $e'));
    }
  }
}
