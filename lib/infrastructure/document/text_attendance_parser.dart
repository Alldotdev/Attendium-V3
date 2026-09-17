import '../../domain/enums/attendance_status.dart';

/// Represents a single parsed entry extracted from raw text, paste, or list.
class ExtractedAttendanceEntry {
  final int index;
  final String? roll;
  final String? name;
  final AttendanceStatus status;
  final String originalText;

  const ExtractedAttendanceEntry({
    required this.index,
    this.roll,
    this.name,
    required this.status,
    required this.originalText,
  });
}

/// Intelligent parser for raw text, clipboard snippets, or comma-separated roll lists.
class TextAttendanceParser {
  const TextAttendanceParser._();

  /// Parses arbitrary text into structured attendance entries.
  /// [defaultStatus] is used when an entry does not explicitly specify attendance status.
  static List<ExtractedAttendanceEntry> parse(
    String input, {
    AttendanceStatus defaultStatus = AttendanceStatus.present,
  }) {
    final cleanInput = input.trim();
    if (cleanInput.isEmpty) return [];

    // Split by newlines or commas/semicolons if single line
    List<String> rawTokens;
    if (cleanInput.contains('\n')) {
      rawTokens = cleanInput
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (cleanInput.contains(',') || cleanInput.contains(';')) {
      rawTokens = cleanInput
          .split(RegExp(r'[,;]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else {
      // Single line space-separated if multiple items, or just one item
      rawTokens = [cleanInput];
    }

    final entries = <ExtractedAttendanceEntry>[];
    int index = 1;

    for (final token in rawTokens) {
      // Check if line is just a header (e.g. "Roll, Name, Status")
      final lower = token.toLowerCase();
      if (lower == 'roll' || lower == 'name' || lower == 'attendance' || lower.contains('roll number')) {
        continue;
      }

      final parsed = _parseSingleToken(token, index, defaultStatus);
      if (parsed != null) {
        entries.add(parsed);
        index++;
      }
    }

    return entries;
  }

  static ExtractedAttendanceEntry? _parseSingleToken(
    String text,
    int index,
    AttendanceStatus defaultStatus,
  ) {
    var working = text.trim();
    if (working.isEmpty) return null;

    // Strip leading bullet markers, dashes, or numbered lists (e.g. "- 552" -> "552", "1. 552" -> "552", "• 552" -> "552")
    working = working.replaceAll(RegExp(r'^([-\*•]|\d+[\.\)])\s*'), '').trim();
    if (working.isEmpty) return null;

    AttendanceStatus resolvedStatus = defaultStatus;

    // 1. Detect and strip status from the end or beginning
    // Match common status tokens: P, A, L, E, Present, Absent, Late, Excused
    final words = working.split(RegExp(r'\s+'));
    if (words.length > 1) {
      final lastWord = words.last.toLowerCase();
      final statusFromLast = _parseStatus(lastWord);
      if (statusFromLast != null) {
        resolvedStatus = statusFromLast;
        working = words.sublist(0, words.length - 1).join(' ').trim();
      } else {
        // Check if first word is status (e.g. "P 588" or "Present 588")
        final firstWord = words.first.toLowerCase();
        final statusFromFirst = _parseStatus(firstWord);
        if (statusFromFirst != null) {
          resolvedStatus = statusFromFirst;
          working = words.sublist(1).join(' ').trim();
        }
      }
    }

    // Clean any trailing or leading separators
    working = working.replaceAll(RegExp(r'^[-\:\,\.\s]+|[-\:\,\.\s]+$'), '').trim();

    String? roll;
    String? name;

    // 2. Determine if remaining text has both roll and name or just one
    // Look for roll pattern (tokens with digits)
    final tokens = working.split(RegExp(r'\s+'));
    if (tokens.length >= 2) {
      // Check if first token contains digits (e.g. "F24-588 Alex Mercer" or "588 John Smith")
      if (RegExp(r'\d').hasMatch(tokens.first)) {
        roll = tokens.first;
        name = tokens.sublist(1).join(' ').trim();
      } else if (RegExp(r'\d').hasMatch(tokens.last)) {
        // e.g. "Alex Mercer 588"
        roll = tokens.last;
        name = tokens.sublist(0, tokens.length - 1).join(' ').trim();
      } else {
        // All words are letters -> full name
        name = working;
      }
    } else {
      // Single token
      if (RegExp(r'\d').hasMatch(working)) {
        roll = working;
      } else {
        name = working;
      }
    }

    return ExtractedAttendanceEntry(
      index: index,
      roll: roll,
      name: name,
      status: resolvedStatus,
      originalText: text,
    );
  }

  static AttendanceStatus? _parseStatus(String word) {
    switch (word) {
      case 'p':
      case 'present':
      case 'prsnt':
      case '+':
      case 'yes':
      case 'y':
        return AttendanceStatus.present;
      case 'a':
      case 'absent':
      case 'abs':
      case 'no':
      case 'n':
        return AttendanceStatus.absent;
      case 'l':
      case 'late':
        return AttendanceStatus.late;
      case 'e':
      case 'excused':
      case 'exc':
        return AttendanceStatus.excused;
      case 'u':
      case 'unmarked':
        return AttendanceStatus.unmarked;
      default:
        return null;
    }
  }
}
