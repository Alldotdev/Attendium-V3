/// Academic session types.
enum SessionType {
  lecture('lecture', 'Lecture', 1.0),
  lab('lab', 'Lab / Practical', 2.0),
  tutorial('tutorial', 'Tutorial', 1.0),
  seminar('seminar', 'Seminar', 1.0),
  practical('practical', 'Practical', 2.0),
  other('other', 'Other', 1.0);

  final String value;
  final String label;
  final double defaultCreditWeight;

  const SessionType(this.value, this.label, this.defaultCreditWeight);

  static SessionType fromString(String? val) {
    if (val == null) return SessionType.lecture;
    final clean = val.trim().toLowerCase();
    return SessionType.values.firstWhere(
      (e) => e.value == clean,
      orElse: () => SessionType.lecture,
    );
  }
}
