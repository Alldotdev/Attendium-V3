import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../../core/constants/app_colors.dart';
import '../../domain/entities/attendance_record.dart';
import '../../domain/entities/audit_log.dart';
import '../../domain/entities/classroom.dart';
import '../../domain/entities/course_session.dart';
import '../../domain/entities/student.dart';
import '../../domain/enums/attendance_classification.dart';
import '../../domain/enums/attendance_status.dart';
import '../../domain/services/attendance_calculator.dart';
import '../../infrastructure/export/excel_generator.dart';
import '../../infrastructure/export/pdf_generator.dart';
import '../providers/classroom_providers.dart';
import '../providers/database_providers.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _riskFilter = 'ALL'; // ALL, SAFE, RISK
  final TextEditingController _searchController = TextEditingController();
  bool _isExporting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _exportExcel({
    required ClassroomEntity classroom,
    required List<StudentEntity> students,
    required List<CourseSessionEntity> sessions,
    required List<AttendanceRecordEntity> records,
    required List<AuditLogEntity> auditLogs,
  }) async {
    setState(() => _isExporting = true);
    try {
      final res = ExcelGenerator.generateClassroomReport(
        classroom: classroom,
        students: students,
        sessions: sessions,
        records: records,
        auditLogs: auditLogs,
      );

      if (res.isSuccess) {
        final bytes = res.successOrNull!;
        final defaultName = '${classroom.courseCode}_${classroom.section}_Attendance.xlsx';
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Excel Attendance Workbook',
          fileName: defaultName,
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
        );

        if (savePath != null) {
          final file = File(savePath);
          await file.writeAsBytes(bytes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Excel report successfully saved to $savePath'),
                backgroundColor: AppColors.present,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to generate Excel: ${res.errorOrNull?.message}'),
              backgroundColor: AppColors.absent,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e'), backgroundColor: AppColors.absent),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportPdf({
    required ClassroomEntity classroom,
    required List<StudentEntity> students,
    required List<CourseSessionEntity> sessions,
    required List<AttendanceRecordEntity> records,
    bool directPrint = false,
  }) async {
    setState(() => _isExporting = true);
    try {
      final res = await PdfGenerator.generateClassroomPdf(
        institutionName: 'Attendium Academic System',
        classroom: classroom,
        students: students,
        sessions: sessions,
        records: records,
      );

      if (res.isSuccess) {
        final bytes = res.successOrNull!;

        if (directPrint) {
          await Printing.layoutPdf(
            onLayout: (format) => bytes,
            name: '${classroom.courseCode}_Attendance_Report',
          );
        } else {
          final defaultName = '${classroom.courseCode}_${classroom.section}_Report.pdf';
          final savePath = await FilePicker.platform.saveFile(
            dialogTitle: 'Save PDF Attendance Report',
            fileName: defaultName,
            type: FileType.custom,
            allowedExtensions: ['pdf'],
          );

          if (savePath != null) {
            final file = File(savePath);
            await file.writeAsBytes(bytes);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('PDF report successfully saved to $savePath'),
                  backgroundColor: AppColors.present,
                ),
              );
            }
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to generate PDF: ${res.errorOrNull?.message}'),
              backgroundColor: AppColors.absent,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF error: $e'), backgroundColor: AppColors.absent),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeClassroomAsync = ref.watch(activeClassroomProvider);
    final rosterAsync = ref.watch(rosterProvider);
    final sessionsAsync = ref.watch(sessionsProvider);
    final attendanceDao = ref.watch(attendanceDaoProvider);
    final auditDao = ref.watch(auditDaoProvider);

    return activeClassroomAsync.when(
      data: (classroom) {
        if (classroom == null) {
          return const Center(
            child: Text('Please select or create an active classroom first.',
                style: TextStyle(color: AppColors.textMuted)),
          );
        }

        return rosterAsync.when(
          data: (roster) {
            return sessionsAsync.when(
              data: (sessions) {
                return FutureBuilder<List<AttendanceRecordEntity>>(
                  future: attendanceDao.getAllRecordsForClassroom(classroom.id).then((r) => r.successOrNull ?? []),
                  builder: (context, recordsSnapshot) {
                    if (recordsSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final records = recordsSnapshot.data ?? [];

                    return FutureBuilder<List<AuditLogEntity>>(
                      future: auditDao.getRecentLogs(limit: 50).then((r) => r.successOrNull ?? []),
                      builder: (context, auditSnapshot) {
                        final auditLogs = auditSnapshot.data ?? [];

                        return _buildContent(
                          context,
                          classroom,
                          roster,
                          sessions,
                          records,
                          auditLogs,
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error loading sessions: $err')),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error loading roster: $err')),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error loading classroom: $err')),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ClassroomEntity classroom,
    List<StudentEntity> roster,
    List<CourseSessionEntity> sessions,
    List<AttendanceRecordEntity> records,
    List<AuditLogEntity> auditLogs,
  ) {
    // 1. Precalculate attendance stats for each student
    final recordMap = <String, Map<String, AttendanceRecordEntity>>{};
    for (final r in records) {
      recordMap.putIfAbsent(r.sessionId, () => {})[r.studentId] = r;
    }

    const policy = AttendancePolicyConfig();
    final studentStats = <String, AttendanceCalculationResult>{};

    for (final s in roster) {
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
      studentStats[s.id] = AttendanceCalculator.calculate(records: studentRecords, policy: policy);
    }

    final totalStudents = roster.length;
    final totalSessions = sessions.length;
    final avgAttendance = studentStats.isNotEmpty
        ? studentStats.values.map((e) => e.percentage).reduce((a, b) => a + b) / studentStats.length
        : 100.0;
    final safeCount = studentStats.values.where((e) => e.isSafe).length;
    final atRiskCount = studentStats.values.where((e) => e.isAtRisk).length;

    // Filter students by risk and search text
    final search = _searchController.text.toLowerCase().trim();
    final filteredStudents = roster.where((s) {
      final stats = studentStats[s.id]!;
      if (_riskFilter == 'SAFE' && !stats.isSafe) return false;
      if (_riskFilter == 'RISK' && !stats.isAtRisk) return false;
      if (search.isNotEmpty) {
        final matchRoll = s.rollNumber.toLowerCase().contains(search);
        final matchName = s.fullName.toLowerCase().contains(search);
        if (!matchRoll && !matchName) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Column(
        children: [
          // Header Bar with Export Actions
          _buildHeaderToolbar(
            context,
            classroom,
            roster,
            sessions,
            records,
            auditLogs,
          ),

          // Analytic Overview Cards
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                _buildMetricCard(
                  title: 'Average Attendance',
                  value: '${avgAttendance.toStringAsFixed(1)}%',
                  subtitle: '$totalSessions sessions held',
                  color: avgAttendance >= 75 ? AppColors.present : AppColors.absent,
                  icon: Icons.trending_up,
                ),
                const SizedBox(width: 14),
                _buildMetricCard(
                  title: 'Enrolled Students',
                  value: '$totalStudents',
                  subtitle: 'In active classroom',
                  color: AppColors.primary,
                  icon: Icons.people_outline,
                ),
                const SizedBox(width: 14),
                _buildMetricCard(
                  title: 'Safe Attendance (>= 75%)',
                  value: '$safeCount',
                  subtitle: '${totalStudents > 0 ? ((safeCount / totalStudents) * 100).toInt() : 0}% of cohort',
                  color: AppColors.present,
                  icon: Icons.check_circle_outline,
                ),
                const SizedBox(width: 14),
                _buildMetricCard(
                  title: 'Shortage Alerts (< 75%)',
                  value: '$atRiskCount',
                  subtitle: 'Action required',
                  color: AppColors.absent,
                  icon: Icons.warning_amber_rounded,
                ),
              ],
            ),
          ),

          // Filters & Search Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 280,
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by roll or name...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppColors.borderSubtle),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                _buildFilterChip('All Students ($totalStudents)', 'ALL'),
                const SizedBox(width: 8),
                _buildFilterChip('Safe ($safeCount)', 'SAFE', color: AppColors.present),
                const SizedBox(width: 8),
                _buildFilterChip('Shortage Alerts ($atRiskCount)', 'RISK', color: AppColors.absent),
                const Spacer(),
                Text(
                  'Showing ${filteredStudents.length} of $totalStudents students',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Roster Statistics Table
          Expanded(
            child: filteredStudents.isEmpty
                ? const Center(child: Text('No students match the criteria.', style: TextStyle(color: AppColors.textMuted)))
                : _buildRosterTable(filteredStudents, studentStats),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderToolbar(
    BuildContext context,
    ClassroomEntity classroom,
    List<StudentEntity> roster,
    List<CourseSessionEntity> sessions,
    List<AttendanceRecordEntity> records,
    List<AuditLogEntity> auditLogs,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.bar_chart_rounded, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${classroom.courseCode} - Reports & Analytics',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      classroom.section,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                classroom.courseName,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
          const Spacer(),
          // Print PDF button
          OutlinedButton.icon(
            onPressed: _isExporting
                ? null
                : () => _exportPdf(
                      classroom: classroom,
                      students: roster,
                      sessions: sessions,
                      records: records,
                      directPrint: true,
                    ),
            icon: const Icon(Icons.print_outlined, size: 16),
            label: const Text('Print Preview'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.borderSubtle),
            ),
          ),
          const SizedBox(width: 10),
          // Export PDF button
          OutlinedButton.icon(
            onPressed: _isExporting
                ? null
                : () => _exportPdf(
                      classroom: classroom,
                      students: roster,
                      sessions: sessions,
                      records: records,
                      directPrint: false,
                    ),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: const Text('Export PDF'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.borderSubtle),
            ),
          ),
          const SizedBox(width: 10),
          // Export Excel button
          ElevatedButton.icon(
            onPressed: _isExporting
                ? null
                : () => _exportExcel(
                      classroom: classroom,
                      students: roster,
                      sessions: sessions,
                      records: records,
                      auditLogs: auditLogs,
                    ),
            icon: _isExporting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.table_view_outlined, size: 16),
            label: const Text('Export Excel (.xlsx)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.present,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
                  const SizedBox(height: 6),
                  Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String key, {Color? color}) {
    final isSelected = _riskFilter == key;
    final activeColor = color ?? AppColors.primary;

    return InkWell(
      onTap: () => setState(() => _riskFilter = key),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.12) : AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? activeColor : AppColors.borderSubtle),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? activeColor : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildRosterTable(
    List<StudentEntity> students,
    Map<String, AttendanceCalculationResult> studentStats,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
              border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: const Row(
              children: [
                SizedBox(width: 100, child: Text('Roll Number', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                Expanded(flex: 3, child: Text('Student Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                SizedBox(width: 60, child: Text('Present', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                SizedBox(width: 60, child: Text('Absent', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                SizedBox(width: 60, child: Text('Late', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                SizedBox(width: 60, child: Text('Excused', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                SizedBox(width: 120, child: Text('Attendance %', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                SizedBox(width: 110, child: Text('Classification', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                Expanded(flex: 2, child: Text('Action / Recovery Plan', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
              ],
            ),
          ),

          // Table Rows
          Expanded(
            child: ListView.separated(
              itemCount: students.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final student = students[index];
                final stats = studentStats[student.id]!;

                Color pctColor;
                Color badgeBg;
                String classLabel;

                switch (stats.classification) {
                  case AttendanceClassification.safe:
                    pctColor = AppColors.present;
                    badgeBg = AppColors.presentBg;
                    classLabel = 'SAFE (>= 75%)';
                    break;
                  case AttendanceClassification.atRisk:
                    pctColor = AppColors.late;
                    badgeBg = AppColors.lateBg;
                    classLabel = 'AT RISK (65-74%)';
                    break;
                  case AttendanceClassification.short:
                  case AttendanceClassification.debarred:
                    pctColor = AppColors.absent;
                    badgeBg = AppColors.absentBg;
                    classLabel = stats.classification == AttendanceClassification.debarred ? 'DEBARRED (< 50%)' : 'SHORT (< 65%)';
                    break;
                }

                String recoveryText;
                if (stats.isAtRisk || stats.isShort || stats.isDebarred) {
                  recoveryText = 'Needs ${stats.classesNeededForThreshold} consecutive present sessions';
                } else {
                  recoveryText = 'Can miss up to ${stats.absencesAllowedBeforeThreshold} session(s) safely';
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(
                          student.rollNumber,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFamily: 'monospace'),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          student.fullName,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text('${stats.presentCount}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.present, fontWeight: FontWeight.w600)),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text('${stats.absentCount}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.absent, fontWeight: FontWeight.w600)),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text('${stats.lateCount}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.late, fontWeight: FontWeight.w600)),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text('${stats.excusedCount}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.excused, fontWeight: FontWeight.w600)),
                      ),
                      SizedBox(
                        width: 120,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: pctColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${stats.percentage.toStringAsFixed(1)}%',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: pctColor),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              classLabel,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: pctColor),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          recoveryText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: stats.isAtRisk ? AppColors.absent : AppColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
