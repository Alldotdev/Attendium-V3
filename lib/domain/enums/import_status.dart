/// Import job status and row review classification.
enum ImportJobStatus {
  pending('pending', 'Pending'),
  extracting('extracting', 'AI Extracting'),
  reviewReady('review_ready', 'Ready for Review'),
  committed('committed', 'Committed to Database'),
  failed('failed', 'Failed');

  final String value;
  final String label;

  const ImportJobStatus(this.value, this.label);

  static ImportJobStatus fromString(String? val) {
    if (val == null) return ImportJobStatus.pending;
    return ImportJobStatus.values.firstWhere(
      (e) => e.value == val.toLowerCase(),
      orElse: () => ImportJobStatus.pending,
    );
  }
}

/// Row-level review state mandated by Section 47 of the directive.
enum RowReviewState {
  matched('MATCHED', 'Matched with high confidence'),
  reviewRequired('REVIEW_REQUIRED', 'Review required before commit'),
  unmatched('UNMATCHED', 'No local student match found'),
  rejected('REJECTED', 'Rejected by reviewer'),
  committed('COMMITTED', 'Successfully committed to attendance records');

  final String code;
  final String description;

  const RowReviewState(this.code, this.description);

  static RowReviewState fromString(String? val) {
    if (val == null) return RowReviewState.reviewRequired;
    return RowReviewState.values.firstWhere(
      (e) => e.code == val.toUpperCase(),
      orElse: () => RowReviewState.reviewRequired,
    );
  }
}
