/// Application-wide constants, thresholds, and tunable default parameters.
class AppConstants {
  AppConstants._();

  static const String appName = 'Attendium';
  static const String appVersion = '1.0.0';
  static const String appTagline = 'Autonomous Enterprise Attendance Management System';

  // Attendance Policy Defaults
  static const double defaultAttendanceThreshold = 75.0; // 75%
  static const double defaultLateWeight = 0.5;           // 50% credit for Late
  static const bool defaultExcusedCounted = false;       // Excused excluded from denominator
  static const double defaultDebarThreshold = 50.0;      // < 50% Debarred
  static const double atRiskThresholdDelta = 10.0;       // 65% - 74.9% At Risk

  // Fuzzy Matching Weights (Directive Section 15)
  // FinalScore = 0.40 * Roll + 0.35 * Name + 0.15 * Alias + 0.10 * Context
  static const double fuzzyWeightRoll = 0.40;
  static const double fuzzyWeightName = 0.35;
  static const double fuzzyWeightAlias = 0.15;
  static const double fuzzyWeightContext = 0.10;

  // Review Bands (Directive Section 15)
  static const double bandAutoAccept = 0.95;
  static const double bandReview = 0.85;
  static const double bandConfirmationRequired = 0.70;

  // Storage & Backup Constants
  static const String databaseFileName = 'attendium.sqlite';
  static const String backupFileExtension = '.attendium.enc';
  static const int pbkdf2Iterations = 100000;
  static const int aesKeyLengthBytes = 32; // AES-256
  static const int gcmNonceLengthBytes = 12;
  static const int gcmTagLengthBytes = 16;

  // Audit Log Sources
  static const String auditSourceManual = 'manual_grid';
  static const String auditSourceAiImport = 'ai_import';
  static const String auditSourceCsvImport = 'csv_import';
  static const String auditSourceEdit = 'manual_edit';
  static const String auditSourceBulk = 'bulk_action';
}
