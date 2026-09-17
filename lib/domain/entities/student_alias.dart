/// Student alias entity for alternate spellings and OCR variations.
class StudentAliasEntity {
  final String id;
  final String studentId;
  final String alias;
  final String normalizedAlias;
  final String source; // 'manual' or 'import_learned'
  final DateTime createdAt;

  const StudentAliasEntity({
    required this.id,
    required this.studentId,
    required this.alias,
    required this.normalizedAlias,
    this.source = 'manual',
    required this.createdAt,
  });
}
