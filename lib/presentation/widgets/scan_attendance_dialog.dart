import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../domain/entities/student.dart';
import '../../domain/enums/attendance_status.dart';
import '../../domain/enums/match_confidence_band.dart';
import '../../domain/services/fuzzy_matcher.dart';
import '../../infrastructure/document/tabular_parser.dart';
import '../../infrastructure/document/text_attendance_parser.dart';
import '../../infrastructure/ai/gemini_provider.dart';
import '../providers/attendance_grid_provider.dart';
import '../providers/classroom_providers.dart';
import '../providers/database_providers.dart';
import '../../domain/entities/audit_log.dart';
import '../../domain/enums/audit_action.dart';

/// Item representing a single extracted attendance record matched against a student candidate.
class ScannedMatchItem {
  final String rawInput;
  final String? rawRoll;
  final String? rawName;
  final StudentMatchCandidate? matchedStudent;
  final MatchConfidenceBand confidenceBand;
  final double confidenceScore;
  AttendanceStatus status;
  bool isSelected;

  ScannedMatchItem({
    required this.rawInput,
    this.rawRoll,
    this.rawName,
    this.matchedStudent,
    required this.confidenceBand,
    required this.confidenceScore,
    required this.status,
    this.isSelected = true,
  });
}

/// Dialog allowing teachers to scan physical paper sheets, screenshots, documents,
/// or paste roll number lists to automatically mark attendance in the active session.
class ScanAttendanceDialog extends ConsumerStatefulWidget {
  final List<StudentEntity> roster;
  final String sessionId;

  const ScanAttendanceDialog({
    super.key,
    required this.roster,
    required this.sessionId,
  });

  static Future<int?> show(BuildContext context, {
    required List<StudentEntity> roster,
    required String sessionId,
  }) {
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ScanAttendanceDialog(
        roster: roster,
        sessionId: sessionId,
      ),
    );
  }

  @override
  ConsumerState<ScanAttendanceDialog> createState() => _ScanAttendanceDialogState();
}

class _ScanAttendanceDialogState extends ConsumerState<ScanAttendanceDialog> {
  int _currentTab = 0; // 0: File/Screenshot, 1: Text Snippet
  AttendanceStatus _defaultStatus = AttendanceStatus.present;

  // File Upload State
  PlatformFile? _selectedFile;
  Uint8List? _fileBytes;
  String? _fileMimeType;

  // Text Snippet State
  final TextEditingController _textController = TextEditingController();

  // Processing & Results State
  bool _isProcessing = false;
  String? _errorMessage;
  List<ScannedMatchItem>? _matchItems;

  // Vision API Provider & Key State
  late String _dialogProviderType;
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _customModelController = TextEditingController();
  bool _obscureApiKey = true;
  bool _showApiKeyInput = false;

  @override
  void initState() {
    super.initState();
    final ai = ref.read(aiSettingsProvider);
    _dialogProviderType = ai.providerType == 'deterministic_local' ? 'gemini' : ai.providerType;
    _syncControllerToProvider();
  }

  void _syncControllerToProvider() {
    final ai = ref.read(aiSettingsProvider);
    switch (_dialogProviderType) {
      case 'gemini':
        _apiKeyController.text = ai.geminiApiKey;
        break;
      case 'claude':
        _apiKeyController.text = ai.claudeApiKey;
        break;
      case 'openai':
        _apiKeyController.text = ai.openaiApiKey;
        break;
      case 'custom':
        _apiKeyController.text = ai.customApiKey;
        _baseUrlController.text = ai.customBaseUrl;
        _customModelController.text = ai.customModel;
        break;
    }
  }

  String _providerDisplayName(String type) {
    switch (type) {
      case 'gemini':
        return 'Google Gemini';
      case 'claude':
        return 'Anthropic Claude';
      case 'openai':
        return 'OpenAI ChatGPT';
      case 'custom':
        return 'Cursor / Compatible';
      default:
        return 'AI Assistant';
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _customModelController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() => _errorMessage = null);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'pdf', 'csv', 'xlsx', 'xls', 'txt'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        }

        if (bytes == null) {
          setState(() => _errorMessage = 'Could not read bytes from the selected file.');
          return;
        }

