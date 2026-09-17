import 'dart:math';
import '../../core/constants/app_constants.dart';
import '../enums/match_confidence_band.dart';
import 'jaro_winkler_distance.dart';
import 'levenshtein_distance.dart';
import 'student_normalizer.dart';

/// Candidate student representation used for matching.
class StudentMatchCandidate {
  final String id;
  final String rollNumber;
  final String fullName;
  final String normalizedName;
  final List<String> aliases;
  final bool isEnrolledInClassroom;

  const StudentMatchCandidate({
    required this.id,
    required this.rollNumber,
    required this.fullName,
    required this.normalizedName,
    this.aliases = const [],
    this.isEnrolledInClassroom = true,
  });
}

/// Detailed match result for an extracted record against a student candidate.
class MatchResult {
  final StudentMatchCandidate? candidate;
  final double rollScore;
  final double nameScore;
  final double aliasScore;
  final double contextScore;
  final double finalScore;
  final MatchConfidenceBand band;
  final String explanation;

  const MatchResult({
    this.candidate,
    required this.rollScore,
    required this.nameScore,
    required this.aliasScore,
    required this.contextScore,
    required this.finalScore,
    required this.band,
    required this.explanation,
  });

  bool get isMatched => band != MatchConfidenceBand.unmatched;
}

/// Deterministic composite fuzzy student matching engine.
class FuzzyMatcher {
  final double weightRoll;
  final double weightName;
  final double weightAlias;
  final double weightContext;

  const FuzzyMatcher({
    this.weightRoll = AppConstants.fuzzyWeightRoll,
    this.weightName = AppConstants.fuzzyWeightName,
    this.weightAlias = AppConstants.fuzzyWeightAlias,
    this.weightContext = AppConstants.fuzzyWeightContext,
  });

  /// Evaluates an extracted roll and name against a list of student candidates.
  /// Returns candidates sorted descending by finalScore.
  List<MatchResult> match({
    required String? rawRoll,
    required String? rawName,
    required List<StudentMatchCandidate> candidates,
  }) {
    if (candidates.isEmpty) {
      return [];
    }

    final cleanRoll = rawRoll != null ? StudentNormalizer.normalizeRoll(rawRoll) : '';
    final cleanName = rawName != null ? StudentNormalizer.normalizeName(rawName) : '';

    final hasRoll = cleanRoll.isNotEmpty;
    final hasName = cleanName.isNotEmpty;
    final results = <MatchResult>[];

    for (final candidate in candidates) {
      final rollScore = _calculateRollScore(cleanRoll, candidate.rollNumber);
      final rawNameScore = _calculateNameScore(cleanName, candidate.normalizedName);
      final aliasScore = _calculateAliasScore(cleanName, candidate.aliases);
      final nameScore = max(rawNameScore, aliasScore);
      final contextScore = candidate.isEnrolledInClassroom ? 1.0 : 0.0;

      // Adaptive scoring formula: handles roll-only, name-only, or combined
      double finalScore;
      if (hasRoll && hasName) {
        finalScore = (weightRoll * rollScore) +
            (weightName * nameScore) +
            (weightAlias * aliasScore) +
            (weightContext * contextScore);
      } else if (hasRoll && !hasName) {
        // Roll number only (e.g. paper roll list or short roll suffix like 588)
        finalScore = (0.85 * rollScore) + (0.15 * contextScore);
      } else if (!hasRoll && hasName) {
        // Student name only (e.g. sign-in sheet or name list)
        finalScore = (0.85 * nameScore) + (0.15 * contextScore);
      } else {
        finalScore = 0.0;
      }

      final clampedFinal = finalScore.clamp(0.0, 1.0);
      final band = MatchConfidenceBand.fromScore(clampedFinal);

      final explanation = 'Roll: ${(rollScore * 100).toStringAsFixed(0)}% | '
          'Name: ${(nameScore * 100).toStringAsFixed(0)}% | '
          'Alias: ${(aliasScore * 100).toStringAsFixed(0)}% | '
          'Context: ${(contextScore * 100).toStringAsFixed(0)}%';

      results.add(MatchResult(
        candidate: candidate,
        rollScore: rollScore,
        nameScore: nameScore,
        aliasScore: aliasScore,
        contextScore: contextScore,
        finalScore: clampedFinal,
        band: band,
        explanation: explanation,
      ));
    }

    // Sort descending by finalScore, break ties with rollScore then nameScore
    results.sort((a, b) {
      final cmp = b.finalScore.compareTo(a.finalScore);
      if (cmp != 0) return cmp;
      final cmpRoll = b.rollScore.compareTo(a.rollScore);
      if (cmpRoll != 0) return cmpRoll;
      return b.nameScore.compareTo(a.nameScore);
    });

    return results;
  }

