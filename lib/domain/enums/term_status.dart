/// Academic term status.
enum TermStatus {
  active('active', 'Active'),
  archived('archived', 'Archived');

  final String value;
  final String label;

  const TermStatus(this.value, this.label);

  static TermStatus fromString(String? val) {
    if (val == null) return TermStatus.active;
    return val.toLowerCase() == 'archived' ? TermStatus.archived : TermStatus.active;
  }
}
