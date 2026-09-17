import 'package:drift/drift.dart';

/// 1. Users table
class Users extends Table {
  TextColumn get id => text()();
  TextColumn get googleSubject => text().nullable().unique()();
  TextColumn get email => text()();
  TextColumn get displayName => text()();
  TextColumn get institutionName => text().withDefault(const Constant('Academic Institution'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 2. Academic Terms table
class AcademicTerms extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  IntColumn get startDate => integer()();
  IntColumn get endDate => integer()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 3. Classrooms table
class Classrooms extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get academicTermId => text().references(AcademicTerms, #id, onDelete: KeyAction.cascade)();
  TextColumn get courseCode => text()();
  TextColumn get courseName => text()();
  TextColumn get section => text()();
  TextColumn get instructorName => text()();
  RealColumn get defaultCreditHours => real().withDefault(const Constant(3.0))();
  RealColumn get attendanceThreshold => real().withDefault(const Constant(75.0))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 4. Students table
class Students extends Table {
  TextColumn get id => text()();
  TextColumn get classroomId => text().nullable().references(Classrooms, #id, onDelete: KeyAction.setNull)();
  TextColumn get rollNumber => text()();
  TextColumn get fullName => text()();
  TextColumn get normalizedName => text()();
  TextColumn get email => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('enrolled'))();
  IntColumn get enrolledAt => integer()();
  IntColumn get withdrawnAt => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 5. Enrollments table (Explicit junction)
class Enrollments extends Table {
  TextColumn get id => text()();
  TextColumn get studentId => text().references(Students, #id, onDelete: KeyAction.cascade)();
  TextColumn get classroomId => text().references(Classrooms, #id, onDelete: KeyAction.cascade)();
  TextColumn get rollNumber => text()();
  IntColumn get enrolledAt => integer()();
  IntColumn get withdrawnAt => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {studentId, classroomId},
  ];
}

/// 6. Student Aliases table
class StudentAliases extends Table {
  TextColumn get id => text()();
  TextColumn get studentId => text().references(Students, #id, onDelete: KeyAction.cascade)();
  TextColumn get alias => text()();
  TextColumn get normalizedAlias => text()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 7. Course Sessions table
class CourseSessions extends Table {
  TextColumn get id => text()();
  TextColumn get classroomId => text().references(Classrooms, #id, onDelete: KeyAction.cascade)();
  TextColumn get sessionDate => text()(); // YYYY-MM-DD
  TextColumn get startTime => text().nullable()();
  TextColumn get endTime => text().nullable()();
  TextColumn get topic => text().nullable()();
  TextColumn get sessionType => text().withDefault(const Constant('lecture'))();
  RealColumn get creditWeight => real().withDefault(const Constant(1.0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 8. Attendance Records table
class AttendanceRecords extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(CourseSessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get studentId => text().references(Students, #id, onDelete: KeyAction.cascade)();
  TextColumn get status => text()(); // present, absent, late, excused, unmarked
  RealColumn get creditWeight => real().withDefault(const Constant(1.0))();
  TextColumn get source => text().withDefault(const Constant('manual_grid'))();
  RealColumn get confidenceScore => real().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {sessionId, studentId},
  ];
}

/// 9. Attendance Policies table
class AttendancePolicies extends Table {
  TextColumn get id => text()();
  TextColumn get classroomId => text().references(Classrooms, #id, onDelete: KeyAction.cascade)();
  RealColumn get minimumPercentage => real().withDefault(const Constant(75.0))();
  RealColumn get lateWeight => real().withDefault(const Constant(0.5))();
  BoolColumn get excusedCounted => boolean().withDefault(const Constant(false))();
  RealColumn get shortThreshold => real().withDefault(const Constant(65.0))();
  RealColumn get debarThreshold => real().withDefault(const Constant(50.0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 10. Audit Logs table (Section 42)
class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()();
  TextColumn get beforeJson => text().nullable()();
  TextColumn get afterJson => text().nullable()();
  TextColumn get reason => text()();
  TextColumn get source => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 11. Import Jobs table
class ImportJobs extends Table {
  TextColumn get id => text()();
  TextColumn get classroomId => text().references(Classrooms, #id, onDelete: KeyAction.cascade)();
  TextColumn get filename => text()();
  TextColumn get mimeType => text()();
  TextColumn get fileHash => text()(); // SHA-256 (Section 46)
  TextColumn get sourceType => text()();
  TextColumn get processingStatus => text().withDefault(const Constant('pending'))();
  TextColumn get rawExtractionJson => text().nullable()();
  TextColumn get errorMessage => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 12. Extraction Rows table (Section 47)
class ExtractionRows extends Table {
  TextColumn get id => text()();
  TextColumn get importJobId => text().references(ImportJobs, #id, onDelete: KeyAction.cascade)();
  IntColumn get rowIndex => integer()();
  TextColumn get rawRoll => text().nullable()();
  TextColumn get rawName => text().nullable()();
  TextColumn get rawAttendance => text().nullable()();
  TextColumn get normalizedRoll => text().nullable()();
  TextColumn get normalizedName => text().nullable()();
  TextColumn get matchedStudentId => text().nullable()();
  RealColumn get matchScore => real().withDefault(const Constant(0.0))();
  RealColumn get aiConfidence => real().withDefault(const Constant(0.0))();
  TextColumn get reviewState => text().withDefault(const Constant('REVIEW_REQUIRED'))();
  TextColumn get evidenceJson => text().nullable()();
  TextColumn get sourceRegion => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 13. Attendance Alerts table
class AttendanceAlerts extends Table {
  TextColumn get id => text()();
  TextColumn get studentId => text().references(Students, #id, onDelete: KeyAction.cascade)();
  TextColumn get classroomId => text().references(Classrooms, #id, onDelete: KeyAction.cascade)();
  TextColumn get alertType => text()();
  RealColumn get percentage => real()();
  RealColumn get threshold => real()();
  BoolColumn get acknowledged => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 14. Backup Jobs table
class BackupJobs extends Table {
  TextColumn get id => text()();
  TextColumn get snapshotHash => text()();
  IntColumn get encryptedSize => integer()();
  TextColumn get driveFileId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get errorMessage => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
