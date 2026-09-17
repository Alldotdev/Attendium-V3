/// Audit log action types.
enum AuditAction {
  create('create', 'Record Created'),
  update('update', 'Record Updated'),
  delete('delete', 'Record Deleted'),
  statusChange('status_change', 'Attendance Status Changed'),
  bulkUpdate('bulk_update', 'Bulk Attendance Applied'),
  importCommit('import_commit', 'Imported Document Committed'),
  restore('restore', 'Backup Restored');

  final String value;
  final String label;

  const AuditAction(this.value, this.label);

  static AuditAction fromString(String? val) {
    if (val == null) return AuditAction.update;
    return AuditAction.values.firstWhere(
      (e) => e.value == val.toLowerCase(),
      orElse: () => AuditAction.update,
    );
  }
}
