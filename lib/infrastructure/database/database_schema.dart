/// Direct authoritative SQLite schema definition and pragmas for Attendium.
/// Strictly enforces Section 1 & Section 2 of DATABASE.md.
class DatabaseSchema {
  DatabaseSchema._();

  static const List<String> mandatoryPragmas = [
    'PRAGMA foreign_keys = ON;',
    'PRAGMA journal_mode = WAL;',
    'PRAGMA synchronous = NORMAL;',
    'PRAGMA busy_timeout = 5000;',
  ];

  static const List<String> createTableStatements = [
    // 1. users
    '''
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      google_subject TEXT UNIQUE,
      email TEXT NOT NULL,
      display_name TEXT NOT NULL,
      institution_name TEXT NOT NULL DEFAULT 'Academic Institution',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    ''',

    // 2. academic_terms
    '''
    CREATE TABLE IF NOT EXISTS academic_terms (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      start_date INTEGER NOT NULL,
      end_date INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'active',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    ''',

    // 3. classrooms
    '''
    CREATE TABLE IF NOT EXISTS classrooms (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      academic_term_id TEXT NOT NULL REFERENCES academic_terms(id) ON DELETE CASCADE,
      course_code TEXT NOT NULL,
      course_name TEXT NOT NULL,
      section TEXT NOT NULL,
      instructor_name TEXT NOT NULL,
      default_credit_hours REAL NOT NULL DEFAULT 3.0,
      attendance_threshold REAL NOT NULL DEFAULT 75.0,
      status TEXT NOT NULL DEFAULT 'active',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    ''',

    // 4. students
    '''
    CREATE TABLE IF NOT EXISTS students (
      id TEXT PRIMARY KEY,
      classroom_id TEXT REFERENCES classrooms(id) ON DELETE SET NULL,
      roll_number TEXT NOT NULL,
      full_name TEXT NOT NULL,
      normalized_name TEXT NOT NULL,
      email TEXT,
      status TEXT NOT NULL DEFAULT 'enrolled',
      enrolled_at INTEGER NOT NULL,
      withdrawn_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    ''',

    // 5. enrollments
    '''
    CREATE TABLE IF NOT EXISTS enrollments (
      id TEXT PRIMARY KEY,
      student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
      classroom_id TEXT NOT NULL REFERENCES classrooms(id) ON DELETE CASCADE,
      roll_number TEXT NOT NULL,
      enrolled_at INTEGER NOT NULL,
      withdrawn_at INTEGER,
      status TEXT NOT NULL DEFAULT 'active',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      UNIQUE (student_id, classroom_id)
    );
    ''',

    // 6. student_aliases
    '''
    CREATE TABLE IF NOT EXISTS student_aliases (
      id TEXT PRIMARY KEY,
      student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
      alias TEXT NOT NULL,
      normalized_alias TEXT NOT NULL,
      source TEXT NOT NULL DEFAULT 'manual',
      created_at INTEGER NOT NULL
    );
    ''',

    // 7. course_sessions
    '''
    CREATE TABLE IF NOT EXISTS course_sessions (
      id TEXT PRIMARY KEY,
      classroom_id TEXT NOT NULL REFERENCES classrooms(id) ON DELETE CASCADE,
      session_date TEXT NOT NULL,
      start_time TEXT,
      end_time TEXT,
      topic TEXT,
      session_type TEXT NOT NULL DEFAULT 'lecture',
      credit_weight REAL NOT NULL DEFAULT 1.0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    ''',

    // 8. attendance_records
    '''
    CREATE TABLE IF NOT EXISTS attendance_records (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL REFERENCES course_sessions(id) ON DELETE CASCADE,
      student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
      status TEXT NOT NULL,
      credit_weight REAL NOT NULL DEFAULT 1.0,
      source TEXT NOT NULL DEFAULT 'manual_grid',
      confidence_score REAL,
      notes TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      UNIQUE (session_id, student_id)
    );
    ''',

    // 9. attendance_policies
    '''
    CREATE TABLE IF NOT EXISTS attendance_policies (
      id TEXT PRIMARY KEY,
      classroom_id TEXT NOT NULL REFERENCES classrooms(id) ON DELETE CASCADE,
      minimum_percentage REAL NOT NULL DEFAULT 75.0,
      late_weight REAL NOT NULL DEFAULT 0.5,
      excused_counted INTEGER NOT NULL DEFAULT 0,
      short_threshold REAL NOT NULL DEFAULT 65.0,
      debar_threshold REAL NOT NULL DEFAULT 50.0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    ''',

    // 10. audit_logs
    '''
    CREATE TABLE IF NOT EXISTS audit_logs (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      action TEXT NOT NULL,
      before_json TEXT,
      after_json TEXT,
      reason TEXT NOT NULL,
      source TEXT NOT NULL,
      created_at INTEGER NOT NULL
    );
    ''',

    // 11. import_jobs
    '''
    CREATE TABLE IF NOT EXISTS import_jobs (
      id TEXT PRIMARY KEY,
      classroom_id TEXT NOT NULL REFERENCES classrooms(id) ON DELETE CASCADE,
      filename TEXT NOT NULL,
      mime_type TEXT NOT NULL,
      file_hash TEXT NOT NULL,
      source_type TEXT NOT NULL,
      processing_status TEXT NOT NULL DEFAULT 'pending',
      raw_extraction_json TEXT,
      error_message TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    ''',

    // 12. extraction_rows
    '''
    CREATE TABLE IF NOT EXISTS extraction_rows (
      id TEXT PRIMARY KEY,
      import_job_id TEXT NOT NULL REFERENCES import_jobs(id) ON DELETE CASCADE,
      row_index INTEGER NOT NULL,
      raw_roll TEXT,
      raw_name TEXT,
      raw_attendance TEXT,
      normalized_roll TEXT,
      normalized_name TEXT,
      matched_student_id TEXT,
      match_score REAL NOT NULL DEFAULT 0.0,
      ai_confidence REAL NOT NULL DEFAULT 0.0,
      review_state TEXT NOT NULL DEFAULT 'REVIEW_REQUIRED',
      evidence_json TEXT,
      source_region TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    ''',

    // 13. attendance_alerts
    '''
    CREATE TABLE IF NOT EXISTS attendance_alerts (
      id TEXT PRIMARY KEY,
      student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
      classroom_id TEXT NOT NULL REFERENCES classrooms(id) ON DELETE CASCADE,
      alert_type TEXT NOT NULL,
      percentage REAL NOT NULL,
      threshold REAL NOT NULL,
      acknowledged INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    );
    ''',

    // 14. backup_jobs
    '''
    CREATE TABLE IF NOT EXISTS backup_jobs (
      id TEXT PRIMARY KEY,
      snapshot_hash TEXT NOT NULL,
      encrypted_size INTEGER NOT NULL,
      drive_file_id TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      error_message TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    ''',
  ];

