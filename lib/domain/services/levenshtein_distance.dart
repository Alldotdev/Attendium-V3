import 'dart:math';

/// Calculates exact Levenshtein edit distance and normalized similarity.
class LevenshteinDistance {
  const LevenshteinDistance._();

  /// Computes the raw minimum edit operations (insertions, deletions, substitutions).
  static int distance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;

      for (int j = 0; j < s2.length; j++) {
        int cost = (s1.codeUnitAt(i) == s2.codeUnitAt(j)) ? 0 : 1;
        v1[j + 1] = min(
          v1[j] + 1, // insertion
          min(
            v0[j + 1] + 1, // deletion
            v0[j] + cost, // substitution
          ),
        );
      }

      for (int j = 0; j <= s2.length; j++) {
        v0[j] = v1[j];
      }
    }

    return v1[s2.length];
  }

  /// Computes normalized similarity in range [0.0, 1.0] where 1.0 indicates identical strings.
  static double similarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    int maxLen = max(s1.length, s2.length);
    if (maxLen == 0) return 1.0;
    int d = distance(s1, s2);
    return (1.0 - (d / maxLen)).clamp(0.0, 1.0);
  }
}
