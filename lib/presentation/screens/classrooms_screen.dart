import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../domain/entities/academic_term.dart';
import '../../domain/entities/attendance_policy.dart';
import '../../domain/entities/audit_log.dart';
import '../../domain/entities/classroom.dart';
import '../../domain/entities/student.dart';
import '../../domain/enums/audit_action.dart';
import '../providers/classroom_providers.dart';
import '../providers/database_providers.dart';
import '../widgets/import_students_dialog.dart';
import '../widgets/student_attendance_history_dialog.dart';

class ClassroomsScreen extends ConsumerStatefulWidget {
  const ClassroomsScreen({super.key});

  @override
  ConsumerState<ClassroomsScreen> createState() => _ClassroomsScreenState();
}

class _ClassroomsScreenState extends ConsumerState<ClassroomsScreen> {
  String _rosterSearchQuery = '';

  @override
  Widget build(BuildContext context) {
    final termsAsync = ref.watch(termsProvider);
    final selectedTermId = ref.watch(selectedTermIdProvider);
    final classroomsAsync = ref.watch(classroomsProvider);
    final selectedClassroomId = ref.watch(selectedClassroomIdProvider);
    final rosterAsync = ref.watch(rosterProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // -----------------------------------------------------------
          // Column 1: Terms & Classrooms Navigation List (320px)
          // -----------------------------------------------------------
          Container(
            width: 320,
            decoration: const BoxDecoration(
              color: AppColors.surfaceSubtle,
              border: Border(right: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Term Header
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Academic Terms',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 18),
                        onPressed: () => _showAddTermDialog(context),
                        tooltip: 'Add Term',
                      ),
                    ],
                  ),
                ),
                // Term Selector
                termsAsync.when(
                  data: (terms) {
                    if (terms.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: OutlinedButton(
                          onPressed: () => _showAddTermDialog(context),
                          child: const Text('Create First Term'),
                        ),
                      );
                    }
                    final activeTerm = terms.firstWhere(
                      (t) => t.id == selectedTermId,
                      orElse: () => terms.first,
                    );

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.borderSubtle),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: (selectedTermId != null && terms.any((t) => t.id == selectedTermId))
                                      ? selectedTermId
                                      : (terms.isNotEmpty ? terms.first.id : null),
                                  items: terms.map((t) => DropdownMenuItem(
                                    value: t.id,
                                    child: Text(t.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  )).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      ref.read(selectedTermIdProvider.notifier).state = val;
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textSecondary),
                            tooltip: 'Term Options',
                            onSelected: (action) {
                              if (action == 'edit') {
                                _showEditTermDialog(context, activeTerm);
                              } else if (action == 'delete') {
                                _confirmDeleteTerm(context, activeTerm);
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(children: [Icon(Icons.edit_outlined, size: 16), SizedBox(width: 8), Text('Edit Term')]),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(children: [Icon(Icons.delete_outline, size: 16, color: AppColors.absent), SizedBox(width: 8), Text('Delete Term', style: TextStyle(color: AppColors.absent))]),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Error loading terms: $e'),
                  ),

                  const SizedBox(height: 16),
                  const Divider(height: 1),

                  // Classroom Header
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Courses & Sections',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 18),
                          onPressed: () => _showAddClassroomDialog(context),
                          tooltip: 'Add Classroom',
                        ),
                      ],
                    ),
                  ),

                  // Classroom List
                  Expanded(
                    child: classroomsAsync.when(
                      data: (classrooms) {
                        if (classrooms.isEmpty) {
                          return const Center(
                            child: Text('No courses in this term', style: TextStyle(fontSize: 12, color: AppColors.textDisabled)),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: classrooms.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 4),
                          itemBuilder: (context, i) {
                            final c = classrooms[i];
                            final isSelected = c.id == (selectedClassroomId ?? classrooms.first.id);

                            return Material(
                              color: isSelected ? AppColors.primaryLight : AppColors.surface,
                              borderRadius: BorderRadius.circular(6),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () {
                                  ref.read(selectedClassroomIdProvider.notifier).state = c.id;
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isSelected ? AppColors.primary.withValues(alpha: 0.3) : AppColors.borderSubtle,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                       Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              c.courseCode,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                                color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.surfaceSubtle,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  'Sec ${c.section}',
                                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                                                ),
                                              ),
                                              PopupMenuButton<String>(
                                                icon: const Icon(Icons.more_vert_rounded, size: 16, color: AppColors.textSecondary),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                tooltip: 'Course Options',
                                                onSelected: (action) {
                                                  if (action == 'edit') {
                                                    _showEditClassroomDialog(context, c);
                                                  } else if (action == 'delete') {
                                                    _confirmDeleteClassroom(context, c);
                                                  }
                                                },
                                                itemBuilder: (ctx) => [
                                                  const PopupMenuItem(
                                                    value: 'edit',
                                                    child: Row(children: [Icon(Icons.edit_outlined, size: 16), SizedBox(width: 8), Text('Edit Course')]),
                                                  ),
                                                  const PopupMenuItem(
                                                    value: 'delete',
                                                    child: Row(children: [Icon(Icons.delete_outline, size: 16, color: AppColors.absent), SizedBox(width: 8), Text('Delete Course', style: TextStyle(color: AppColors.absent))]),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        c.courseName,
                                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Text('Error: $e'),
                    ),
                  ),
                ],
              ),
            ),

          // -----------------------------------------------------------
          // Column 2: Student Roster Workbench
          // -----------------------------------------------------------
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(28.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Action header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Classroom Student Roster',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Authoritative local student database for fuzzy matching and attendance registers',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          if (selectedClassroomId != null) ...[
                            OutlinedButton.icon(
                              onPressed: () => ImportStudentsDialog.show(context, classroomId: selectedClassroomId),
                              icon: const Icon(Icons.upload_file_outlined, size: 16),
                              label: const Text('Import Student List'),
                            ),
                            const SizedBox(width: 8),
                          ],
                          ElevatedButton.icon(
                            onPressed: () => _showAddStudentDialog(context),
                            icon: const Icon(Icons.person_add, size: 16),
                            label: const Text('Add Student'),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Search & Filters bar
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Search students by roll number or full name...',
                            prefixIcon: Icon(Icons.search, size: 18),
                          ),
                          onChanged: (val) {
                            setState(() {
                              _rosterSearchQuery = val.toLowerCase().trim();
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Students Table
                  Expanded(
                    child: rosterAsync.when(
                      data: (students) {
                        final filtered = students.where((s) {
                          if (_rosterSearchQuery.isEmpty) return true;
                          return s.rollNumber.toLowerCase().contains(_rosterSearchQuery) ||
                              s.fullName.toLowerCase().contains(_rosterSearchQuery);
                        }).toList();

                        if (filtered.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.people_outline, size: 48, color: AppColors.textDisabled),
                                const SizedBox(height: 12),
                                Text(
                                  students.isEmpty ? 'No students enrolled in this classroom yet' : 'No matching students found',
                                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: () => _showAddStudentDialog(context),
                                  child: const Text('Enroll New Student'),
                                ),
                              ],
                            ),
                          );
                        }

                        return Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: SingleChildScrollView(
                            child: DataTable(
                              headingRowHeight: 42,
                              dataRowMinHeight: 48,
                              dataRowMaxHeight: 52,
                              columns: const [
                                DataColumn(label: Text('Roll Number', style: TextStyle(fontWeight: FontWeight.w700))),
                                DataColumn(label: Text('Student Full Name', style: TextStyle(fontWeight: FontWeight.w700))),
                                DataColumn(label: Text('Normalized Name', style: TextStyle(fontWeight: FontWeight.w700))),
                                DataColumn(label: Text('Email Address', style: TextStyle(fontWeight: FontWeight.w700))),
                                DataColumn(label: Text('Enrolled Date', style: TextStyle(fontWeight: FontWeight.w700))),
                                DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.w700))),
                              ],
                              rows: filtered.map((s) {
                                return DataRow(cells: [
                                  DataCell(Text(s.rollNumber, style: const TextStyle(fontWeight: FontWeight.w600))),
                                  DataCell(Text(s.fullName)),
                                  DataCell(Text(s.normalizedName, style: const TextStyle(color: AppColors.textMuted, fontSize: 12))),
                                  DataCell(Text(s.email ?? '—')),
                                  DataCell(Text(s.enrolledAt.toIso8601String().split('T')[0])),
                                  DataCell(Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (selectedClassroomId != null)
                                        IconButton(
                                          icon: const Icon(Icons.bar_chart_rounded, size: 16, color: AppColors.primary),
                                          onPressed: () => StudentAttendanceHistoryDialog.show(
                                            context,
                                            student: s,
                                            classroomId: selectedClassroomId,
                                          ),
                                          tooltip: 'Attendance History',
                                        ),
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 16),
                                        onPressed: () => _showEditStudentDialog(context, s),
                                        tooltip: 'Edit Student Details',
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.absent),
                                        onPressed: () => _confirmDeleteStudent(context, s),
                                        tooltip: 'Remove / Delete Student',
                                      ),
                                    ],
                                  )),
                                ]);
                              }).toList(),
                            ),
                          ),
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Text('Error loading roster: $e'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddTermDialog(BuildContext context) {
    final nameCtrl = TextEditingController(text: 'Fall 2026');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Academic Term'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Term Name (e.g. Fall 2026)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final termId = 'term_${DateTime.now().millisecondsSinceEpoch}';
              final term = AcademicTermEntity(
                id: termId,
                userId: currentUserId,
                name: nameCtrl.text.trim(),
                startDate: DateTime.now(),
                endDate: DateTime.now().add(const Duration(days: 120)),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              );
              await ref.read(classroomDaoProvider).createTerm(term);
              ref.read(auditDaoProvider).logActionSync(AuditLogEntity(
                id: 'aud_${DateTime.now().millisecondsSinceEpoch}',
                entityType: 'term',
                entityId: termId,
                action: AuditAction.create,
                reason: 'Term created: ${term.name}',
                source: 'teacher_ui',
                createdAt: DateTime.now(),
              ));
              ref.invalidate(termsProvider);
              ref.read(selectedTermIdProvider.notifier).state = termId;
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Create Term'),
          ),
        ],
      ),
    );
  }

  void _showAddClassroomDialog(BuildContext context) {
    final codeCtrl = TextEditingController(text: 'CS-301');
    final nameCtrl = TextEditingController(text: 'Operating Systems');
    final secCtrl = TextEditingController(text: 'A');
    final instCtrl = TextEditingController(text: 'Prof. Alan Turing');
    final thresholdCtrl = TextEditingController(text: '75.0');
    final lateWeightCtrl = TextEditingController(text: '0.5');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Course Section'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Course Code (e.g. CS-301)')),
                const SizedBox(height: 10),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Course Name')),
                const SizedBox(height: 10),
                TextField(controller: secCtrl, decoration: const InputDecoration(labelText: 'Section (e.g. A)')),
                const SizedBox(height: 10),
                TextField(controller: instCtrl, decoration: const InputDecoration(labelText: 'Instructor Name')),
                const SizedBox(height: 10),
                TextField(controller: thresholdCtrl, decoration: const InputDecoration(labelText: 'Attendance Threshold (%)')),
                const SizedBox(height: 10),
                TextField(controller: lateWeightCtrl, decoration: const InputDecoration(labelText: 'Late Status Weight (e.g. 0.5)')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final termId = ref.read(selectedTermIdProvider) ?? 'term_default';
              final classId = 'class_${DateTime.now().millisecondsSinceEpoch}';
              final classroom = ClassroomEntity(
                id: classId,
                userId: currentUserId,
                academicTermId: termId,
                courseCode: codeCtrl.text.trim(),
                courseName: nameCtrl.text.trim(),
                section: secCtrl.text.trim(),
                instructorName: instCtrl.text.trim(),
                attendanceThreshold: double.tryParse(thresholdCtrl.text.trim()) ?? 75.0,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              );

              final policy = AttendancePolicyEntity(
                id: 'pol_$classId',
                classroomId: classId,
                minimumPercentage: double.tryParse(thresholdCtrl.text.trim()) ?? 75.0,
                lateWeight: double.tryParse(lateWeightCtrl.text.trim()) ?? 0.5,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              );

              await ref.read(classroomDaoProvider).createClassroom(classroom);
              await ref.read(attendanceDaoProvider).savePolicy(policy);
              ref.read(auditDaoProvider).logActionSync(AuditLogEntity(
                id: 'aud_${DateTime.now().millisecondsSinceEpoch}',
                entityType: 'classroom',
                entityId: classId,
                action: AuditAction.create,
                reason: 'Classroom created: ${classroom.courseCode} ${classroom.section}',
                source: 'teacher_ui',
                createdAt: DateTime.now(),
              ));
              ref.invalidate(classroomsProvider);
              ref.read(selectedClassroomIdProvider.notifier).state = classId;
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save Classroom'),
          ),
        ],
      ),
    );
  }

  void _showAddStudentDialog(BuildContext context) {
    final rollCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enroll New Student'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: rollCtrl, decoration: const InputDecoration(labelText: 'Roll Number / ID')),
              const SizedBox(height: 10),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name')),
              const SizedBox(height: 10),
              TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email Address (Optional)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final classroomId = ref.read(selectedClassroomIdProvider);
              if (classroomId == null) return;

              final studentId = 'stud_${DateTime.now().millisecondsSinceEpoch}';
              final student = StudentEntity(
                id: studentId,
                classroomId: classroomId,
                rollNumber: rollCtrl.text.trim(),
                fullName: nameCtrl.text.trim(),
                normalizedName: nameCtrl.text.trim().toLowerCase(),
                email: emailCtrl.text.trim().isNotEmpty ? emailCtrl.text.trim() : null,
                enrolledAt: DateTime.now(),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              );

              await ref.read(studentDaoProvider).createStudent(student);
              ref.read(auditDaoProvider).logActionSync(AuditLogEntity(
                id: 'aud_${DateTime.now().millisecondsSinceEpoch}',
                entityType: 'student',
                entityId: studentId,
                action: AuditAction.create,
                reason: 'Student enrolled: ${student.fullName} (${student.rollNumber})',
                source: 'teacher_ui',
                createdAt: DateTime.now(),
              ));
              ref.invalidate(rosterProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Enroll Student'),
          ),
        ],
      ),
    );
  }

  void _showEditStudentDialog(BuildContext context, StudentEntity s) {
    final rollCtrl = TextEditingController(text: s.rollNumber);
    final nameCtrl = TextEditingController(text: s.fullName);
    final emailCtrl = TextEditingController(text: s.email ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Student Details'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: rollCtrl, decoration: const InputDecoration(labelText: 'Roll Number')),
              const SizedBox(height: 10),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name')),
              const SizedBox(height: 10),
              TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email Address')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final updated = s.copyWith(
                rollNumber: rollCtrl.text.trim(),
                fullName: nameCtrl.text.trim(),
                normalizedName: nameCtrl.text.trim().toLowerCase(),
                email: emailCtrl.text.trim(),
              );
              await ref.read(studentDaoProvider).updateStudent(updated);
              ref.read(auditDaoProvider).logActionSync(AuditLogEntity(
                id: 'aud_${DateTime.now().millisecondsSinceEpoch}',
                entityType: 'student',
                entityId: s.id,
                action: AuditAction.update,
                reason: 'Student updated: ${updated.fullName} (${updated.rollNumber})',
                source: 'teacher_ui',
                createdAt: DateTime.now(),
              ));
              ref.invalidate(rosterProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showEditClassroomDialog(BuildContext context, ClassroomEntity c) {
    final codeCtrl = TextEditingController(text: c.courseCode);
    final nameCtrl = TextEditingController(text: c.courseName);
    final secCtrl = TextEditingController(text: c.section);
    final instCtrl = TextEditingController(text: c.instructorName);
    final thresholdCtrl = TextEditingController(text: c.attendanceThreshold.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Course Details'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Course Code')),
                const SizedBox(height: 10),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Course Name')),
                const SizedBox(height: 10),
                TextField(controller: secCtrl, decoration: const InputDecoration(labelText: 'Section')),
                const SizedBox(height: 10),
                TextField(controller: instCtrl, decoration: const InputDecoration(labelText: 'Instructor Name')),
                const SizedBox(height: 10),
                TextField(controller: thresholdCtrl, decoration: const InputDecoration(labelText: 'Attendance Threshold (%)')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final updated = c.copyWith(
                courseCode: codeCtrl.text.trim(),
                courseName: nameCtrl.text.trim(),
                section: secCtrl.text.trim(),
                instructorName: instCtrl.text.trim(),
                attendanceThreshold: double.tryParse(thresholdCtrl.text.trim()) ?? c.attendanceThreshold,
                updatedAt: DateTime.now(),
              );
              await ref.read(classroomDaoProvider).updateClassroom(updated);
              ref.read(auditDaoProvider).logActionSync(AuditLogEntity(
                id: 'aud_${DateTime.now().millisecondsSinceEpoch}',
                entityType: 'classroom',
                entityId: c.id,
                action: AuditAction.update,
                reason: 'Classroom updated: ${updated.courseCode} ${updated.section}',
                source: 'teacher_ui',
                createdAt: DateTime.now(),
              ));
              ref.invalidate(classroomsProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteClassroom(BuildContext context, ClassroomEntity c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.absent),
            const SizedBox(width: 8),
            Text('Delete ${c.courseCode}?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${c.courseCode} - ${c.courseName} (Section ${c.section})"?\n\n'
          'All course sessions, student enrollments, and attendance records associated with this classroom will be permanently deleted.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await ref.read(classroomDaoProvider).deleteClassroom(c.id);
              ref.read(auditDaoProvider).logActionSync(AuditLogEntity(
                id: 'aud_${DateTime.now().millisecondsSinceEpoch}',
                entityType: 'classroom',
                entityId: c.id,
                action: AuditAction.delete,
                reason: 'Classroom deleted: ${c.courseCode} ${c.section}',
                source: 'teacher_ui',
                createdAt: DateTime.now(),
              ));
              ref.read(selectedClassroomIdProvider.notifier).state = null;
              ref.invalidate(classroomsProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.absent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Course'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteStudent(BuildContext context, StudentEntity s) {
    final classroomId = ref.read(selectedClassroomIdProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.person_remove_rounded, color: AppColors.absent),
            const SizedBox(width: 8),
            Text('Remove ${s.fullName}?'),
          ],
        ),
        content: Text(
          'Choose an action for student "${s.fullName}" (Roll: ${s.rollNumber}):\n\n'
          '• "Remove from Course": Unenrolls the student from this course section only.\n'
          '• "Delete Permanently": Removes the student completely from the entire database.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          if (classroomId != null)
            OutlinedButton(
              onPressed: () async {
                await ref.read(studentDaoProvider).removeStudentFromClassroom(s.id, classroomId);
                ref.read(auditDaoProvider).logActionSync(AuditLogEntity(
                  id: 'aud_${DateTime.now().millisecondsSinceEpoch}',
                  entityType: 'student',
                  entityId: s.id,
                  action: AuditAction.delete,
                  reason: 'Student removed from classroom: ${s.fullName} (${s.rollNumber})',
                  source: 'teacher_ui',
                  createdAt: DateTime.now(),
                ));
                ref.invalidate(rosterProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Remove from Course'),
            ),
          ElevatedButton(
            onPressed: () async {
              await ref.read(studentDaoProvider).deleteStudent(s.id);
              ref.read(auditDaoProvider).logActionSync(AuditLogEntity(
                id: 'aud_${DateTime.now().millisecondsSinceEpoch}',
                entityType: 'student',
                entityId: s.id,
                action: AuditAction.delete,
                reason: 'Student permanently deleted: ${s.fullName} (${s.rollNumber})',
                source: 'teacher_ui',
                createdAt: DateTime.now(),
              ));
              ref.invalidate(rosterProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.absent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  void _showEditTermDialog(BuildContext context, AcademicTermEntity t) {
    final nameCtrl = TextEditingController(text: t.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Academic Term'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Term Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final updated = t.copyWith(
                name: nameCtrl.text.trim(),
                updatedAt: DateTime.now(),
              );
              await ref.read(classroomDaoProvider).updateTerm(updated);
              ref.read(auditDaoProvider).logActionSync(AuditLogEntity(
                id: 'aud_${DateTime.now().millisecondsSinceEpoch}',
                entityType: 'term',
                entityId: t.id,
                action: AuditAction.update,
                reason: 'Term renamed: ${t.name} → ${updated.name}',
                source: 'teacher_ui',
                createdAt: DateTime.now(),
              ));
              ref.invalidate(termsProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteTerm(BuildContext context, AcademicTermEntity t) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.absent),
            const SizedBox(width: 8),
            Text('Delete "${t.name}"?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete term "${t.name}"?\n\n'
          'All courses and attendance registers under this academic term will be permanently removed.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await ref.read(classroomDaoProvider).deleteTerm(t.id);
              ref.read(auditDaoProvider).logActionSync(AuditLogEntity(
                id: 'aud_${DateTime.now().millisecondsSinceEpoch}',
                entityType: 'term',
                entityId: t.id,
                action: AuditAction.delete,
                reason: 'Term deleted: ${t.name}',
                source: 'teacher_ui',
                createdAt: DateTime.now(),
              ));
              ref.read(selectedTermIdProvider.notifier).state = null;
              ref.invalidate(termsProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.absent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Term'),
          ),
        ],
      ),
    );
  }
}
