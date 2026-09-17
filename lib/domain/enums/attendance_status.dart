/// Attendance status for a student in a session.
enum AttendanceStatus {
  present('present', 'P', 'Present'),
  absent('absent', 'A', 'Absent'),
  late('late', 'L', 'Late'),
  excused('excused', 'E', 'Excused'),
  unmarked('unmarked', 'U', 'Unmarked');

  final String value;
  final String code;
  final String label;

  const AttendanceStatus(this.value, this.code, this.label);

  static AttendanceStatus fromString(String? val) {
    if (val == null) return AttendanceStatus.unmarked;
    final clean = val.trim().toLowerCase();
    switch (clean) {
      case 'p':
      case 'present':
      case '1':
      case 'yes':
        return AttendanceStatus.present;
      case 'a':
      case 'absent':
      case '0':
      case 'no':
        return AttendanceStatus.absent;
      case 'l':
      case 'late':
        return AttendanceStatus.late;
      case 'e':
      case 'excused':
      case 'leave':
        return AttendanceStatus.excused;
      case 'u':
      case 'unmarked':
      default:
        return AttendanceStatus.unmarked;
    }
  }

  /// Calculates credit points earned based on status and custom late weight.
  double creditPoints({double lateWeight = 0.5}) {
    switch (this) {
      case AttendanceStatus.present:
        return 1.0;
      case AttendanceStatus.late:
        return lateWeight;
      case AttendanceStatus.excused:
        return 0.0; // In standard counting, excused is excluded from denominator or given 0 credit
      case AttendanceStatus.absent:
      case AttendanceStatus.unmarked:
        return 0.0;
    }
  }
}
