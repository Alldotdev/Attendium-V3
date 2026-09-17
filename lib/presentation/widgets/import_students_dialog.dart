import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_colors.dart';
import '../../domain/entities/audit_log.dart';
import '../../domain/entities/student.dart';
import '../../domain/enums/audit_action.dart';
import '../../infrastructure/ai/ai_models.dart';
import '../providers/classroom_providers.dart';
import '../providers/database_providers.dart';

class _ParsedStudent {
  String roll;
  String name;
  bool selected = true;
  _ParsedStudent({required this.roll, required this.name});
}

/// Dialog to bulk-import a student list from an image, PDF, Excel, CSV, or text file.
class ImportStudentsDialog extends ConsumerStatefulWidget {
  final String classroomId;

  const ImportStudentsDialog({super.key, required this.classroomId});

  static Future<void> show(BuildContext context,
      {required String classroomId}) {
    return showDialog(
      context: context,
      builder: (ctx) => ImportStudentsDialog(classroomId: classroomId),
    );
  }

  @override
  ConsumerState<ImportStudentsDialog> createState() =>
      _ImportStudentsDialogState();
}

class _ImportStudentsDialogState extends ConsumerState<ImportStudentsDialog> {
  // --- file
  PlatformFile? _selectedFile;
  Uint8List? _fileBytes;
  String? _fileMimeType;

  // --- text
  final TextEditingController _textCtrl = TextEditingController();
  int _tab = 0; // 0 = file, 1 = text