  /// Calculates roll number similarity supporting full rolls (F24-588) and short suffixes (588).
  double _calculateRollScore(String extracted, String targetRoll) {
    if (extracted.isEmpty) return 0.0;
    final normalizedTarget = StudentNormalizer.normalizeRoll(targetRoll);
    if (extracted == normalizedTarget) return 1.0;

    // Exact string suffix match (e.g. roll "588" matching "F24588")
    if (normalizedTarget.endsWith(extracted) && extracted.length >= 2) {
      return 0.98;
    }

    // Compare numeric digit sequences (e.g. "588" vs "F24-588", "1" vs "CS-2026-001", "042" vs "CS-2026-042")
    final extractedDigits = RegExp(r'\d+').allMatches(extracted).map((m) => m.group(0)!).toList();
    final targetOriginalDigits = RegExp(r'\d+').allMatches(targetRoll).map((m) => m.group(0)!).toList();
    final targetNormalizedDigits = RegExp(r'\d+').allMatches(normalizedTarget).map((m) => m.group(0)!).toList();

    if (extractedDigits.isNotEmpty) {
      final extLast = extractedDigits.last;
      final extInt = int.tryParse(extLast);

      // 1. Check last digit chunk of delimited roll (e.g. "1" matches "CS-2026-001" or "CS-001" because 1 == 001)
      if (targetOriginalDigits.isNotEmpty && extInt != null) {
        final targetLastOriginal = targetOriginalDigits.last;
        final targetOriginalInt = int.tryParse(targetLastOriginal);
        if (targetOriginalInt != null && extInt == targetOriginalInt) {
          return 0.98;
        }
      }

      // 2. Check last digit chunk of normalized roll
      if (targetNormalizedDigits.isNotEmpty && extInt != null) {
        final targetLastNorm = targetNormalizedDigits.last;
        final targetNormInt = int.tryParse(targetLastNorm);
        if (targetNormInt != null && extInt == targetNormInt) {
          return 0.98;
        }

        // Check if target numeric ends with extracted numeric (e.g. target "24588" ends with "588")
        if (targetLastNorm.endsWith(extLast) && extLast.length >= 2) {
          return 0.96;
        }
      }
    }

    return LevenshteinDistance.similarity(extracted, normalizedTarget);
  }


  /// Calculates name similarity combining Jaro-Winkler and Token Set similarity.
  double _calculateNameScore(String extracted, String normalizedTarget) {
    if (extracted.isEmpty) return 0.0;
    if (extracted == normalizedTarget) return 1.0;

    final jw = JaroWinklerDistance.similarity(extracted, normalizedTarget);
    final tokenScore = _tokenSetSimilarity(extracted, normalizedTarget);

    // Maximize to handle reversed name order (e.g., "Smith John" vs "John Smith")
    return max(jw, tokenScore);
  }

  /// Calculates similarity allowing for name word permutations (e.g. John Doe vs Doe John).
  double _tokenSetSimilarity(String s1, String s2) {
    final tokens1 = s1.split(' ').where((t) => t.isNotEmpty).toSet();
    final tokens2 = s2.split(' ').where((t) => t.isNotEmpty).toSet();

    if (tokens1.isEmpty || tokens2.isEmpty) return 0.0;

    final intersection = tokens1.intersection(tokens2);
    final union = tokens1.union(tokens2);

    final jaccard = intersection.length / union.length;

    // Check if all tokens from shorter name exist in longer name
    if (tokens1.length <= tokens2.length && tokens1.difference(tokens2).isEmpty) {
      return max(0.90, jaccard);
    }
    if (tokens2.length <= tokens1.length && tokens2.difference(tokens1).isEmpty) {
      return max(0.90, jaccard);
    }

    return jaccard;
  }

  /// Calculates alias similarity against any registered aliases.
  double _calculateAliasScore(String cleanName, List<String> aliases) {
    if (cleanName.isEmpty || aliases.isEmpty) return 0.0;
    double best = 0.0;
    for (final alias in aliases) {
      final normalized = StudentNormalizer.normalizeName(alias);
      final score = _calculateNameScore(cleanName, normalized);
      if (score > best) {
        best = score;
      }
    }
    return best;
  }
}
