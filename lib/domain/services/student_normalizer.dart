/// Normalization utilities for student names, roll numbers, and aliases.
class StudentNormalizer {
  const StudentNormalizer._();

  /// Normalizes a human name:
  /// - Lowercase
  /// - Strips diacritics and non-letter/space punctuation
  /// - Collapses multiple spaces
  /// - Trims leading and trailing whitespace
  static String normalizeName(String name) {
    if (name.isEmpty) return '';

    // Convert to lowercase
    String result = name.toLowerCase();

    // Replace common diacritics / accented characters
    result = _stripDiacritics(result);

    // Replace non-alphanumeric (except space) with space
    result = result.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');

    // Collapse multiple whitespace
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();

    return result;
  }

  /// Normalizes a student roll number / registration identifier:
  /// - Uppercase
  /// - Removes hyphens, spaces, dots, slashes
  /// - Applies OCR substitution heuristics (O -> 0, I/l -> 1, S -> 5, B -> 8) when in digit contexts
  static String normalizeRoll(String roll, {bool applyOcrFixes = true}) {
    if (roll.isEmpty) return '';

    String cleaned = roll.toUpperCase();
    // Remove formatting separators
    cleaned = cleaned.replaceAll(RegExp(r'[\s\-_./:\\]'), '');

    if (applyOcrFixes) {
      cleaned = _applyRollOcrHeuristics(cleaned);
    }

    return cleaned;
  }

  /// Applies OCR corrections specifically for numeric suffixes in roll numbers.
  static String _applyRollOcrHeuristics(String input) {
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final char = input[i];
      // Only apply substitutions if we are already in the numeric portion of the roll
      // (preceded by a digit) or strictly flanked by digits.
      final hasPrevDigit = i > 0 && _isDigit(input[i - 1]);
      final hasNextDigit = i < input.length - 1 && _isDigit(input[i + 1]);
      final isDigitContext = hasPrevDigit || (hasNextDigit && i >= 2 && _isDigit(input[i + 1]));

      if (isDigitContext) {
        if (char == 'O' || char == 'Q') {
          buffer.write('0');
        } else if (char == 'I' || char == 'L') {
          buffer.write('1');
        } else if (char == 'S') {
          buffer.write('5');
        } else if (char == 'B') {
          buffer.write('8');
        } else {
          buffer.write(char);
        }
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  static bool _isDigit(String char) {
    if (char.isEmpty) return false;
    final code = char.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  /// Strips standard Latin diacritics without external dependencies.
  static String _stripDiacritics(String text) {
    const withDia = 'àáâãäåāæçèéêëēìíîïīðñòóôõöøōùúûüūýÿœ';
    const withoutDia = 'aaaaaaaceeeeeiiiiidnooooooouuuuuyyo';

    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      final index = withDia.indexOf(char);
      if (index >= 0) {
        buffer.write(withoutDia[index]);
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }
}