        final ext = (file.extension ?? '').toLowerCase();
        String mime = 'application/octet-stream';
        if (['png', 'jpg', 'jpeg', 'webp'].contains(ext)) {
          mime = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
        } else if (ext == 'pdf') {
          mime = 'application/pdf';
        } else if (ext == 'csv' || ext == 'txt') {
          mime = 'text/csv';
        } else if (ext == 'xlsx' || ext == 'xls') {
          mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        }

        setState(() {
          _selectedFile = file;
          _fileBytes = bytes;
          _fileMimeType = mime;
          _matchItems = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'File selection error: $e');
    }
  }

  Future<List<StudentMatchCandidate>> _buildCandidates() async {
    final studentDao = ref.read(studentDaoProvider);
    final candidates = <StudentMatchCandidate>[];

    for (final s in widget.roster) {
      final aliasesRes = await studentDao.getAliasesForStudent(s.id);
      final aliases = (aliasesRes.successOrNull ?? []).map((a) => a.alias).toList();
      candidates.add(StudentMatchCandidate(
        id: s.id,
        rollNumber: s.rollNumber,
        fullName: s.fullName,
        normalizedName: s.normalizedName,
        aliases: aliases,
        isEnrolledInClassroom: true,
      ));
    }
    return candidates;
  }

  Future<void> _processScan() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _matchItems = null;
    });

    try {
      final candidates = await _buildCandidates();
      const matcher = FuzzyMatcher();
      final items = <ScannedMatchItem>[];

      if (_currentTab == 1) {
        // --- Tab 1: Text / Snippet Parsing ---
        final text = _textController.text.trim();
        if (text.isEmpty) {
          setState(() {
            _isProcessing = false;
            _errorMessage = 'Please enter or paste roll numbers / names.';
          });
          return;
        }

        final parsedEntries = TextAttendanceParser.parse(
          text,
          defaultStatus: _defaultStatus,
        );

        if (parsedEntries.isEmpty) {
          setState(() {
            _isProcessing = false;
            _errorMessage = 'Could not find any student entries in the pasted text.';
          });
          return;
        }

        for (final entry in parsedEntries) {
          final matches = matcher.match(
            rawRoll: entry.roll,
            rawName: entry.name,
            candidates: candidates,
          );

          final bestMatch = matches.isNotEmpty ? matches.first : null;
          final isMatched = bestMatch != null && bestMatch.isMatched;

          items.add(ScannedMatchItem(
            rawInput: entry.originalText,
            rawRoll: entry.roll,
            rawName: entry.name,
            matchedStudent: isMatched ? bestMatch.candidate : null,
            confidenceBand: bestMatch?.band ?? MatchConfidenceBand.unmatched,
            confidenceScore: bestMatch?.finalScore ?? 0.0,
            status: entry.status,
            isSelected: isMatched,
          ));
        }
      } else {
        // --- Tab 0: File / Image / Doc Upload ---
        if (_fileBytes == null || _selectedFile == null) {
          setState(() {
            _isProcessing = false;
            _errorMessage = 'Please select a document or screenshot first.';
          });
          return;
        }

        final ext = (_selectedFile!.extension ?? '').toLowerCase();
        final mime = _fileMimeType ?? 'application/octet-stream';

        if (ext == 'csv' || ext == 'txt') {
          final content = utf8.decode(_fileBytes!, allowMalformed: true);
          final tabularRes = TabularParser.parseCsv(content);
          final tabRows = tabularRes.successOrNull?.rows ?? [];

          if (tabRows.isNotEmpty && tabRows.any((r) => r.roll != null || r.name != null)) {
            for (final r in tabRows) {
              final matches = matcher.match(
                rawRoll: r.roll,
                rawName: r.name,
                candidates: candidates,
              );
              final best = matches.isNotEmpty ? matches.first : null;
              final isMatched = best != null && best.isMatched;
              final status = _parseStatus(r.attendance) ?? _defaultStatus;

              items.add(ScannedMatchItem(
                rawInput: [r.roll, r.name].whereType<String>().join(' - '),
                rawRoll: r.roll,
                rawName: r.name,
                matchedStudent: isMatched ? best.candidate : null,
                confidenceBand: best?.band ?? MatchConfidenceBand.unmatched,
                confidenceScore: best?.finalScore ?? 0.0,
                status: status,
                isSelected: isMatched,
              ));
            }
          } else {
            // Fallback to text lines parser
            final textEntries = TextAttendanceParser.parse(content, defaultStatus: _defaultStatus);
            for (final e in textEntries) {
              final matches = matcher.match(
                rawRoll: e.roll,
                rawName: e.name,
                candidates: candidates,
              );
              final best = matches.isNotEmpty ? matches.first : null;
              final isMatched = best != null && best.isMatched;

              items.add(ScannedMatchItem(
                rawInput: e.originalText,
                rawRoll: e.roll,
                rawName: e.name,
                matchedStudent: isMatched ? best.candidate : null,
                confidenceBand: best?.band ?? MatchConfidenceBand.unmatched,
                confidenceScore: best?.finalScore ?? 0.0,
                status: e.status,
                isSelected: isMatched,
              ));
            }
          }
        } else if (ext == 'xlsx' || ext == 'xls') {
          final tabularRes = TabularParser.parseXlsx(_fileBytes!);
          if (tabularRes.isSuccess) {
            final tabRows = tabularRes.successOrNull!.rows;
            for (final r in tabRows) {
              final matches = matcher.match(
                rawRoll: r.roll,
                rawName: r.name,
                candidates: candidates,
              );
              final best = matches.isNotEmpty ? matches.first : null;
              final isMatched = best != null && best.isMatched;
              final status = _parseStatus(r.attendance) ?? _defaultStatus;

              items.add(ScannedMatchItem(
                rawInput: [r.roll, r.name].whereType<String>().join(' - '),
                rawRoll: r.roll,
                rawName: r.name,
                matchedStudent: isMatched ? best.candidate : null,
                confidenceBand: best?.band ?? MatchConfidenceBand.unmatched,
                confidenceScore: best?.finalScore ?? 0.0,
                status: status,
                isSelected: isMatched,
              ));
            }
          } else {
            throw Exception('Could not parse Excel spreadsheet: ${tabularRes.errorOrNull?.message}');
          }
        } else {
          // Image / Screenshot / PDF extraction via AI Provider
          final aiSettings = ref.read(aiSettingsProvider);
          bool hasKey = false;
          switch (aiSettings.providerType) {
            case 'gemini':
              hasKey = aiSettings.geminiApiKey.trim().isNotEmpty;
              break;
            case 'claude':
              hasKey = aiSettings.claudeApiKey.trim().isNotEmpty;
              break;
            case 'openai':
              hasKey = aiSettings.openaiApiKey.trim().isNotEmpty;
              break;
            case 'custom':
              hasKey = aiSettings.customApiKey.trim().isNotEmpty;
              break;
            default:
              hasKey = false;
          }

          if (!hasKey) {
            setState(() {
              _isProcessing = false;
              _showApiKeyInput = true;
              _errorMessage = 'An API key is required for ${_providerDisplayName(aiSettings.providerType)}. Please configure it below, or use the "Paste Text" tab.';
            });
            return;
          }

          final ai = ref.read(activeAiProvider);
          final extractRes = await ai.extractAttendance(
            documentBytes: _fileBytes!,
            mimeType: mime,
            userPromptContext: 'Attendance sheet for classroom with ${widget.roster.length} students.',
          );

          if (extractRes.isFailure) {
            final err = extractRes.errorOrNull?.message ?? 'Extraction failed';
            setState(() {
              _isProcessing = false;
              _errorMessage = 'Scan error: $err. Ensure your ${_providerDisplayName(aiSettings.providerType)} API key is valid or use the Paste Text tab.';
            });
            return;
          }

          final payload = extractRes.successOrNull!;
          for (final row in payload.rows) {
            // Sanitize roll number by stripping any leading dashes, bullets, or whitespace (e.g. "- 552" -> "552")
            String? roll = row.rawRoll;
            if (roll != null) {
              roll = roll.replaceAll(RegExp(r'^([-\*•]|\d+[\.\)])\s*'), '').trim();
              roll = roll.replaceAll(RegExp(r'^[-\:\,\.\s]+|[-\:\,\.\s]+$'), '').trim();
              if (roll.isEmpty) roll = null;
            }

            final matches = matcher.match(
              rawRoll: roll,
              rawName: row.rawName,
              candidates: candidates,
            );
            final best = matches.isNotEmpty ? matches.first : null;
            final isMatched = best != null && best.isMatched;
            final status = _parseStatus(row.rawAttendance) ?? _defaultStatus;

            items.add(ScannedMatchItem(
              rawInput: [row.rawRoll, row.rawName].whereType<String>().join(' • '),
              rawRoll: roll,
              rawName: row.rawName,
              matchedStudent: isMatched ? best.candidate : null,
              confidenceBand: best?.band ?? MatchConfidenceBand.unmatched,
              confidenceScore: best?.finalScore ?? 0.0,
              status: status,
              isSelected: isMatched,
            ));
          }
        }
      }

      setState(() {
        _isProcessing = false;
        _matchItems = items;
        if (items.isEmpty) {
          _errorMessage = 'No student records could be detected from the input.';
        }
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Processing failed: $e';
      });
    }
  }

  AttendanceStatus? _parseStatus(String? raw) {
    if (raw == null) return null;
    final lower = raw.trim().toLowerCase();
    if (lower.startsWith('p') || lower.contains('present')) return AttendanceStatus.present;
    if (lower.startsWith('a') || lower.contains('absent')) return AttendanceStatus.absent;
    if (lower.startsWith('l') || lower.contains('late')) return AttendanceStatus.late;
    if (lower.startsWith('e') || lower.contains('excuse')) return AttendanceStatus.excused;
    return null;
  }

  void _applyBatchToSession() {
    if (_matchItems == null) return;
    final updates = <String, AttendanceStatus>{};

    for (final item in _matchItems!) {
      if (item.isSelected && item.matchedStudent != null) {
        updates[item.matchedStudent!.id] = item.status;
      }
    }

    if (updates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No matched students selected to apply.'),
          backgroundColor: AppColors.lateDark,
        ),
      );
      return;
    }

    // Save audit log with raw scanned data for "View Source" feature
    try {
      final auditJson = jsonEncode({
        'fileName': _selectedFile?.name ?? 'Manual Text Input',
        'fileSize': _selectedFile?.size,
        'appliedCount': updates.length,
        'timestamp': DateTime.now().toIso8601String(),
        'entries': _matchItems?.map((i) => {
          'input': i.rawInput,
          'roll': i.matchedStudent?.rollNumber ?? i.rawRoll ?? '',
          'name': i.matchedStudent?.fullName ?? i.rawName ?? '',
          'status': i.status.label,
          'matched': i.matchedStudent != null,
        }).toList() ?? [],
      });

      ref.read(auditDaoProvider).logActionSync(AuditLogEntity(
        id: 'aud_scan_${DateTime.now().millisecondsSinceEpoch}',
        entityType: 'session_scan',
        entityId: widget.sessionId,
        action: AuditAction.update,
        afterJson: auditJson,
        reason: 'Scanned attendance imported: ${updates.length} students marked',
        source: 'ai_scan',
        createdAt: DateTime.now(),
      ));
    } catch (_) {}

    ref.read(attendanceGridProvider.notifier).applyScannedBatch(updates);
    Navigator.of(context).pop(updates.length);
  }

  Future<void> _promptAddToRoster(ScannedMatchItem item) async {
    final defaultRoll = item.rawRoll ?? (RegExp(r'^\d+$').hasMatch(item.rawInput) ? item.rawInput : '');
    final defaultName = item.rawName ?? (!RegExp(r'^\d+$').hasMatch(item.rawInput) ? item.rawInput : '');

    final rollCtrl = TextEditingController(text: defaultRoll);
    final nameCtrl = TextEditingController(text: defaultName);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.person_add_alt_1_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Add Student to Roster', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Student detected in scan ("${item.rawInput}") was not found in the current roster. Would you like to enroll them into this classroom?',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: rollCtrl,
                autofocus: defaultRoll.isEmpty,
                decoration: const InputDecoration(
                  labelText: 'Roll Number / ID *',
                  hintText: 'e.g. 588 or F24-588',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                autofocus: defaultRoll.isNotEmpty && defaultName.isEmpty,
                decoration: const InputDecoration(
                  labelText: 'Student Full Name *',
                  hintText: 'e.g. John Doe',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (rollCtrl.text.trim().isNotEmpty) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Enroll & Match'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final classroomId = ref.read(selectedClassroomIdProvider) ??
          (widget.roster.isNotEmpty ? widget.roster.first.classroomId : null);
      if (classroomId == null) return;

      final roll = rollCtrl.text.trim();
      final name = nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : roll;
      final studentId = 'stud_${DateTime.now().millisecondsSinceEpoch}';

      final student = StudentEntity(
        id: studentId,
        classroomId: classroomId,
        rollNumber: roll,
        fullName: name,
        normalizedName: name.toLowerCase(),
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
        reason: 'Enrolled student from scan dialog: $name ($roll)',
        source: 'ai_scan',
        createdAt: DateTime.now(),
      ));

      ref.invalidate(rosterProvider);

      setState(() {
        final idx = _matchItems!.indexOf(item);
        if (idx != -1) {
          _matchItems![idx] = ScannedMatchItem(
            rawInput: item.rawInput,
            rawRoll: roll,
            rawName: name,
            matchedStudent: StudentMatchCandidate(
              id: student.id,
              rollNumber: student.rollNumber,
              fullName: student.fullName,
              normalizedName: student.normalizedName,
            ),
            confidenceBand: MatchConfidenceBand.autoAccept,
            confidenceScore: 1.0,
            status: item.status,
            isSelected: true,
          );
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name ($roll) added to roster and matched!'),
            backgroundColor: AppColors.presentDark,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasResults = _matchItems != null && _matchItems!.isNotEmpty;
    final selectedCount = _matchItems?.where((i) => i.isSelected && i.matchedStudent != null).length ?? 0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 820,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header Bar
              _buildHeader(),
              const SizedBox(height: 16),

              // 2. Error Display if any
              if (_errorMessage != null) ...[
                _buildErrorBanner(_errorMessage!),
                const SizedBox(height: 12),
              ],

              // 3. Body: Either Input Configuration or Match Results Table
              Expanded(
                child: _isProcessing
                    ? _buildProcessingView()
                    : (hasResults ? _buildResultsView() : _buildInputView()),
              ),
              const SizedBox(height: 16),

              // 4. Footer Actions
              _buildFooterActions(hasResults, selectedCount),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 24),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Scan & Auto-Mark Attendance',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              Text(
                'Scan paper sheets, screenshots, documents, or paste roll numbers to auto-adjust attendance.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.absentLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.absent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.absentDark, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: AppColors.absentDark, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tab Selector: Upload File vs Paste Text
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _currentTab = 0),
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _currentTab == 0 ? AppColors.surface : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                      boxShadow: _currentTab == 0
                          ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.upload_file_rounded,
                          size: 16,
                          color: _currentTab == 0 ? AppColors.primary : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Upload Screenshot / Doc',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: _currentTab == 0 ? FontWeight.w700 : FontWeight.w500,
                            color: _currentTab == 0 ? AppColors.primary : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _currentTab = 1),
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _currentTab == 1 ? AppColors.surface : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                      boxShadow: _currentTab == 1
                          ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.paste_rounded,
                          size: 16,
                          color: _currentTab == 1 ? AppColors.primary : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Paste Text / Roll Numbers',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: _currentTab == 1 ? FontWeight.w700 : FontWeight.w500,
                            color: _currentTab == 1 ? AppColors.primary : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Default Status Selector
        Row(
          children: [
            const Text(
              'Default Status for entries without status: ',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 8),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<AttendanceStatus>(
                  value: _defaultStatus,
                  items: [
                    AttendanceStatus.present,
                    AttendanceStatus.absent,
                    AttendanceStatus.late,
                    AttendanceStatus.excused,
                  ].map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  )).toList(),
                  onChanged: (s) {
                    if (s != null) setState(() => _defaultStatus = s);
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Tab Content
        Expanded(
          child: _currentTab == 0 ? _buildFileUploadTab() : _buildTextPasteTab(),
        ),
      ],
    );
  }

  Widget _buildFileUploadTab() {
    final isImage = _selectedFile != null &&
        ['png', 'jpg', 'jpeg', 'webp'].contains((_selectedFile!.extension ?? '').toLowerCase());

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderMedium, style: BorderStyle.solid),
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
                    child: const Icon(Icons.cloud_upload_outlined, color: AppColors.primary, size: 28),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Select Attendance Screenshot, Paper Photo, or Document',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Supports Images (PNG, JPG, WEBP), PDF, Excel (XLSX), or CSV',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.folder_open_rounded, size: 16),
                    label: const Text('Browse Files'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: Image.memory(_fileBytes!, fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    const Icon(Icons.description_outlined, color: AppColors.primary, size: 48),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    _selectedFile!.name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(_selectedFile!.size / 1024).toStringAsFixed(1)} KB • ${_selectedFile!.extension?.toUpperCase()}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 10),

                  // Vision AI Status / Configuration Card for images
                  if (isImage) ...[
                    _buildVisionAiConfigCard(),
                    const SizedBox(height: 12),
                  ],

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickFile,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Change File'),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _selectedFile = null;
                          _fileBytes = null;
                          _fileMimeType = null;
                          _matchItems = null;
                        }),
                        icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.absent),
                        label: const Text('Remove', style: TextStyle(color: AppColors.absent)),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildVisionAiConfigCard() {
    final aiSettings = ref.watch(aiSettingsProvider);
    final activeAi = ref.watch(activeAiProvider);

    bool hasActiveKey = false;
    switch (aiSettings.providerType) {
      case 'gemini':
        hasActiveKey = aiSettings.geminiApiKey.trim().isNotEmpty;
        break;
      case 'claude':
        hasActiveKey = aiSettings.claudeApiKey.trim().isNotEmpty;
        break;
      case 'openai':
        hasActiveKey = aiSettings.openaiApiKey.trim().isNotEmpty;
        break;
      case 'custom':
        hasActiveKey = aiSettings.customApiKey.trim().isNotEmpty;
        break;
      default:
        hasActiveKey = false;
    }

    if (!hasActiveKey || _showApiKeyInput) {
      return Container(
        constraints: const BoxConstraints(maxWidth: 620),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primaryLight.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Select AI Vision Provider',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const Spacer(),
                if (hasActiveKey)
                  InkWell(
                    onTap: () => setState(() => _showApiKeyInput = false),
                    child: const Text('Close', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // Provider Dropdown
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.borderMedium),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _dialogProviderType,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'gemini', child: Text('Google Gemini (Auto Model Discovery • Recommended)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                    DropdownMenuItem(value: 'claude', child: Text('Anthropic Claude (claude-3-5-sonnet)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                    DropdownMenuItem(value: 'openai', child: Text('OpenAI ChatGPT (gpt-4o)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                    DropdownMenuItem(value: 'custom', child: Text('Cursor / Compatible Endpoint (OpenRouter, Groq, Ollama)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _dialogProviderType = val;
                        _syncControllerToProvider();
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),

            if (_dialogProviderType == 'custom') ...[
              SizedBox(
                height: 36,
                child: TextField(
                  controller: _baseUrlController,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'API Base URL',
                    labelStyle: const TextStyle(fontSize: 11),
                    hintText: 'https://openrouter.ai/api/v1 or http://localhost:11434/v1',
                    hintStyle: const TextStyle(fontSize: 11, color: AppColors.textDisabled),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: TextField(
                  controller: _customModelController,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Model Name',
                    labelStyle: const TextStyle(fontSize: 11),
                    hintText: 'e.g. meta-llama/llama-3.2-11b-vision-instruct',
                    hintStyle: const TextStyle(fontSize: 11, color: AppColors.textDisabled),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _apiKeyController,
                      obscureText: _obscureApiKey,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        labelText: '${_providerDisplayName(_dialogProviderType)} API Key',
                        labelStyle: const TextStyle(fontSize: 11),
                        hintText: _dialogProviderType == 'gemini'
                            ? 'Paste Gemini Key (AIzaSy...)'
                            : (_dialogProviderType == 'claude'
                                ? 'Paste Anthropic Key (sk-ant-...)'
                                : 'Paste API Key (sk-...)'),
                        hintStyle: const TextStyle(fontSize: 11, color: AppColors.textDisabled),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureApiKey ? Icons.visibility_off : Icons.visibility, size: 14),
                          onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final key = _apiKeyController.text.trim();
                    if (key.isNotEmpty) {
                      final notifier = ref.read(aiSettingsProvider.notifier);
                      if (_dialogProviderType == 'gemini') {
                        notifier.setGeminiKey(key);
                      } else if (_dialogProviderType == 'claude') {
                        notifier.setClaudeKey(key);
                      } else if (_dialogProviderType == 'openai') {
                        notifier.setOpenAiKey(key);
                      } else if (_dialogProviderType == 'custom') {
                        notifier.setCustomConfig(
                          baseUrl: _baseUrlController.text.trim(),
                          apiKey: key,
                          model: _customModelController.text.trim(),
                        );
                      }
                      notifier.setProvider(_dialogProviderType);

                      setState(() {
                        _showApiKeyInput = false;
                        _errorMessage = null;
                      });

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${_providerDisplayName(_dialogProviderType)} enabled successfully!'),
                          backgroundColor: AppColors.presentDark,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  child: const Text('Save & Use', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    String activeLabel = 'AI Assistant';
    if (aiSettings.providerType == 'gemini') {
      final model = activeAi is GeminiProvider ? activeAi.activeModelName : 'Auto Discovery';
      activeLabel = 'Google Gemini ($model)';
    } else if (aiSettings.providerType == 'claude') {
      activeLabel = 'Anthropic Claude (${aiSettings.claudeModel})';
    } else if (aiSettings.providerType == 'openai') {
      activeLabel = 'OpenAI ChatGPT (${aiSettings.openaiModel})';
    } else if (aiSettings.providerType == 'custom') {
      activeLabel = 'Custom (${aiSettings.customModel})';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.presentLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.present.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.presentDark, size: 14),
          const SizedBox(width: 6),
          Text(
            'Active Engine: $activeLabel',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.presentDark),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: () {
              setState(() {
                _dialogProviderType = aiSettings.providerType == 'deterministic_local' ? 'gemini' : aiSettings.providerType;
                _syncControllerToProvider();
                _showApiKeyInput = true;
              });
            },
            child: const Text(
              'Change Engine / Key',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary, decoration: TextDecoration.underline),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextPasteTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Paste roll numbers (e.g. "588, 589" or "F24-588") or student names. Attendance status like "P", "A", "L" can optionally follow each entry.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TextField(
            controller: _textController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: 'e.g.:\n588\n589 A\nF24-590 P\nSarah Connor L\n\nOr comma-separated:\n588, 589, 590',
              hintStyle: const TextStyle(fontSize: 12, color: AppColors.textDisabled),
              filled: true,
              fillColor: AppColors.surfaceSubtle,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.borderSubtle),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _processScan,
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('Process & Match Students'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProcessingView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Analyzing document & matching student roster...',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          SizedBox(height: 4),
          Text(
            'Evaluating roll number suffixes, full IDs, and adaptive scoring...',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsView() {
    final items = _matchItems!;
    final autoAcceptCount = items.where((i) => i.confidenceBand == MatchConfidenceBand.autoAccept).length;
    final reviewCount = items.where((i) => i.confidenceBand == MatchConfidenceBand.review || i.confidenceBand == MatchConfidenceBand.confirmationRequired).length;
    final unmatchedCount = items.where((i) => i.confidenceBand == MatchConfidenceBand.unmatched).length;

    final allSelected = items.where((i) => i.matchedStudent != null).every((i) => i.isSelected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary & Filter Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            children: [
              _metricPill('Detected', items.length.toString(), AppColors.textPrimary, AppColors.surfaceMuted),
              const SizedBox(width: 8),
              _metricPill('Auto-Accept', autoAcceptCount.toString(), AppColors.presentDark, AppColors.presentLight),
              const SizedBox(width: 8),
              _metricPill('Review', reviewCount.toString(), AppColors.lateDark, AppColors.lateLight),
              const SizedBox(width: 8),
              _metricPill('Unmatched', unmatchedCount.toString(), AppColors.absentDark, AppColors.absentLight),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _matchItems = null),
                icon: const Icon(Icons.arrow_back_rounded, size: 14),
                label: const Text('Re-scan / Edit Input', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Select All row
        Row(
          children: [
            Checkbox(
              value: allSelected,
              onChanged: (val) {
                final checked = val ?? false;
                setState(() {
                  for (final item in items) {
                    if (item.matchedStudent != null) {
                      item.isSelected = checked;
                    }
                  }
                });
              },
            ),
            const Text(
              'Select All Matched Students',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // Scrollable Results Table
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.borderSubtle),
              itemBuilder: (context, idx) {
                final item = items[idx];
                final hasStudent = item.matchedStudent != null;

                return Container(
                  color: item.isSelected ? AppColors.primaryLight.withValues(alpha: 0.2) : AppColors.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Checkbox(
                        value: item.isSelected,
                        onChanged: hasStudent
                            ? (val) {
                                setState(() => item.isSelected = val ?? false);
                              }
                            : null,
                      ),
                      const SizedBox(width: 8),

                      // Raw Input
                      SizedBox(
                        width: 140,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.rawInput,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Text(
                              'Extracted Input',
                              style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 12),

                      // Matched Student
                      Expanded(
                        child: hasStudent
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.matchedStudent!.fullName,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                                  ),
                                  Text(
                                    item.matchedStudent!.rollNumber,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.primary),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Not in roster',
                                    style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppColors.absent),
                                  ),
                                  const SizedBox(height: 2),
                                  InkWell(
                                    onTap: () => _promptAddToRoster(item),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.person_add_alt_1_rounded, size: 12, color: AppColors.primary),
                                        SizedBox(width: 3),
                                        Text(
                                          'Add to Roster',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                      ),

                      // Match Confidence Pill
                      _buildConfidenceBadge(item.confidenceBand, item.confidenceScore),
                      const SizedBox(width: 14),

                      // Status Dropdown
                      Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: _statusBgColor(item.status),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _statusColor(item.status).withValues(alpha: 0.3)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<AttendanceStatus>(
                            value: item.status,
                            items: [
                              AttendanceStatus.present,
                              AttendanceStatus.absent,
                              AttendanceStatus.late,
                              AttendanceStatus.excused,
                            ].map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                s.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _statusColor(s),
                                ),
                              ),
                            )).toList(),
                            onChanged: (newStatus) {
                              if (newStatus != null) {
                                setState(() => item.status = newStatus);
                              }
                            },
                          ),
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
    );
  }

  Widget _metricPill(String label, String value, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(fontSize: 11, color: color)),
          Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _buildConfidenceBadge(MatchConfidenceBand band, double score) {
    Color bg;
    Color fg;
    String label;

    switch (band) {
      case MatchConfidenceBand.autoAccept:
        bg = AppColors.presentLight;
        fg = AppColors.presentDark;
        label = '${(score * 100).toStringAsFixed(0)}% Match';
        break;
      case MatchConfidenceBand.review:
      case MatchConfidenceBand.confirmationRequired:
        bg = AppColors.lateLight;
        fg = AppColors.lateDark;
        label = '${(score * 100).toStringAsFixed(0)}% Review';
        break;
      case MatchConfidenceBand.unmatched:
        bg = AppColors.surfaceMuted;
        fg = AppColors.textDisabled;
        label = 'Unmatched';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _buildFooterActions(bool hasResults, int selectedCount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 12),
        if (hasResults) ...[
          ElevatedButton.icon(
            onPressed: selectedCount > 0 ? _applyBatchToSession : null,
            icon: const Icon(Icons.check_circle_rounded, size: 16),
            label: Text('Apply to Active Session ($selectedCount Students)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.present,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
        ] else ...[
          ElevatedButton.icon(
            onPressed: (_currentTab == 0 && _fileBytes != null) ||
                    (_currentTab == 1 && _textController.text.trim().isNotEmpty)
                ? _processScan
                : null,
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('Scan & Match'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
        ],
      ],
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
}
