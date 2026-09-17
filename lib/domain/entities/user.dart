/// Local user profile entity.
class UserEntity {
  final String id;
  final String? googleSubject;
  final String email;
  final String displayName;
  final String institutionName;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserEntity({
    required this.id,
    this.googleSubject,
    required this.email,
    required this.displayName,
    this.institutionName = 'Academic Institution',
    required this.createdAt,
    required this.updatedAt,
  });

  UserEntity copyWith({
    String? id,
    String? googleSubject,
    String? email,
    String? displayName,
    String? institutionName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserEntity(
      id: id ?? this.id,
      googleSubject: googleSubject ?? this.googleSubject,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      institutionName: institutionName ?? this.institutionName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
