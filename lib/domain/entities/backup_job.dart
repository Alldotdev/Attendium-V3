/// Zero-knowledge cloud backup snapshot record.
class BackupJobEntity {
  final String id;
  final String snapshotHash; // SHA-256 of encrypted blob
  final int encryptedSize;
  final String? driveFileId;
  final String status; // 'pending', 'encrypted', 'uploaded', 'verified', 'failed'
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BackupJobEntity({
    required this.id,
    required this.snapshotHash,
    required this.encryptedSize,
    this.driveFileId,
    this.status = 'pending',
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  });
}
