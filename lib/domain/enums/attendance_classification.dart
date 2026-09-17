/// Student attendance standing classification based on course threshold.
enum AttendanceClassification {
  safe('safe', 'Safe', 'Attendance meets or exceeds requirements'),
  atRisk('at_risk', 'At Risk', 'Attendance is approaching short threshold'),
  short('short', 'Short Attendance', 'Below minimum attendance requirement'),
  debarred('debarred', 'Debarred', 'Debarred from examinations due to critical shortage');

  final String value;
  final String label;
  final String description;

  const AttendanceClassification(this.value, this.label, this.description);

  static AttendanceClassification fromPercentage({
    required double percentage,
    required double minimumThreshold,
    double atRiskDelta = 10.0,
    double debarThreshold = 50.0,
  }) {
    if (percentage >= minimumThreshold) {
      return AttendanceClassification.safe;
    } else if (percentage >= (minimumThreshold - atRiskDelta) && percentage > debarThreshold) {
      return AttendanceClassification.atRisk;
    } else if (percentage >= debarThreshold) {
      return AttendanceClassification.short;
    } else {
      return AttendanceClassification.debarred;
    }
  }
}
