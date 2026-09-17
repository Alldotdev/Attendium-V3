import '../../core/constants/app_constants.dart';

/// Fuzzy matching confidence bands.
enum MatchConfidenceBand {
  autoAccept('auto_accept', 'Auto-Accept Candidate', 'Score >= 0.95'),
  review('review', 'Review Recommended', '0.85 <= Score < 0.95'),
  confirmationRequired('confirmation_required', 'Confirmation Required', '0.70 <= Score < 0.85'),
  unmatched('unmatched', 'Unmatched', 'Score < 0.70');

  final String value;
  final String label;
  final String range;

  const MatchConfidenceBand(this.value, this.label, this.range);

  static MatchConfidenceBand fromScore(double score) {
    if (score >= AppConstants.bandAutoAccept) {
      return MatchConfidenceBand.autoAccept;
    } else if (score >= AppConstants.bandReview) {
      return MatchConfidenceBand.review;
    } else if (score >= AppConstants.bandConfirmationRequired) {
      return MatchConfidenceBand.confirmationRequired;
    } else {
      return MatchConfidenceBand.unmatched;
    }
  }
}