  static const List<String> createIndexStatements = [
    'CREATE INDEX IF NOT EXISTS idx_terms_user ON academic_terms(user_id);',
    'CREATE INDEX IF NOT EXISTS idx_classrooms_term ON classrooms(academic_term_id);',
    'CREATE INDEX IF NOT EXISTS idx_students_classroom ON students(classroom_id);',
    'CREATE INDEX IF NOT EXISTS idx_students_roll ON students(roll_number);',
    'CREATE INDEX IF NOT EXISTS idx_enrollments_class ON enrollments(classroom_id);',
    'CREATE INDEX IF NOT EXISTS idx_aliases_student ON student_aliases(student_id);',
    'CREATE INDEX IF NOT EXISTS idx_sessions_class ON course_sessions(classroom_id);',
    'CREATE INDEX IF NOT EXISTS idx_sessions_date ON course_sessions(session_date);',
    'CREATE INDEX IF NOT EXISTS idx_attendance_session ON attendance_records(session_id);',
    'CREATE INDEX IF NOT EXISTS idx_attendance_student ON attendance_records(student_id);',
    'CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_logs(entity_type, entity_id);',
    'CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_logs(created_at);',
    'CREATE INDEX IF NOT EXISTS idx_imports_class ON import_jobs(classroom_id);',
    'CREATE INDEX IF NOT EXISTS idx_imports_hash ON import_jobs(file_hash);',
    'CREATE INDEX IF NOT EXISTS idx_extraction_job ON extraction_rows(import_job_id);',
    'CREATE INDEX IF NOT EXISTS idx_alerts_class ON attendance_alerts(classroom_id);',
  ];
}
