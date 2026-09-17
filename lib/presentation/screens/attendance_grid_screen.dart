import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../domain/entities/audit_log.dart';
import '../../domain/entities/course_session.dart';
import '../../domain/entities/student.dart';
import '../../domain/enums/attendance_status.dart';
import '../../domain/enums/audit_action.dart';
import '../../domain/enums/session_type.dart';
import '../providers/attendance_grid_provider.dart';
import '../providers/classroom_providers.dart';
import '../providers/database_providers.dart';
import '../widgets/scan_attendance_dialog.dart';

class AttendanceGridScreen extends ConsumerStatefulWidget {
  const AttendanceGridScreen({super.key});

  @override
  ConsumerState<AttendanceGridScreen> createState() => _AttendanceGridScreenState();
}

class _AttendanceGridScreenState extends ConsumerState<AttendanceGridScreen> {
  final FocusNode _keyboardFocusNode = FocusNode();
  String? _loadedSessionId;

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event, List<StudentEntity> roster) {
    if (event is! KeyDownEvent) return;

    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    // Undo / Redo
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (isShift) {
        ref.read(attendanceGridProvider.notifier).redo();
      } else {
        ref.read(attendanceGridProvider.notifier).undo();
      }
      return;
    }

    // Save
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyS) {
      final sessId = ref.read(activeSessionIdProvider);
      if (sessId != null) {
        ref.read(attendanceGridProvider.notifier).commitAttendance(sessId);
      }
      return;
    }

    // Navigation
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      ref.read(attendanceGridProvider.notifier).moveFocusUp();
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      ref.read(attendanceGridProvider.notifier).moveFocusDown(roster.length);
      return;
    }

    // Status toggles
    final char = event.character?.toUpperCase();
    if (char == 'P') {
      ref.read(attendanceGridProvider.notifier).applyStatus(AttendanceStatus.present, roster);
    } else if (char == 'A') {
      ref.read(attendanceGridProvider.notifier).applyStatus(AttendanceStatus.absent, roster);
    } else if (char == 'L') {
      ref.read(attendanceGridProvider.notifier).applyStatus(AttendanceStatus.late, roster);
    } else if (char == 'E') {
      ref.read(attendanceGridProvider.notifier).applyStatus(AttendanceStatus.excused, roster);
    } else if (char == 'U') {
      ref.read(attendanceGridProvider.notifier).applyStatus(AttendanceStatus.unmarked, roster);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rosterAsync = ref.watch(rosterProvider);
    final sessionsAsync = ref.watch(sessionsProvider);
    final activeSessionId = ref.watch(activeSessionIdProvider);
    final gridState = ref.watch(attendanceGridProvider);

    return rosterAsync.when(
      data: (roster) {
        return sessionsAsync.when(
          data: (sessions) {
            // Auto-select or create session if none selected
            if (activeSessionId == null && sessions.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ref.read(activeSessionIdProvider.notifier).state = sessions.first.id;
              });
            }

            // Initialize grid if session changed
            if (activeSessionId != null && activeSessionId != _loadedSessionId) {
              _loadedSessionId = activeSessionId;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ref.read(attendanceGridProvider.notifier).initializeForSession(
                  sessionId: activeSessionId,
                  roster: roster,
                );
              });
            }

            // Count summary status
            int presentCount = 0;
            int absentCount = 0;
            int lateCount = 0;
            int excusedCount = 0;
            int unmarkedCount = 0;

            gridState.statuses.forEach((_, status) {
              switch (status) {
                case AttendanceStatus.present:
                  presentCount++;
                  break;
                case AttendanceStatus.absent:
                  absentCount++;
                  break;
                case AttendanceStatus.late:
                  lateCount++;
                  break;
                case AttendanceStatus.excused:
                  excusedCount++;
                  break;
                case AttendanceStatus.unmarked:
                  unmarkedCount++;
                  break;
              }
            });

            return KeyboardListener(
              focusNode: _keyboardFocusNode,
              autofocus: true,
              onKeyEvent: (evt) => _handleKeyEvent(evt, roster),
              child: Scaffold(
                backgroundColor: AppColors.background,
                body: Column(
                  children: [
                    // 1. Top Session Toolbar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
                      ),
                      child: Row(
                        children: [
                          // Session selector
                          if (sessions.isNotEmpty) ...[
                            Container(
                              constraints: const BoxConstraints(maxWidth: 240),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceSubtle,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.borderSubtle),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: (activeSessionId != null && sessions.any((s) => s.id == activeSessionId))
                                      ? activeSessionId
                                      : (sessions.isNotEmpty ? sessions.first.id : null),
                                  items: sessions.map((s) {
                                    return DropdownMenuItem(
                                      value: s.id,
                                      child: Text(
                                        '${s.sessionDate} • ${s.topic ?? s.sessionType.label}',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      ref.read(activeSessionIdProvider.notifier).state = val;
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (activeSessionId != null && sessions.any((s) => s.id == activeSessionId))
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textSecondary),
                                tooltip: 'Session Options',
                                onSelected: (action) {
                                  final activeSession = sessions.firstWhere((s) => s.id == activeSessionId);
                                  if (action == 'edit') {
                                    _showEditSessionDialog(context, activeSession);
                                  } else if (action == 'delete') {
                                    _confirmDeleteSession(context, activeSession);
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(children: [Icon(Icons.edit_outlined, size: 16), SizedBox(width: 8), Text('Edit Session')]),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(children: [Icon(Icons.delete_outline, size: 16, color: AppColors.absent), SizedBox(width: 8), Text('Delete Session', style: TextStyle(color: AppColors.absent))]),
                                  ),
                                ],
                              ),
                          ],
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => _showCreateSessionDialog(context),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('New Session'),
                          ),
                          const Spacer(),

                          // View Uploaded Data Button
                          if (activeSessionId != null) ...[
                            OutlinedButton.icon(
                              onPressed: () => _showUploadedDataDialog(context, activeSessionId),
                              icon: const Icon(Icons.history_edu_rounded, size: 16),
                              label: const Text('View Uploaded Data'),
                            ),
                            const SizedBox(width: 8),
                          ],

                          // Scan / Auto-Mark Attendance Button
                          ElevatedButton.icon(
                            onPressed: activeSessionId != null
                                ? () async {
                                    final appliedCount = await ScanAttendanceDialog.show(
                                      context,
                                      roster: roster,
                                      sessionId: activeSessionId,
                                    );
                                    if (context.mounted && appliedCount != null && appliedCount > 0) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Auto-marked attendance for $appliedCount students from scan.'),
                                          backgroundColor: AppColors.presentDark,
                                          duration: const Duration(seconds: 3),
                                        ),
                                      );
                                    }
                                  }
                                : null,
                            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                            label: const Text('Scan / Auto-Mark'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Quick Batch Buttons
                          OutlinedButton(
                            onPressed: () => ref.read(attendanceGridProvider.notifier).markAll(AttendanceStatus.present, roster),
                            child: const Text('All Present (P)'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () => ref.read(attendanceGridProvider.notifier).markAll(AttendanceStatus.absent, roster),
                            child: const Text('All Absent (A)'),
                          ),
                          const SizedBox(width: 12),

                          // Undo / Redo buttons
                          IconButton(
                            icon: const Icon(Icons.undo, size: 18),
                            onPressed: gridState.canUndo ? () => ref.read(attendanceGridProvider.notifier).undo() : null,
                            tooltip: 'Undo (Ctrl+Z)',
                          ),
                          IconButton(
                            icon: const Icon(Icons.redo, size: 18),
                            onPressed: gridState.canRedo ? () => ref.read(attendanceGridProvider.notifier).redo() : null,
                            tooltip: 'Redo (Ctrl+Shift+Z)',
                          ),
                          const SizedBox(width: 12),

                          // Save Changes Button
                          ElevatedButton.icon(
                            onPressed: activeSessionId != null
                                ? () async {
                                    final messenger = ScaffoldMessenger.of(context);
                                    final success = await ref
                                        .read(attendanceGridProvider.notifier)
                                        .commitAttendance(activeSessionId);
                                    if (mounted && success) {
                                      ref.read(auditDaoProvider).logActionSync(AuditLogEntity(
                                        id: 'aud_${DateTime.now().millisecondsSinceEpoch}',
                                        entityType: 'attendance_session',
                                        entityId: activeSessionId,
                                        action: AuditAction.update,
                                        reason: 'Attendance register saved for session',
                                        source: 'manual_grid',
                                        createdAt: DateTime.now(),
                                      ));
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text('Attendance saved transactionally to local SQLite.'),
                                          backgroundColor: AppColors.presentDark,
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  }
                                : null,
                            icon: gridState.isSaving
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.save, size: 16),
                            label: Text(gridState.hasUnsavedChanges ? 'Save Changes *' : 'Saved to DB'),
                          ),
                        ],
                      ),
                    ),

                    // 2. Status Counter & Shortcut Cheat Sheet Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                      color: AppColors.surfaceSubtle,
                      child: Row(
                        children: [
                          _statusChip('Present', presentCount, AppColors.present, AppColors.presentLight),
                          const SizedBox(width: 8),
                          _statusChip('Late', lateCount, AppColors.late, AppColors.lateLight),
                          const SizedBox(width: 8),
                          _statusChip('Excused', excusedCount, AppColors.excused, AppColors.excusedLight),
                          const SizedBox(width: 8),
                          _statusChip('Absent', absentCount, AppColors.absent, AppColors.absentLight),
                          const SizedBox(width: 8),
                          _statusChip('Unmarked', unmarkedCount, AppColors.unmarked, AppColors.surfaceMuted),
                          const Spacer(),
                          const Text(
                            'Shortcuts: [P] Present  [A] Absent  [L] Late  [E] Excused  [U] Unmarked  [↑/↓] Navigate  [Ctrl+S] Save',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),

                    // 3. High-Performance Interactive Table
                    Expanded(
                      child: roster.isEmpty
                          ? const Center(child: Text('No students in roster. Add students in Classrooms view.'))
                          : ListView.builder(
                              itemCount: roster.length,
                              itemBuilder: (context, i) {
                                final s = roster[i];
                                final status = gridState.statuses[s.id] ?? AttendanceStatus.unmarked;
                                final isFocused = i == gridState.focusedIndex;
                                final isSelected = gridState.selectedStudentIds.contains(s.id);

                                return GestureDetector(
                                  onTap: () {
                                    ref.read(attendanceGridProvider.notifier).setFocusIndex(i, roster.length);
                                    _keyboardFocusNode.requestFocus();
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isFocused
                                          ? AppColors.primaryLight.withValues(alpha: 0.5)
                                          : (i % 2 == 0 ? AppColors.surface : AppColors.surfaceSubtle),
                                      border: Border(
                                        left: BorderSide(
                                          color: isFocused ? AppColors.primary : Colors.transparent,
                                          width: 4,
                                        ),
                                        bottom: const BorderSide(color: AppColors.borderSubtle),
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                                    child: Row(
                                      children: [
                                        // Checkbox for multi-select
                                        Checkbox(
                                          value: isSelected,
                                          onChanged: (_) {
                                            ref.read(attendanceGridProvider.notifier).toggleStudentSelection(s.id);
                                          },
                                        ),
                                        const SizedBox(width: 12),
                                        // Roll Number
                                        SizedBox(
                                          width: 120,
                                          child: Text(
                                            s.rollNumber,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                        ),
                                        // Student Full Name
                                        Expanded(
                                          child: Text(
                                            s.fullName,
                                            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                                          ),
                                        ),

                                        // Status Pill Indicator
                                        Container(
                                          width: 100,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: _statusBgColor(status),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: _statusColor(status).withValues(alpha: 0.3)),
                                          ),
                                          child: Center(
                                            child: Text(
                                              status.label,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: _statusColor(status),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),

                                        // Quick Key Buttons (P, A, L, E, U)
                                        _miniStatusButton('P', AttendanceStatus.present, status, () {
                                          ref.read(attendanceGridProvider.notifier).setFocusIndex(i, roster.length);
                                          ref.read(attendanceGridProvider.notifier).applyStatus(AttendanceStatus.present, roster);
                                        }),
                                        const SizedBox(width: 4),
                                        _miniStatusButton('A', AttendanceStatus.absent, status, () {
                                          ref.read(attendanceGridProvider.notifier).setFocusIndex(i, roster.length);
                                          ref.read(attendanceGridProvider.notifier).applyStatus(AttendanceStatus.absent, roster);
                                        }),
                                        const SizedBox(width: 4),
                                        _miniStatusButton('L', AttendanceStatus.late, status, () {
                                          ref.read(attendanceGridProvider.notifier).setFocusIndex(i, roster.length);
                                          ref.read(attendanceGridProvider.notifier).applyStatus(AttendanceStatus.late, roster);
                                        }),
                                        const SizedBox(width: 4),
                                        _miniStatusButton('E', AttendanceStatus.excused, status, () {
                                          ref.read(attendanceGridProvider.notifier).setFocusIndex(i, roster.length);
                                          ref.read(attendanceGridProvider.notifier).applyStatus(AttendanceStatus.excused, roster);
                                        }),
                                        const SizedBox(width: 4),
                                        _miniStatusButton('U', AttendanceStatus.unmarked, status, () {
                                          ref.read(attendanceGridProvider.notifier).setFocusIndex(i, roster.length);
                                          ref.read(attendanceGridProvider.notifier).applyStatus(AttendanceStatus.unmarked, roster);
                                        }),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error loading sessions: $e')),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading roster: $e')),
    );
  }

  Widget _statusChip(String label, int count, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            '$label: $count',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  Widget _miniStatusButton(String code, AttendanceStatus target, AttendanceStatus current, VoidCallback onTap) {
    final isSelected = target == current;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: isSelected ? _statusColor(target) : AppColors.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? _statusColor(target) : AppColors.borderMedium,
          ),
        ),
        child: Center(
          child: Text(
            code,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Color _statusColor(AttendanceStatus s) {
    switch (s) {
      case AttendanceStatus.present:
        return AppColors.present;
      case AttendanceStatus.absent:
        return AppColors.absent;
      case AttendanceStatus.late:
        return AppColors.late;
      case AttendanceStatus.excused:
        return AppColors.excused;
      case AttendanceStatus.unmarked:
        return AppColors.unmarked;
    }
  }

  Color _statusBgColor(AttendanceStatus s) {
    switch (s) {
      case AttendanceStatus.present:
        return AppColors.presentLight;
      case AttendanceStatus.absent:
        return AppColors.absentLight;
      case AttendanceStatus.late:
        return AppColors.lateLight;
      case AttendanceStatus.excused:
        return AppColors.excusedLight;
      case AttendanceStatus.unmarked:
        return AppColors.surfaceMuted;
    }
  }

  void _showCreateSessionDialog(BuildContext context) {
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final dateCtrl = TextEditingController(text: dateStr);
    final topicCtrl = TextEditingController(text: 'Lecture');
    SessionType selectedType = SessionType.lecture;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Course Session'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: dateCtrl,
                decoration: const InputDecoration(labelText: 'Session Date (YYYY-MM-DD)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: topicCtrl,
                decoration: const InputDecoration(labelText: 'Topic / Subject'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<SessionType>(
                initialValue: selectedType,
                decoration: const InputDecoration(labelText: 'Session Type'),
                items: SessionType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label))).toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedType = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final classroomId = ref.read(selectedClassroomIdProvider);
                if (classroomId == null) return;
                final sessId = 'sess_${DateTime.now().millisecondsSinceEpoch}';
                final newSess = CourseSessionEntity(
                  id: sessId,
                  classroomId: classroomId,
                  sessionDate: dateCtrl.text.trim(),
                  topic: topicCtrl.text.trim(),
                  sessionType: selectedType,
                  creditWeight: selectedType.defaultCreditWeight,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );
                await ref.read(sessionDaoProvider).createSession(newSess);
                ref.read(auditDaoProvider).logActionSync(AuditLogEntity(
                  id: 'aud_${DateTime.now().millisecondsSinceEpoch}',
                  entityType: 'session',
                  entityId: sessId,
                  action: AuditAction.create,
                  reason: 'Session created: ${newSess.sessionDate} (${newSess.topic ?? newSess.sessionType.label})',
                  source: 'teacher_ui',
                  createdAt: DateTime.now(),
                ));
                ref.invalidate(sessionsProvider);
                ref.read(activeSessionIdProvider.notifier).state = sessId;
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Create Session'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUploadedDataDialog(BuildContext context, String sessionId) async {
    final auditDao = ref.read(auditDaoProvider);
    final res = await auditDao.getLogsForEntity('session_scan', sessionId);
    final logs = res.successOrNull ?? [];

    if (!context.mounted) return;

    if (logs.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Uploaded Attendance Data'),
            ],
          ),
          content: const Text(
            'No scanned data or uploaded document has been recorded for this session yet.\n\n'
            'Use the "Scan / Auto-Mark" button to scan a paper sheet, screenshot, or document.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        int selectedLogIdx = 0;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final log = logs[selectedLogIdx];
            Map<String, dynamic> data = {};
            try {
              if (log.afterJson != null) {
                data = jsonDecode(log.afterJson!) as Map<String, dynamic>;
              }
            } catch (_) {}

            final fileName = data['fileName'] ?? 'Unknown Source';
            final appliedCount = data['appliedCount'] ?? 0;
            final entries = (data['entries'] as List<dynamic>?) ?? [];

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.history_edu_rounded, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Uploaded Attendance Source Data', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        Text('Source: $fileName • ${log.createdAt.toLocal().toString().split('.')[0]}',
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  if (logs.length > 1) ...[
                    const Text('Scan version: ', style: TextStyle(fontSize: 12)),
                    DropdownButton<int>(
                      value: selectedLogIdx,
                      items: List.generate(logs.length, (i) => DropdownMenuItem(value: i, child: Text('#${logs.length - i}'))),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedLogIdx = val);
                      },
                    ),
                  ],
                ],
              ),
              content: SizedBox(
                width: 650,
                height: 420,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: Row(
                        children: [
                          Text('Records Applied: $appliedCount', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text('Total Extracted Entries: ${entries.length}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: entries.isEmpty
                          ? const Center(child: Text('No entry details available.'))
                          : Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.borderSubtle),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: ListView.separated(
                                itemCount: entries.length,
                                separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.borderSubtle),
                                itemBuilder: (ctx, idx) {
                                  final e = entries[idx] as Map<String, dynamic>;
                                  final input = e['input'] ?? '';
                                  final roll = e['roll'] ?? '';
                                  final name = e['name'] ?? '';
                                  final status = e['status'] ?? 'Present';
                                  final matched = e['matched'] == true;

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 130,
                                          child: Text(input.toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                        ),
                                        const Icon(Icons.arrow_forward, size: 12, color: AppColors.textMuted),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            matched ? '$name ($roll)' : 'Not matched in roster',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: matched ? AppColors.textPrimary : AppColors.absent,
                                              fontStyle: matched ? FontStyle.normal : FontStyle.italic,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryLight,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            status.toString(),
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditSessionDialog(BuildContext context, CourseSessionEntity s) {
    final dateCtrl = TextEditingController(text: s.sessionDate);
    final topicCtrl = TextEditingController(text: s.topic ?? '');
    SessionType selectedType = s.sessionType;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Course Session'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: dateCtrl,
                decoration: const InputDecoration(labelText: 'Session Date (YYYY-MM-DD)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: topicCtrl,
                decoration: const InputDecoration(labelText: 'Topic / Subject'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<SessionType>(
                initialValue: selectedType,
                decoration: const InputDecoration(labelText: 'Session Type'),
                items: SessionType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label))).toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedType = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final updated = s.copyWith(
                  sessionDate: dateCtrl.text.trim(),
                  topic: topicCtrl.text.trim(),
                  sessionType: selectedType,
                  creditWeight: selectedType.defaultCreditWeight,
                  updatedAt: DateTime.now(),
                );
                await ref.read(sessionDaoProvider).updateSession(updated);
                ref.read(auditDaoProvider).logActionSync(AuditLogEntity(
                  id: 'aud_${DateTime.now().millisecondsSinceEpoch}',
                  entityType: 'session',
                  entityId: s.id,
                  action: AuditAction.update,
                  reason: 'Session updated: ${updated.sessionDate} (${updated.topic ?? updated.sessionType.label})',
                  source: 'teacher_ui',
                  createdAt: DateTime.now(),
                ));
                ref.invalidate(sessionsProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteSession(BuildContext context, CourseSessionEntity s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.absent),
            const SizedBox(width: 8),
            Text('Delete Session (${s.sessionDate})?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete the session on ${s.sessionDate} (${s.topic ?? s.sessionType.label})?\n\n'
          'All attendance marks recorded for this session will be permanently deleted.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await ref.read(sessionDaoProvider).deleteSession(s.id);
              ref.read(auditDaoProvider).logActionSync(AuditLogEntity(
                id: 'aud_${DateTime.now().millisecondsSinceEpoch}',
                entityType: 'session',
                entityId: s.id,
                action: AuditAction.delete,
                reason: 'Session deleted: ${s.sessionDate} (${s.topic ?? s.sessionType.label})',
                source: 'teacher_ui',
                createdAt: DateTime.now(),
              ));
              ref.read(activeSessionIdProvider.notifier).state = null;
              ref.invalidate(sessionsProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.absent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Session'),
          ),
        ],
      ),
    );
  }
}
