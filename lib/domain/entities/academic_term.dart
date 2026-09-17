import '../enums/term_status.dart';

/// Academic term / semester entity.
class AcademicTermEntity {
  final String id;
  final String userId;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final TermStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AcademicTermEntity({
    required this.id,
    required this.userId,
    required this.name,
    required this.startDate,
    required this.endDate,
    this.status = TermStatus.active,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isActive => status == TermStatus.active;

  AcademicTermEntity copyWith({
    String? id,
    String? userId,
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    TermStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AcademicTermEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
