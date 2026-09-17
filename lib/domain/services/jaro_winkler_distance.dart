import 'dart:math';

/// Calculates Jaro and Jaro-Winkler string similarity scores in [0.0, 1.0].
class JaroWinklerDistance {
  const JaroWinklerDistance._();

  static const double defaultScalingFactor = 0.1;
  static const int maxPrefixLength = 4;

  /// Calculates the Jaro similarity score.
  static double jaroSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final int len1 = s1.length;
    final int len2 = s2.length;
    final int matchWindow = max(0, (max(len1, len2) ~/ 2) - 1);

    final List<bool> s1Matched = List<bool>.filled(len1, false);
    final List<bool> s2Matched = List<bool>.filled(len2, false);

    int matches = 0;

    // Find matches
    for (int i = 0; i < len1; i++) {
      final int start = max(0, i - matchWindow);
      final int end = min(len2 - 1, i + matchWindow);

      for (int j = start; j <= end; j++) {
        if (!s2Matched[j] && s1.codeUnitAt(i) == s2.codeUnitAt(j)) {
          s1Matched[i] = true;
          s2Matched[j] = true;
          matches++;
          break;
        }
      }
    }

    if (matches == 0) return 0.0;

    // Count transpositions
    int transpositions = 0;
    int k = 0;
    for (int i = 0; i < len1; i++) {
      if (!s1Matched[i]) continue;
      while (!s2Matched[k]) {
        k++;
      }
      if (s1.codeUnitAt(i) != s2.codeUnitAt(k)) {
        transpositions++;
      }
      k++;
    }

    final double halfTranspositions = transpositions / 2.0;

    return (
      (matches / len1) +
      (matches / len2) +
      ((matches - halfTranspositions) / matches)
    ) / 3.0;
  }

  /// Calculates Jaro-Winkler similarity with prefix bonus.
  static double similarity(
    String s1,
    String s2, {
    double scalingFactor = defaultScalingFactor,
  }) {
    final double jaro = jaroSimilarity(s1, s2);
    if (jaro < 0.7) return jaro;

    // Common prefix length up to maxPrefixLength
    int prefix = 0;
    final int minLen = min(min(s1.length, s2.length), maxPrefixLength);
    for (int i = 0; i < minLen; i++) {
      if (s1.codeUnitAt(i) == s2.codeUnitAt(i)) {
        prefix++;
      } else {
        break;
      }
    }

    final double jaroWinkler = jaro + (prefix * scalingFactor * (1.0 - jaro));
    return jaroWinkler.clamp(0.0, 1.0);
  }
}
