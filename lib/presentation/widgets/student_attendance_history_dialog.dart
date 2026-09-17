import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../domain/entities/student.dart';
import '../../domain/enums/attendance_status.dart';
import '../providers/classroom_providers.dart';
import '../providers/database_providers.dart';

/// Displays a student's attendance history across all sessions in a classroom.
class StudentAttendanceHistoryDialog extends ConsumerStatefulWidget {
  final StudentEntity student;
  final String classroomId;

  const StudentAttendanceHistoryDialog({
    super.key,
    required this.student,
    required this.classroomId,
  });

  static Future<void> show(
    BuildContext context, {
    required StudentEntity student,
    required String classroomId,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => StudentAttendanceHistoryDialog(
        student: student,
        classroomId: classroomId,
      ),
    );
  }

  @override
  ConsumerState<StudentAttendanceHistoryDialog> createState() =>
      _StudentAttendanceHistoryDialogState();
}

class _StudentAttendanceHistoryDialogState
    extends ConsumerState<StudentAttendanceHistoryDialog> {
  Map<String, AttendanceStatus>? _statusMap;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final attendanceDao = ref.read(attendanceDaoProvider);
      final result = await attendanceDao.getRecordsForStudent(
        widget.student.id,
        widget.classroomId,
      );
      if (result.isSuccess) {
        final map = <String, AttendanceStatus>{};
        for (final r in result.successOrNull ?? []) {
          map[r.sessionId] = r.status;
        }
        setState(() {
          _statusMap = map;
          _loading = false;
        });
      } else {
        setState(() {
          _error = result.errorOrNull?.message ?? 'Failed to load history';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(sessionsProvider);

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 720,
        height: 620,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.bar_chart_rounded,
                        color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.student.fullName,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary),
                        ),
                        Text(
                          'Roll: ${widget.student.rollNumber}  •  Attendance History',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              style: const TextStyle(color: AppColors.absent)))
                      : sessionsAsync.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Center(child: Text('Error: $e')),
                          data: (sessions) {
                            if (sessions.isEmpty) {
                              return const Center(
                                child: Text(
                                  'No sessions recorded for this classroom yet.',
                                  style: TextStyle(
                                      fontSize: 13, color: AppColors.textMuted),
                                ),
                              );
                            }

                            final sm = _statusMap ?? {};
                            final presentC = sessions
                                .where((s) => sm[s.id] == AttendanceStatus.present)
                                .length;
                            final lateC = sessions
                                .where((s) => sm[s.id] == AttendanceStatus.late)
                                .length;
                            final excusedC = sessions
                                .where((s) => sm[s.id] == AttendanceStatus.excused)
                                .length;
                            final absentC = sessions
                                .where((s) => sm[s.id] == AttendanceStatus.absent)
                                .length;
                            final unmarkedC = sessions
                                .where((s) =>
                                    sm[s.id] == null ||
                                    sm[s.id] == AttendanceStatus.unmarked)
                                .length;
                            final marked = sessions.length - unmarkedC;
                            final attended = presentC + lateC + excusedC;
                            final pct = marked > 0
                                ? (attended / marked * 100).toStringAsFixed(1)
                                : '—';

                            return Column(
                              children: [
                                // Summary bar
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 10),
                                  color: AppColors.surfaceSubtle,
                                  child: Row(
                                    children: [
                                      _chip('Sessions', sessions.length.toString(),
                                          AppColors.textPrimary, AppColors.surfaceMuted),
                                      const SizedBox(width: 6),
                                      _chip('Present', presentC.toString(),
                                          AppColors.presentDark, AppColors.presentLight),
                                      const SizedBox(width: 6),
                                      _chip('Late', lateC.toString(),
                                          AppColors.lateDark, AppColors.lateLight),
                                      const SizedBox(width: 6),
                                      _chip('Excused', excusedC.toString(),
                                          AppColors.excusedDark, AppColors.excusedLight),
                                      const SizedBox(width: 6),
                                      _chip('Absent', absentC.toString(),
                                          AppColors.absentDark, AppColors.absentLight),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary,
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          'Attendance: $pct%',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Table header
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 8),
                                  decoration: const BoxDecoration(
                                    border: Border(
                                        bottom: BorderSide(
                                            color: AppColors.borderSubtle)),
                                  ),
                                  child: const Row(
                                    children: [
                                      SizedBox(
                                          width: 40,
                                          child: Text('#',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.textMuted))),
                                      SizedBox(
                                          width: 110,
                                          child: Text('Date',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.textMuted))),
                                      Expanded(
                                          child: Text('Topic',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.textMuted))),
                                      SizedBox(
                                          width: 80,
                                          child: Text('Type',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.textMuted))),
                                      SizedBox(
                                          width: 90,
                                          child: Text('Status',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.textMuted))),
                                    ],
                                  ),
                                ),

                                // Rows
                                Expanded(
                                  child: ListView.separated(
                                    itemCount: sessions.length,
                                    separatorBuilder: (_, _) => const Divider(
                                        height: 1, color: AppColors.borderSubtle),
                                    itemBuilder: (ctx, idx) {
                                      final s = sessions[idx];
                                      final status =
                                          sm[s.id] ?? AttendanceStatus.unmarked;
                                      final isMissed =
                                          status == AttendanceStatus.absent;
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 20, vertical: 10),
                                        color: isMissed
                                            ? AppColors.absentLight
                                                .withValues(alpha: 0.25)
                                            : (idx.isEven
                                                ? AppColors.surface
                                                : AppColors.surfaceSubtle
                                                    .withValues(alpha: 0.4)),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 40,
                                              child: Text('${idx + 1}',
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      color: AppColors.textMuted)),
                                            ),
                                            SizedBox(
                                              width: 110,
                                              child: Text(
                                                s.sessionDate,
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                s.topic ?? s.sessionType.label,
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: AppColors.textSecondary),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            SizedBox(
                                              width: 80,
                                              child: Text(
                                                s.sessionType.label,
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: AppColors.textMuted),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 90,
                                              child: _statusBadge(status),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
            ),

            // Footer
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                border:
                    Border(top: BorderSide(color: AppColors.borderSubtle)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$label: ',
              style: TextStyle(
                  fontSize: 11, color: fg.withValues(alpha: 0.75))),
          Text(value,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ]),
      );

  Widget _statusBadge(AttendanceStatus s) {
    final (bg, fg) = switch (s) {
      AttendanceStatus.present => (AppColors.presentLight, AppColors.presentDark),
      AttendanceStatus.absent => (AppColors.absentLight, AppColors.absentDark),
      AttendanceStatus.late => (AppColors.lateLight, AppColors.lateDark),
      AttendanceStatus.excused => (AppColors.excusedLight, AppColors.excusedDark),
      AttendanceStatus.unmarked => (AppColors.surfaceMuted, AppColors.textDisabled),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(s.label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}
