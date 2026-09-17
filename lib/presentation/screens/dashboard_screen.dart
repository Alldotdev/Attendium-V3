import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../domain/enums/attendance_status.dart';
import '../../domain/services/attendance_calculator.dart';
import '../providers/classroom_providers.dart';
import '../providers/database_providers.dart';
import '../shell/app_shell.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeClassroomAsync = ref.watch(activeClassroomProvider);
    final rosterAsync = ref.watch(rosterProvider);
    final sessionsAsync = ref.watch(sessionsProvider);
    final policyAsync = ref.watch(activePolicyProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Screen Title Bar & Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Attendance Command Center',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      activeClassroomAsync.when(
                        data: (c) => Text(
                          c != null
                              ? '${c.courseCode} (${c.section}) — ${c.courseName} • Instructor: ${c.instructorName}'
                              : 'Select or create a classroom to begin taking attendance',
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                        loading: () => const Text('Loading active classroom...'),
                        error: (_, _) => const Text('Error loading classroom'),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        ref.read(selectedNavigationIndexProvider.notifier).state = 3; // Import
                      },
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: const Text('Ingest Document'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        ref.read(selectedNavigationIndexProvider.notifier).state = 2; // Grid
                      },
                      icon: const Icon(Icons.add_task, size: 16),
                      label: const Text('Take Attendance'),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 2. High-Level Metrics Cards
            rosterAsync.when(
              data: (students) {
                return sessionsAsync.when(
                  data: (sessions) {
                    final policyEntity = policyAsync.value;
                    final AttendancePolicyConfig policy = policyEntity != null
                        ? AttendancePolicyConfig(
                            minimumPercentage: policyEntity.minimumPercentage,
                            lateWeight: policyEntity.lateWeight,
                            excusedCounted: policyEntity.excusedCounted,
                            debarThreshold: policyEntity.debarThreshold,
                          )
                        : const AttendancePolicyConfig();

                    return FutureBuilder(
                      future: ref.read(attendanceDaoProvider).getAllRecordsForClassroom(
                        ref.read(selectedClassroomIdProvider) ?? '',
                      ),
                      builder: (context, snapshot) {
                        final records = snapshot.data?.successOrNull ?? [];
                        final recordMap = <String, Map<String, dynamic>>{};
                        for (final r in records) {
                          recordMap.putIfAbsent(r.sessionId, () => {})[r.studentId] = r;
                        }

                        // Calculate overall stats
                        double sumPct = 0;
                        int atRiskCount = 0;
                        int shortCount = 0;

                        for (final s in students) {
                          final recs = <SessionRecordInput>[];
                          for (final sess in sessions) {
                            final r = recordMap[sess.id]?[s.id];
                            recs.add(SessionRecordInput(
                              sessionId: sess.id,
                              status: r?.status ?? AttendanceStatus.unmarked,
                              sessionCreditWeight: sess.creditWeight,
                            ));
                          }
                          final calc = AttendanceCalculator.calculate(records: recs, policy: policy);
                          sumPct += calc.percentage;
                          if (calc.isAtRisk) atRiskCount++;
                          if (calc.isShort || calc.isDebarred) shortCount++;
                        }

                        final avgPct = (students.isNotEmpty && sessions.isNotEmpty) ? sumPct / students.length : 0.0;

                        return Column(
                          children: [
                            Row(
                              children: [
                                _metricCard(
                                  title: 'Enrolled Students',
                                  value: '${students.length}',
                                  icon: Icons.people_outline,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 16),
                                _metricCard(
                                  title: 'Sessions Held',
                                  value: '${sessions.length}',
                                  icon: Icons.event_note_outlined,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 16),
                                _metricCard(
                                  title: 'Class Average',
                                  value: (students.isNotEmpty && sessions.isNotEmpty) ? '${avgPct.toStringAsFixed(1)}%' : '—',
                                  icon: Icons.analytics_outlined,
                                  color: (students.isNotEmpty && sessions.isNotEmpty)
                                      ? (avgPct >= policy.minimumPercentage ? AppColors.present : AppColors.late)
                                      : AppColors.textDisabled,
                                ),
                                const SizedBox(width: 16),
                                _metricCard(
                                  title: 'Short / Debarred',
                                  value: '$shortCount',
                                  subtitle: '$atRiskCount at risk',
                                  icon: Icons.warning_amber_rounded,
                                  color: shortCount > 0 ? AppColors.absent : AppColors.present,
                                ),
                              ],
                            ),

                            const SizedBox(height: 28),

                            // 3. Lower Grid: Sessions & At-Risk Students
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left column: Recent Sessions
                                Expanded(
                                  flex: 5,
                                  child: _buildRecentSessionsCard(sessions, ref),
                                ),
                                const SizedBox(width: 20),
                                // Right column: At Risk Alerts
                                Expanded(
                                  flex: 6,
                                  child: _buildAtRiskAlertsCard(students, sessions, recordMap, policy),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Error loading sessions: $e'),
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error loading roster: $e'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    String? subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderSubtle),
          boxShadow: AppColors.shadowSm,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSessionsCard(List<dynamic> sessions, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Class Sessions',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              Text(
                '${sessions.length} recorded',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text('No sessions recorded yet. Click "Take Attendance" to create one.',
                    style: TextStyle(fontSize: 12, color: AppColors.textDisabled)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sessions.take(6).length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = sessions[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Center(
                      child: Text(
                        s.sessionDate.split('-').last,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                  ),
                  title: Text(
                    s.topic ?? 'Lecture Session',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${s.sessionDate} • ${s.sessionType.label}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                  trailing: TextButton(
                    onPressed: () {
                      ref.read(activeSessionIdProvider.notifier).state = s.id;
                      ref.read(selectedNavigationIndexProvider.notifier).state = 2; // Go to grid
                    },
                    child: const Text('Open Grid', style: TextStyle(fontSize: 12)),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAtRiskAlertsCard(
    List<dynamic> students,
    List<dynamic> sessions,
    Map<String, Map<String, dynamic>> recordMap,
    AttendancePolicyConfig policy,
  ) {
    final alertStudents = <Map<String, dynamic>>[];

    for (final s in students) {
      final recs = <SessionRecordInput>[];
      for (final sess in sessions) {
        final r = recordMap[sess.id]?[s.id];
        recs.add(SessionRecordInput(
          sessionId: sess.id,
          status: r?.status ?? AttendanceStatus.unmarked,
          sessionCreditWeight: sess.creditWeight,
        ));
      }
      final calc = AttendanceCalculator.calculate(records: recs, policy: policy);
      if (!calc.isSafe) {
        alertStudents.add({
          'student': s,
          'calc': calc,
        });
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Shortage & At-Risk Alerts',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: alertStudents.isEmpty ? AppColors.presentLight : AppColors.absentLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${alertStudents.length} flags',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: alertStudents.isEmpty ? AppColors.presentDark : AppColors.absentDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (alertStudents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text(
                  students.isEmpty
                      ? 'No enrolled students to evaluate yet.'
                      : 'All students currently meet or exceed attendance requirements.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textDisabled),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: alertStudents.take(6).length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final item = alertStudents[i];
                final s = item['student'];
                final AttendanceCalculationResult calc = item['calc'];

                final Color statusColor = calc.isDebarred
                    ? AppColors.absent
                    : calc.isShort
                        ? AppColors.absent
                        : AppColors.late;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${calc.percentage.toStringAsFixed(1)}%',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${s.rollNumber} • ${s.fullName}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              calc.classesNeededForThreshold > 0
                                  ? 'Needs ${calc.classesNeededForThreshold} consecutive classes to reach ${policy.minimumPercentage}%'
                                  : calc.classification.label,
                              style: TextStyle(fontSize: 11, color: statusColor),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSubtle,
                          border: Border.all(color: AppColors.borderSubtle),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          calc.classification.label,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