  // --- state
  bool _isProcessing = false;
  String? _error;
  List<_ParsedStudent>? _parsed;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'png', 'jpg', 'jpeg', 'webp', 'pdf',
        'csv', 'xlsx', 'xls', 'txt', 'doc', 'docx'
      ],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) {
      setState(() => _error = 'Could not read file bytes.');
      return;
    }
    final ext = (file.extension ?? '').toLowerCase();
    String mime = 'application/octet-stream';
    if (['png', 'jpg', 'jpeg', 'webp'].contains(ext)) {
      mime = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
    } else if (ext == 'pdf') {
      mime = 'application/pdf';
    } else if (['csv', 'txt'].contains(ext)) {
      mime = 'text/plain';
    } else if (['xlsx', 'xls'].contains(ext)) {
      mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    setState(() {
      _selectedFile = file;
      _fileBytes = bytes;
      _fileMimeType = mime;
      _parsed = null;
      _error = null;
    });
  }

  Future<void> _extract() async {
    setState(() {
      _isProcessing = true;
      _error = null;
      _parsed = null;
    });

    try {
      List<AiExtractedRow> rows = [];

      if (_tab == 0 && _fileBytes != null) {
        final aiProvider = ref.read(activeAiProvider);
        final result = await aiProvider.extractAttendance(
          documentBytes: _fileBytes!,
          mimeType: _fileMimeType ?? 'application/octet-stream',
          userPromptContext:
              'This document is a STUDENT LIST / ROSTER. '
              'Extract each student\'s roll number and full name. '
              'Do NOT try to extract attendance status — just roll numbers and names. '
              'Include every student you can see.',
        );
        if (result.isSuccess) {
          rows = result.successOrNull!.rows;
        } else {
          setState(() {
            _error = result.errorOrNull?.message ?? 'Extraction failed';
            _isProcessing = false;
          });
          return;
        }
      } else if (_tab == 1 && _textCtrl.text.trim().isNotEmpty) {
        // Parse text: each line may be "roll, name", "roll name", "name", or "roll"
        final lines = _textCtrl.text.split('\n');
        int idx = 0;
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          String roll = '';
          String name = '';
          
          if (trimmed.contains(',')) {
            final parts = trimmed.split(',');
            roll = parts[0].trim();
            name = parts.sublist(1).join(',').trim();
          } else {
            final parts = trimmed.split(RegExp(r'\s+'));
            if (parts.length == 1) {
              if (RegExp(r'\d').hasMatch(parts[0])) {
                roll = parts[0];
                name = '';
              } else {
                name = parts[0];
                roll = '${idx + 1}';
              }
            } else {
              if (RegExp(r'\d').hasMatch(parts[0])) {
                roll = parts[0];
                name = parts.sublist(1).join(' ');
              } else {
                name = trimmed;
                roll = '${idx + 1}';
              }
            }
          }

          if (roll.isNotEmpty || name.isNotEmpty) {
            if (roll.isEmpty) roll = '${idx + 1}';
            rows.add(AiExtractedRow(
              rowIndex: idx++,
              rawRoll: roll,
              rawName: name,
              visualConfidence: 1.0,
            ));
          }
        }
      }

      // Deduplicate & map to _ParsedStudent
      final seen = <String>{};
      final parsed = <_ParsedStudent>[];
      for (final row in rows) {
        final roll = (row.rawRoll ?? '').trim();
        if (roll.isEmpty) continue;
        if (seen.contains(roll)) continue;
        seen.add(roll);
        parsed.add(_ParsedStudent(
          roll: roll,
          name: (row.rawName ?? '').trim(),
        ));
      }

      setState(() {
        _parsed = parsed;
        _isProcessing = false;
        if (parsed.isEmpty) _error = 'No student entries found in this file.';
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isProcessing = false;
      });
    }
  }

  Future<void> _importSelected() async {
    final toImport = (_parsed ?? []).where((s) => s.selected).toList();
    if (toImport.isEmpty) return;

    setState(() => _importing = true);
    final studentDao = ref.read(studentDaoProvider);
    final auditDao = ref.read(auditDaoProvider);
    int imported = 0;

    for (final s in toImport) {
      if (s.roll.trim().isEmpty) continue;
      final id = 'stud_${DateTime.now().millisecondsSinceEpoch}_$imported';
      final student = StudentEntity(
        id: id,
        classroomId: widget.classroomId,
        rollNumber: s.roll.trim(),
        fullName: s.name.trim().isNotEmpty ? s.name.trim() : s.roll.trim(),
        normalizedName: (s.name.trim().isNotEmpty ? s.name.trim() : s.roll.trim()).toLowerCase(),
        enrolledAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await studentDao.createStudent(student);
      auditDao.logActionSync(AuditLogEntity(
        id: 'aud_${DateTime.now().millisecondsSinceEpoch}_$imported',
        entityType: 'student',
        entityId: id,
        action: AuditAction.create,
        reason: 'Bulk import: ${student.fullName} (${student.rollNumber})',
        source: 'import_ui',
        createdAt: DateTime.now(),
      ));
      imported++;
      await Future.delayed(const Duration(milliseconds: 1)); // ensure unique ms ids
    }

    ref.invalidate(rosterProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = (_parsed ?? []).where((s) => s.selected).length;

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 700,
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
                    child: const Icon(Icons.group_add_rounded,
                        color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Import Student List',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                        Text(
                          'Upload an image, PDF, Excel, or paste text to extract and bulk-enroll students.',
                          style:
                              TextStyle(fontSize: 12, color: AppColors.textMuted),
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
              child: _parsed != null
                  ? _buildReviewView(selectedCount)
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          // Tabs
                          Row(
                            children: [
                              _tabBtn('📁  Upload File', 0),
                              const SizedBox(width: 8),
                              _tabBtn('📝  Paste Text', 1),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: _tab == 0
                                ? _buildFileTab()
                                : _buildTextTab(),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.absentLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline,
                                      color: AppColors.absent, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(_error!,
                                        style: const TextStyle(
                                            color: AppColors.absentDark,
                                            fontSize: 12)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.borderSubtle)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  if (_parsed != null) ...[
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _parsed = null),
                      icon: const Icon(Icons.arrow_back_rounded, size: 16),
                      label: const Text('Back'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: selectedCount > 0 && !_importing
                          ? _importSelected
                          : null,
                      icon: _importing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle_rounded, size: 16),
                      label: Text(_importing
                          ? 'Importing...'
                          : 'Import $selectedCount Students'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.present,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                      ),
                    ),
                  ] else
                    ElevatedButton.icon(
                      onPressed: _isProcessing
                          ? null
                          : ((_tab == 0 && _fileBytes != null) ||
                                  (_tab == 1 &&
                                      _textCtrl.text.trim().isNotEmpty))
                              ? _extract
                              : null,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_awesome_rounded, size: 16),
                      label: Text(
                          _isProcessing ? 'Scanning...' : 'Scan & Extract'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabBtn(String label, int idx) => InkWell(
        onTap: () => setState(() => _tab = idx),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color:
                _tab == idx ? AppColors.primaryLight : AppColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _tab == idx
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : AppColors.borderSubtle,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _tab == idx ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      );

  Widget _buildFileTab() {
    final isImage = _selectedFile != null &&
        ['png', 'jpg', 'jpeg', 'webp']
            .contains((_selectedFile!.extension ?? '').toLowerCase());
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderMedium),
      ),
      padding: const EdgeInsets.all(20),
      child: Center(
        child: _selectedFile == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.cloud_upload_outlined,
                        color: AppColors.primary, size: 28),
                  ),
                  const SizedBox(height: 12),
                  const Text('Upload Student List File',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  const Text(
                      'Supports Images, PDF, Excel (XLSX), CSV, Word (DOCX), or plain text',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.folder_open_rounded, size: 16),
                    label: const Text('Browse Files'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isImage && _fileBytes != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 130,
                        decoration: BoxDecoration(
                            border: Border.all(color: AppColors.borderSubtle)),
                        child: Image.memory(_fileBytes!, fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    const Icon(Icons.description_outlined,
                        color: AppColors.primary, size: 48),
                    const SizedBox(height: 10),
                  ],
                  Text(_selectedFile!.name,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(
                      '${(_selectedFile!.size / 1024).toStringAsFixed(1)} KB • ${_selectedFile!.extension?.toUpperCase()}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickFile,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Change File'),
                      ),
                      const SizedBox(width: 10),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _selectedFile = null;
                          _fileBytes = null;
                          _fileMimeType = null;
                        }),
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 16, color: AppColors.absent),
                        label: const Text('Remove',
                            style: TextStyle(color: AppColors.absent)),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildTextTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Paste one student per line:\n  Roll Number, Name   or   Roll   Name   (space-separated)',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: TextField(
            controller: _textCtrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText:
                  'e.g.:\nF24-501, Ali Hassan\nF24-502, Sara Khan\n588 John Smith\n589',
              hintStyle: const TextStyle(
                  fontSize: 12, color: AppColors.textDisabled),
              filled: true,
              fillColor: AppColors.surfaceSubtle,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: AppColors.borderSubtle)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: AppColors.borderSubtle)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                      color: AppColors.primary, width: 1.5)),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewView(int selectedCount) {
    final parsed = _parsed!;
    final allSelected = parsed.isNotEmpty && parsed.every((s) => s.selected);

    return Column(
      children: [
        // Review header
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: AppColors.surfaceSubtle,
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: AppColors.present, size: 16),
              const SizedBox(width: 8),
              Text(
                '${parsed.length} students extracted. Review and deselect any to skip.',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  for (final s in parsed) {
                    s.selected = true;
                  }
                }),
                child: const Text('Select All',
                    style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: () => setState(() {
                  for (final s in parsed) {
                    s.selected = false;
                  }
                }),
                child: const Text('Deselect All',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ),
            ],
          ),
        ),

        // Column headers
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(
                bottom: BorderSide(color: AppColors.borderSubtle)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Checkbox(
                  value: allSelected,
                  tristate: true,
                  onChanged: (val) => setState(() {
                    for (final s in parsed) {
                      s.selected = val ?? false;
                    }
                  }),
                ),
              ),
              const SizedBox(width: 130,
                  child: Text('#  Roll Number',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted))),
              const Expanded(
                  child: Text('Full Name',
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
            itemCount: parsed.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: AppColors.borderSubtle),
            itemBuilder: (ctx, idx) {
              final s = parsed[idx];
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 6),
                color: s.selected
                    ? AppColors.presentLight.withValues(alpha: 0.15)
                    : AppColors.surface,
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Checkbox(
                        value: s.selected,
                        onChanged: (val) =>
                            setState(() => s.selected = val ?? false),
                      ),
                    ),
                    // Roll Number (editable)
                    SizedBox(
                      width: 130,
                      child: TextFormField(
                        initialValue: s.roll,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => s.roll = v,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Name (editable)
                    Expanded(
                      child: TextFormField(
                        initialValue: s.name,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          border: OutlineInputBorder(),
                          hintText: '(enter name)',
                        ),
                        onChanged: (v) => s.name = v,
                      ),
                    ),
                    // Delete row
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          size: 16, color: AppColors.textMuted),
                      tooltip: 'Remove from import',
                      onPressed: () => setState(() => parsed.removeAt(idx)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
