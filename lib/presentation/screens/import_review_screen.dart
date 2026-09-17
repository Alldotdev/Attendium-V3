import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../domain/entities/course_session.dart';
import '../../domain/entities/extraction_row.dart';
import '../../domain/entities/student.dart';
import '../../domain/enums/import_status.dart';
import '../../domain/enums/session_type.dart';
import '../providers/classroom_providers.dart';
import '../providers/database_providers.dart';
import '../providers/import_provider.dart';

class ImportReviewScreen extends ConsumerStatefulWidget {
  const ImportReviewScreen({super.key});

  @override
  ConsumerState<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

class _ImportReviewScreenState extends ConsumerState<ImportReviewScreen> {
  String _filterBand = 'ALL'; // ALL, AUTO, REVIEW, UNMATCHED
  String? _selectedSessionId;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickFile(String classroomId) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls', 'pdf', 'png', 'jpg', 'jpeg'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final bytes = file.bytes;
        if (bytes != null) {
          final ext = file.extension?.toLowerCase() ?? 'csv';
          String mimeType = 'text/csv';
          if (ext == 'xlsx' || ext == 'xls') {
            mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
          } else if (ext == 'pdf') {
            mimeType = 'application/pdf';
          } else if (ext == 'png') {
            mimeType = 'image/png';
          } else if (ext == 'jpg' || ext == 'jpeg') {
            mimeType = 'image/jpeg';
          }

          await ref.read(importProvider.notifier).ingestDocument(
                bytes: bytes,
                filename: file.name,
                mimeType: mimeType,
                classroomId: classroomId,
              );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File selection error: $e'), backgroundColor: AppColors.absent),
        );
      }
    }
  }

  void _loadSampleData(String classroomId, List<StudentEntity> roster) {
    // Generate sample attendance CSV for quick demonstration / testing
    final buffer = StringBuffer();
    buffer.writeln('Roll Number,Student Name,Status,Visual Confidence');
    for (int i = 0; i < roster.length; i++) {
      final s = roster[i];
      final status = i % 5 == 0 ? 'A' : (i % 7 == 0 ? 'L' : 'P');
      // Intentionally introduce minor OCR noise in 1 or 2 names/rolls for matching demo
      final roll = i == 2 ? s.rollNumber.replaceAll('0', 'O') : s.rollNumber;
      final name = i == 3 ? s.fullName.toLowerCase() : s.fullName;
      buffer.writeln('$roll,$name,$status,0.98');
    }
    // Add one external student
    buffer.writeln('CS-999,Unknown Extracted Guest,P,0.85');

    final bytes = buffer.toString().codeUnits;
    ref.read(importProvider.notifier).ingestDocument(
          bytes: Uint8List.fromList(bytes),
          filename: 'Sample_Roster_Attendance.csv',
          mimeType: 'text/csv',
          classroomId: classroomId,
        );
  }

  @override
  Widget build(BuildContext context) {
    final activeClassroomAsync = ref.watch(activeClassroomProvider);
    final rosterAsync = ref.watch(rosterProvider);
    final sessionsAsync = ref.watch(sessionsProvider);
    final importState = ref.watch(importProvider);

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
                if (_selectedSessionId == null && sessions.isNotEmpty) {
                  _selectedSessionId = sessions.first.id;
                }

                return Scaffold(
                  backgroundColor: AppColors.canvas,
                  body: Column(
                    children: [
                      // Header Toolbar
                      _buildHeaderToolbar(context, classroom, roster, sessions, importState),

                      // Warning Banner if duplicate document detected
                      if (importState.duplicateWarning != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                          color: AppColors.lateBg,
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: AppColors.late, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  importState.duplicateWarning!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.late,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Main Split Workbench
                      Expanded(
                        child: importState.rows.isEmpty && !importState.isProcessing
                            ? _buildEmptyState(context, classroom.id, roster)
                            : Row(
                                children: [
                                  // Left Side: Ingested File Source Inspector
                                  Container(
                                    width: 340,
                                    decoration: const BoxDecoration(
                                      color: AppColors.surface,
                                      border: Border(right: BorderSide(color: AppColors.borderSubtle)),
                                    ),
                                    child: _buildDocumentSourcePanel(context, importState, classroom.id, roster),
                                  ),

                                  // Right Side: Verification Workbench Grid
                                  Expanded(
                                    child: _buildVerificationWorkbench(
                                      context,
                                      importState,
                                      roster,
                                      sessions,
                                      classroom.id,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
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
      error: (err, _) => Center(child: Text('Error loading active classroom: $err')),
    );
  }

  Widget _buildHeaderToolbar(
    BuildContext context,
    dynamic classroom,
    List<StudentEntity> roster,
    List<CourseSessionEntity> sessions,
    ImportState importState,
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
            child: const Icon(Icons.document_scanner, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Multimodal Import & Verification',
                    style: TextStyle(
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
                      '${classroom.courseCode} (${classroom.section})',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'AI-assisted extraction with authoritative local deterministic fuzzy verification',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
          const Spacer(),
          // Action Buttons
          OutlinedButton.icon(
            onPressed: () => _loadSampleData(classroom.id, roster),
            icon: const Icon(Icons.dataset_outlined, size: 16),
            label: const Text('Load Sample Roster'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.borderSubtle),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: () => _pickFile(classroom.id),
            icon: const Icon(Icons.upload_file, size: 16),
            label: const Text('Upload Document (CSV/XLSX/PDF/IMG)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String classroomId, List<StudentEntity> roster) {
    return Center(
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderSubtle),
          boxShadow: const [
            BoxShadow(color: Color(0x05000000), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_upload_outlined, color: AppColors.primary, size: 32),
            ),
            const SizedBox(height: 20),
            const Text(
              'Ingest Attendance Document',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Upload CSV, Excel sheet, scanned attendance sheet photo (PNG/JPG), or PDF report. Attendium validates schema and matches with the roster deterministically.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _loadSampleData(classroomId, roster),
                  icon: const Icon(Icons.play_arrow_outlined, size: 16),
                  label: const Text('Try with Demo CSV'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _pickFile(classroomId),
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('Browse Files'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentSourcePanel(
    BuildContext context,
    ImportState importState,
    String classroomId,
    List<StudentEntity> roster,
  ) {
    final job = importState.currentJob;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Icon(Icons.description_outlined, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text(
              'Document Manifest',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const Spacer(),
            if (importState.isProcessing)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 16),

        _buildManifestItem('Filename', importState.filename ?? 'Unknown Document'),
        _buildManifestItem('MIME Type', job?.mimeType ?? 'text/csv'),
        _buildManifestItem('Source Type', job?.sourceType.toUpperCase() ?? 'TABULAR'),
        _buildManifestItem(
          'SHA-256 Hash',
          job?.fileHash ?? 'Not computed',
          isCode: true,
        ),
        _buildManifestItem(
          'Extraction Status',
          job?.processingStatus.name.toUpperCase() ?? 'PENDING',
          badgeColor: AppColors.present,
        ),
        const SizedBox(height: 20),

        const Divider(),
        const SizedBox(height: 12),
        const Text(
          'Verification Rules',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        _buildRuleItem('Roll Weight', '40% authoritative roll match'),
        _buildRuleItem('Name Weight', '35% Jaro-Winkler distance'),
        _buildRuleItem('Alias Weight', '15% student aliases table'),
        _buildRuleItem('Class Context', '10% active roster enrollment'),
        _buildRuleItem('Auto-Accept Band', 'Score >= 0.95'),
        _buildRuleItem('Review Band', '0.70 <= Score < 0.95'),

        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => _pickFile(classroomId),
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Re-upload / Replace File'),
        ),
      ],
    );
  }

  Widget _buildManifestItem(String label, String value, {bool isCode = false, Color? badgeColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
          const SizedBox(height: 2),
          if (badgeColor != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                value,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: badgeColor),
              ),
            )
          else
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                fontFamily: isCode ? 'monospace' : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Widget _buildRuleItem(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900)),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                children: [
                  TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  TextSpan(text: desc),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationWorkbench(
    BuildContext context,
    ImportState importState,
    List<StudentEntity> roster,
    List<CourseSessionEntity> sessions,
    String classroomId,
  ) {
    final rows = importState.rows;
    final total = rows.length;
    final matched = importState.matchedCount;
    final reviewReq = importState.reviewRequiredCount;
    final unmatched = importState.unmatchedCount;

    // Filter rows based on selected filterBand
    final filteredRows = rows.where((r) {
      if (_filterBand == 'AUTO') return r.reviewState == RowReviewState.matched;
      if (_filterBand == 'REVIEW') return r.reviewState == RowReviewState.reviewRequired;
      if (_filterBand == 'UNMATCHED') return r.reviewState == RowReviewState.unmatched;
      return true;
    }).toList();

    return Column(
      children: [
        // Summary Metrics Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
          ),
          child: Row(
            children: [
              _metricPill('Total Extracted', '$total', AppColors.textPrimary, 'ALL'),
              const SizedBox(width: 8),
              _metricPill('Auto-Accepted', '$matched', AppColors.present, 'AUTO'),
              const SizedBox(width: 8),
              _metricPill('Review Required', '$reviewReq', AppColors.late, 'REVIEW'),
              const SizedBox(width: 8),
              _metricPill('Unmatched', '$unmatched', AppColors.absent, 'UNMATCHED'),
              const Spacer(),
              if (reviewReq > 0)
                ElevatedButton.icon(
                  onPressed: () {
                    ref.read(importProvider.notifier).bulkApproveSafe();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Auto-approved safe matches (Score >= 0.95)')),
                    );
                  },
                  icon: const Icon(Icons.done_all, size: 16),
                  label: const Text('Approve Safe Matches (>= 0.95)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryLight,
                    foregroundColor: AppColors.primary,
                    elevation: 0,
                  ),
                ),
            ],
          ),
        ),

        // Extraction Rows Table
        Expanded(
          child: filteredRows.isEmpty
              ? const Center(child: Text('No extraction rows match the current filter.', style: TextStyle(color: AppColors.textMuted)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredRows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final row = filteredRows[index];
                    return _buildExtractionRowCard(context, row, roster);
                  },
                ),
        ),

        // Bottom Commit Action Bar
        _buildBottomCommitBar(context, importState, sessions, classroomId),
      ],
    );
  }

  Widget _metricPill(String label, String count, Color color, String filterKey) {
    final isSelected = _filterBand == filterKey;
    return InkWell(
      onTap: () => setState(() => _filterBand = filterKey),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : AppColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? color : AppColors.borderSubtle),
        ),
        child: Row(
          children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isSelected ? color : AppColors.textSecondary)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(count, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExtractionRowCard(
    BuildContext context,
    ExtractionRowEntity row,
    List<StudentEntity> roster,
  ) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (row.reviewState == RowReviewState.matched) {
      statusColor = AppColors.present;
      statusLabel = 'MATCHED (${(row.matchScore * 100).toInt()}%)';
      statusIcon = Icons.check_circle_rounded;
    } else if (row.reviewState == RowReviewState.reviewRequired) {
      statusColor = AppColors.late;
      statusLabel = 'REVIEW (${(row.matchScore * 100).toInt()}%)';
      statusIcon = Icons.warning_amber_rounded;
    } else if (row.reviewState == RowReviewState.committed) {
      statusColor = AppColors.primary;
      statusLabel = 'COMMITTED';
      statusIcon = Icons.verified_rounded;
    } else {
      statusColor = AppColors.absent;
      statusLabel = 'UNMATCHED';
      statusIcon = Icons.error_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: row.reviewState == RowReviewState.reviewRequired
              ? AppColors.late.withValues(alpha: 0.5)
              : AppColors.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          // Row Index
          SizedBox(
            width: 32,
            child: Text(
              '#${row.rowIndex}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted),
            ),
          ),

          // Raw Extracted Information
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        row.rawRoll ?? 'No Roll',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        row.rawName ?? 'Unknown Name',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (row.evidenceJson != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Text(
                      'Evidence: ${row.evidenceJson}',
                      style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),

          // Raw Extracted Status Toggle (P/A/L/E)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _statusBgColor(row.rawAttendance),
              borderRadius: BorderRadius.circular(6),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: (row.rawAttendance ?? 'P').toUpperCase(),
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 'P', child: Text('Present (P)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.present))),
                  DropdownMenuItem(value: 'A', child: Text('Absent (A)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.absent))),
                  DropdownMenuItem(value: 'L', child: Text('Late (L)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.late))),
                  DropdownMenuItem(value: 'E', child: Text('Excused (E)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.excused))),
                ],
                onChanged: (val) {
                  if (val != null) {
                    ref.read(importProvider.notifier).updateRowDecision(
                          rowId: row.id,
                          newState: row.reviewState,
                          attendanceStatus: val,
                        );
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Confidence & Review Status Badge
          Container(
            width: 130,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(statusIcon, size: 14, color: statusColor),
                const SizedBox(width: 4),
                Text(
                  statusLabel,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // Matched Student Candidate Dropdown (Authoritative mapping)
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: row.matchedStudentId,
                  hint: const Text('Select matching student...', style: TextStyle(fontSize: 12)),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('— Unmatched / External —', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ),
                    ...roster.map((s) {
                      return DropdownMenuItem<String>(
                        value: s.id,
                        child: Text(
                          '${s.rollNumber} - ${s.fullName}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }),
                  ],
                  onChanged: (studentId) {
                    ref.read(importProvider.notifier).updateRowDecision(
                          rowId: row.id,
                          newState: studentId != null ? RowReviewState.matched : RowReviewState.unmatched,
                          assignedStudentId: studentId,
                        );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Quick Action Icons
          IconButton(
            tooltip: 'Approve match',
            icon: const Icon(Icons.check, size: 18, color: AppColors.present),
            onPressed: () {
              ref.read(importProvider.notifier).updateRowDecision(
                    rowId: row.id,
                    newState: RowReviewState.matched,
                  );
            },
          ),
          IconButton(
            tooltip: 'Reject match',
            icon: const Icon(Icons.close, size: 18, color: AppColors.absent),
            onPressed: () {
              ref.read(importProvider.notifier).updateRowDecision(
                    rowId: row.id,
                    newState: RowReviewState.rejected,
                  );
            },
          ),
        ],
      ),
    );
  }

  Color _statusBgColor(String? status) {
    switch ((status ?? 'P').toUpperCase()) {
      case 'P':
        return AppColors.presentBg;
      case 'A':
        return AppColors.absentBg;
      case 'L':
        return AppColors.lateBg;
      case 'E':
        return AppColors.excusedBg;
      default:
        return AppColors.surfaceSubtle;
    }
  }

  Widget _buildBottomCommitBar(
    BuildContext context,
    ImportState importState,
    List<CourseSessionEntity> sessions,
    String classroomId,
  ) {
    final matchedCount = importState.matchedCount;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          const Text(
            'Target Session for Commit:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 12),
          Container(
            width: 260,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedSessionId,
                hint: const Text('Choose session...', style: TextStyle(fontSize: 12)),
                items: sessions.map((s) {
                  return DropdownMenuItem(
                    value: s.id,
                    child: Text(
                      '${s.sessionDate} - ${s.topic ?? 'Session'}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedSessionId = val),
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: () => _showCreateSessionModal(context, classroomId),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New Session'),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: matchedCount == 0 || _selectedSessionId == null || importState.isProcessing
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await ref.read(importProvider.notifier).commitToAttendance(
                          sessionId: _selectedSessionId!,
                          classroomId: classroomId,
                        );
                    if (ok && mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Successfully committed $matchedCount attendance records to SQLite!'),
                          backgroundColor: AppColors.present,
                        ),
                      );
                    }
                  },
            icon: importState.isProcessing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.cloud_done_rounded, size: 18),
            label: Text('Commit $matchedCount Verified Records to SQLite'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateSessionModal(BuildContext context, String classroomId) {
    final titleCtrl = TextEditingController(text: 'Imported Session');
    DateTime date = DateTime.now();
    SessionType type = SessionType.lecture;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Create New Session', style: TextStyle(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Session Title', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: Text('Date: ${DateFormat('yyyy-MM-dd').format(date)}'),
                  trailing: TextButton(
                    child: const Text('Change'),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setDialogState(() => date = picked);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<SessionType>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Session Type', border: OutlineInputBorder()),
                  items: SessionType.values.map((t) {
                    return DropdownMenuItem(value: t, child: Text(t.name.toUpperCase()));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => type = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final sessionDao = ref.read(sessionDaoProvider);
                final newId = 'sess_${DateTime.now().millisecondsSinceEpoch}';
                final newSession = CourseSessionEntity(
                  id: newId,
                  classroomId: classroomId,
                  sessionDate: DateFormat('yyyy-MM-dd').format(date),
                  topic: titleCtrl.text.trim(),
                  sessionType: type,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );
                await sessionDao.createSession(newSession);
                ref.invalidate(sessionsProvider);
                setState(() => _selectedSessionId = newId);
                if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
              },
              child: const Text('Create Session'),
            ),
          ],
        ),
      ),
    );
  }
}
