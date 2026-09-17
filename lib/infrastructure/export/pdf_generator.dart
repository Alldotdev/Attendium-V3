import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/errors/failures.dart';
import '../../core/result/result.dart';
import '../../domain/entities/attendance_record.dart';
import '../../domain/entities/classroom.dart';
import '../../domain/entities/course_session.dart';
import '../../domain/entities/student.dart';
import '../../domain/enums/attendance_status.dart';
import '../../domain/services/attendance_calculator.dart';

/// PDF attendance report generator producing clean, print-ready documents (Section 34).
class PdfGenerator {
  const PdfGenerator._();

  static Future<Result<Uint8List, Failure>> generateClassroomPdf({
    required String institutionName,
    required ClassroomEntity classroom,
    required List<StudentEntity> students,
    required List<CourseSessionEntity> sessions,
    required List<AttendanceRecordEntity> records,
    AttendancePolicyConfig policy = const AttendancePolicyConfig(),
  }) async {
    try {
      final doc = pw.Document();

      // Build records index
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

      final avgPct = students.isNotEmpty
          ? studentStats.values.map((e) => e.percentage).reduce((a, b) => a + b) / students.length
          : 100.0;

      final safeCount = studentStats.values.where((e) => e.isSafe).length;
      final atRiskCount = studentStats.values.where((e) => e.isAtRisk).length;
      final shortCount = studentStats.values.where((e) => e.isShort).length;
      final debarredCount = studentStats.values.where((e) => e.isDebarred).length;

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          institutionName.toUpperCase(),
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey900,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          '${classroom.courseCode} (${classroom.section}) - ${classroom.courseName}',
                          style: pw.TextStyle(
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.purple800,
                          ),
                        ),
                        pw.Text(
                          'Instructor: ${classroom.instructorName} | Total Sessions: ${sessions.length}',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'ATTENDANCE REPORT',
                          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                        ),
                        pw.Text(
                          DateTime.now().toString().split('.')[0],
                          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.Divider(thickness: 1, color: PdfColors.grey300),
                pw.SizedBox(height: 8),
              ],
            );
          },
          footer: (pw.Context context) {
            return pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Attendium Attendance Management System | Official Record',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
              ],
            );
          },
          build: (pw.Context context) {
            return [
              // Summary Metrics Cards
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    _buildMetric('Class Average', '${avgPct.toStringAsFixed(1)}%', PdfColors.blue800),
                    _buildMetric('Safe (>=${policy.minimumPercentage}%)', '$safeCount', PdfColors.green800),
                    _buildMetric('At Risk', '$atRiskCount', PdfColors.amber800),
                    _buildMetric('Short / Debarred', '${shortCount + debarredCount}', PdfColors.red800),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Student Roster Table
              pw.TableHelper.fromTextArray(
                border: const pw.TableBorder(
                  bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                  horizontalInside: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                ),
                headerStyle: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey900,
                ),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                cellStyle: const pw.TextStyle(fontSize: 8.5),
                cellAlignment: pw.Alignment.centerLeft,
                columnWidths: {
                  0: const pw.FlexColumnWidth(2.0),
                  1: const pw.FlexColumnWidth(4.0),
                  2: const pw.FlexColumnWidth(1.2),
                  3: const pw.FlexColumnWidth(1.2),
                  4: const pw.FlexColumnWidth(1.2),
                  5: const pw.FlexColumnWidth(1.8),
                  6: const pw.FlexColumnWidth(2.0),
                },
                headers: ['Roll No', 'Student Name', 'Present', 'Late', 'Absent', 'Percentage', 'Status'],
                data: students.map((s) {
                  final calc = studentStats[s.id]!;
                  return [
                    s.rollNumber,
                    s.fullName,
                    '${calc.presentCount}',
                    '${calc.lateCount}',
                    '${calc.absentCount}',
                    '${calc.percentage.toStringAsFixed(1)}%',
                    calc.classification.label,
                  ];
                }).toList(),
              ),
            ];
          },
        ),
      );

      final pdfBytes = await doc.save();
      return Success(pdfBytes);
    } catch (e) {
      return Err(ExportFailure('Failed to generate PDF: $e'));
    }
  }

  static pw.Widget _buildMetric(String label, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    );
  }
}
