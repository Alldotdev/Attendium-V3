import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../domain/entities/audit_log.dart';
import '../../domain/enums/audit_action.dart';
import '../providers/database_providers.dart';

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  final TextEditingController _searchController = TextEditingController();
  AuditAction? _selectedAction;
  String? _selectedEntityType;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _exportAuditCsv(List<AuditLogEntity> logs) async {
    try {
      final buffer = StringBuffer();
      buffer.writeln('ID,Timestamp,User ID,Action,Entity Type,Entity ID,Source,Reason,Before JSON,After JSON');

      for (final log in logs) {
        final time = DateFormat('yyyy-MM-dd HH:mm:ss').format(log.createdAt);
        final before = (log.beforeJson ?? '').replaceAll('"', '""');
        final after = (log.afterJson ?? '').replaceAll('"', '""');
        final reason = log.reason.replaceAll('"', '""');
        buffer.writeln('"${log.id}","$time","${log.userId}","${log.action.value}","${log.entityType}","${log.entityId}","${log.source}","$reason","$before","$after"');
      }

      final defaultName = 'Attendium_Audit_Trail_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Audit Trail CSV',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (savePath != null) {
        final file = File(savePath);
        await file.writeAsString(buffer.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Audit trail exported successfully to $savePath'),
              backgroundColor: AppColors.present,
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
    }
  }

  void _showDiffDialog(BuildContext context, AuditLogEntity log) {
    String prettyBefore = '';
    String prettyAfter = '';

    if (log.beforeJson != null) {
      try {
        final decoded = jsonDecode(log.beforeJson!);
        prettyBefore = const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {
        prettyBefore = log.beforeJson!;
      }
    }

    if (log.afterJson != null) {
      try {
        final decoded = jsonDecode(log.afterJson!);
        prettyAfter = const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {
        prettyAfter = log.afterJson!;
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _actionColor(log.action).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                log.action.value.toUpperCase(),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _actionColor(log.action)),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${log.entityType}: ${log.entityId}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: SizedBox(
          width: 700,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Timestamp: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(log.createdAt)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const Spacer(),
                  Text('Source: ${log.source}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
              if (log.reason.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Reason: ${log.reason}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ],
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Before State
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('State Before', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                        const SizedBox(height: 6),
                        Container(
                          height: 200,
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceSubtle,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: SingleChildScrollView(
                            child: Text(
                              prettyBefore.isEmpty ? '(Empty / Created)' : prettyBefore,
                              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  // After State
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('State After', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                        const SizedBox(height: 6),
                        Container(
                          height: 200,
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceSubtle,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: SingleChildScrollView(
                            child: Text(
                              prettyAfter.isEmpty ? '(Empty / Deleted)' : prettyAfter,
                              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textPrimary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Color _actionColor(AuditAction action) {
    switch (action) {
      case AuditAction.create:
        return AppColors.present;
      case AuditAction.update:
      case AuditAction.bulkUpdate:
        return AppColors.primary;
      case AuditAction.statusChange:
        return AppColors.late;
      case AuditAction.delete:
        return AppColors.absent;
      case AuditAction.importCommit:
        return Colors.teal;
      case AuditAction.restore:
        return Colors.indigo;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auditDao = ref.watch(auditDaoProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: FutureBuilder<List<AuditLogEntity>>(
        future: auditDao.getRecentLogs(limit: 250).then((r) => r.successOrNull ?? []),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allLogs = snapshot.data ?? [];

          // Filter by search query, action, and entity type
          final query = _searchController.text.toLowerCase().trim();
          final filteredLogs = allLogs.where((log) {
            if (_selectedAction != null && log.action != _selectedAction) return false;
            if (_selectedEntityType != null && log.entityType != _selectedEntityType) return false;
            if (query.isNotEmpty) {
              final matchEntity = log.entityType.toLowerCase().contains(query);
              final matchId = log.entityId.toLowerCase().contains(query);
              final matchReason = log.reason.toLowerCase().contains(query);
              final matchSource = log.source.toLowerCase().contains(query);
              if (!matchEntity && !matchId && !matchReason && !matchSource) return false;
            }
            return true;
          }).toList();

          return Column(
            children: [
              // Header Toolbar
              _buildHeader(allLogs, filteredLogs),

              // Filter Controls Bar
              _buildFilterBar(allLogs),

              // Audit Logs Table
              Expanded(
                child: filteredLogs.isEmpty
                    ? const Center(
                        child: Text(
                          'No audit logs match the specified search/filter criteria.',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      )
                    : _buildLogTable(filteredLogs),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(List<AuditLogEntity> allLogs, List<AuditLogEntity> filteredLogs) {
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
            child: const Icon(Icons.history_edu_rounded, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Immutable Audit Trail',
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
                      '${allLogs.length} Total Events',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'Comprehensive changelog recording every attendance override, manual edit, import, and backup',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Refresh'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.borderSubtle),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: filteredLogs.isEmpty ? null : () => _exportAuditCsv(filteredLogs),
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Export Audit CSV'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(List<AuditLogEntity> allLogs) {
    final entityTypes = allLogs.map((l) => l.entityType).toSet().toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          // Search input
          SizedBox(
            width: 280,
            height: 38,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search audit events...',
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
          const SizedBox(width: 14),

          // Action Filter Dropdown
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<AuditAction?>(
                value: _selectedAction,
                hint: const Text('All Actions', style: TextStyle(fontSize: 12)),
                items: [
                  const DropdownMenuItem<AuditAction?>(value: null, child: Text('All Actions', style: TextStyle(fontSize: 12))),
                  ...AuditAction.values.map((a) {
                    return DropdownMenuItem(
                      value: a,
                      child: Row(
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: _actionColor(a), shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text(a.value.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  }),
                ],
                onChanged: (val) => setState(() => _selectedAction = val),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Entity Type Filter Dropdown
          if (entityTypes.isNotEmpty)
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedEntityType,
                  hint: const Text('All Entities', style: TextStyle(fontSize: 12)),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All Entities', style: TextStyle(fontSize: 12))),
                    ...entityTypes.map((t) {
                      return DropdownMenuItem(
                        value: t,
                        child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      );
                    }),
                  ],
                  onChanged: (val) => setState(() => _selectedEntityType = val),
                ),
              ),
            ),

          const Spacer(),
          if (_selectedAction != null || _selectedEntityType != null || _searchController.text.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedAction = null;
                  _selectedEntityType = null;
                  _searchController.clear();
                });
              },
              icon: const Icon(Icons.clear, size: 16),
              label: const Text('Reset Filters'),
            ),
        ],
      ),
    );
  }

  Widget _buildLogTable(List<AuditLogEntity> logs) {
    return Container(
      margin: const EdgeInsets.all(24),
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
                SizedBox(width: 150, child: Text('Timestamp', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                SizedBox(width: 100, child: Text('Action', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                SizedBox(width: 130, child: Text('Entity Type', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                Expanded(flex: 2, child: Text('Entity ID', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                SizedBox(width: 100, child: Text('Source', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                Expanded(flex: 3, child: Text('Notes / Reason', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                SizedBox(width: 70, child: Text('Diff', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
              ],
            ),
          ),

          // Table Rows
          Expanded(
            child: ListView.separated(
              itemCount: logs.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final log = logs[index];
                final color = _actionColor(log.action);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 150,
                        child: Text(
                          DateFormat('yyyy-MM-dd HH:mm:ss').format(log.createdAt),
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppColors.textSecondary),
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                log.action.value.toUpperCase(),
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 130,
                        child: Text(
                          log.entityType,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          log.entityId,
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppColors.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        child: Text(
                          log.source,
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          log.reason.isNotEmpty ? log.reason : '—',
                          style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 70,
                        child: Center(
                          child: (log.beforeJson != null || log.afterJson != null)
                              ? IconButton(
                                  icon: const Icon(Icons.visibility_outlined, size: 18, color: AppColors.primary),
                                  tooltip: 'Inspect JSON Payload Diff',
                                  onPressed: () => _showDiffDialog(context, log),
                                )
                              : const Text('—', style: TextStyle(color: AppColors.textDisabled)),
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
