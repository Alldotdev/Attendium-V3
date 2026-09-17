# Attendium — Database Architecture & Schema Specification

## 1. Engine & Configuration

Attendium utilizes **SQLite** as its single source of truth, accessed via native Dart FFI with Drift ORM bindings.

### Mandatory SQLite Pragmas
```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA busy_timeout = 5000;
```

---

## 2. Table Specifications

### 2.1 `users`
Local user profile required for offline operation and optional Google identity linking.
- `id` (TEXT PRIMARY KEY): UUIDv4
- `google_subject` (TEXT UNIQUE NULL): Linked Google sub claim
- `email` (TEXT NOT NULL)
- `display_name` (TEXT NOT NULL)
- `institution_name` (TEXT NOT NULL DEFAULT 'Academic Institution')
- `created_at` (INTEGER NOT NULL): Epoch milliseconds
- `updated_at` (INTEGER NOT NULL)

### 2.2 `academic_terms`
Academic semesters, trimesters, or quarters.
- `id` (TEXT PRIMARY KEY)
- `user_id` (TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE)
- `name` (TEXT NOT NULL): e.g. "Fall 2026"
- `start_date` (INTEGER NOT NULL)
- `end_date` (INTEGER NOT NULL)
- `status` (TEXT NOT NULL DEFAULT 'active'): active, archived
- `created_at` (INTEGER NOT NULL)
- `updated_at` (INTEGER NOT NULL)

### 2.3 `classrooms`
Course sections taught by an instructor.
- `id` (TEXT PRIMARY KEY)
- `user_id` (TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE)
- `academic_term_id` (TEXT NOT NULL REFERENCES academic_terms(id) ON DELETE CASCADE)
- `course_code` (TEXT NOT NULL): e.g. "CS-301"
- `course_name` (TEXT NOT NULL): e.g. "Algorithms & Complexity"
- `section` (TEXT NOT NULL): e.g. "A"
- `instructor_name` (TEXT NOT NULL)
- `default_credit_hours` (REAL NOT NULL DEFAULT 3.0)
- `attendance_threshold` (REAL NOT NULL DEFAULT 75.0)
- `status` (TEXT NOT NULL DEFAULT 'active'): active, archived
- `created_at` (INTEGER NOT NULL)
- `updated_at` (INTEGER NOT NULL)

### 2.4 `students`
Master student identity record.
- `id` (TEXT PRIMARY KEY)
- `classroom_id` (TEXT NULL REFERENCES classrooms(id) ON DELETE SET NULL)
- `roll_number` (TEXT NOT NULL)
- `full_name` (TEXT NOT NULL)
- `normalized_name` (TEXT NOT NULL)
- `email` (TEXT NULL)
- `status` (TEXT NOT NULL DEFAULT 'enrolled'): enrolled, withdrawn, suspended
- `enrolled_at` (INTEGER NOT NULL)
- `withdrawn_at` (INTEGER NULL)
- `created_at` (INTEGER NOT NULL)
- `updated_at` (INTEGER NOT NULL)

### 2.5 `enrollments`
Explicit junction mapping students to classrooms, preserving enrollment history.
- `id` (TEXT PRIMARY KEY)
- `student_id` (TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE)
- `classroom_id` (TEXT NOT NULL REFERENCES classrooms(id) ON DELETE CASCADE)
- `roll_number` (TEXT NOT NULL)
- `enrolled_at` (INTEGER NOT NULL)
- `withdrawn_at` (INTEGER NULL)
- `status` (TEXT NOT NULL DEFAULT 'active'): active, withdrawn, auditing
- `created_at` (INTEGER NOT NULL)
- `updated_at` (INTEGER NOT NULL)
- **UNIQUE constraint**: `(student_id, classroom_id)`

### 2.6 `student_aliases`
Alternate spellings, nicknames, or OCR variants learned from import reviews.
- `id` (TEXT PRIMARY KEY)
- `student_id` (TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE)
- `alias` (TEXT NOT NULL)
- `normalized_alias` (TEXT NOT NULL)
- `source` (TEXT NOT NULL DEFAULT 'manual'): manual, import_learned
- `created_at` (INTEGER NOT NULL)

### 2.7 `course_sessions`
Class meetings/lecture events.
- `id` (TEXT PRIMARY KEY)
- `classroom_id` (TEXT NOT NULL REFERENCES classrooms(id) ON DELETE CASCADE)
- `session_date` (TEXT NOT NULL): "YYYY-MM-DD"
- `start_time` (TEXT NULL): "HH:MM"
- `end_time` (TEXT NULL): "HH:MM"
- `topic` (TEXT NULL)
- `session_type` (TEXT NOT NULL DEFAULT 'lecture'): lecture, lab, tutorial, seminar, practical, other
- `credit_weight` (REAL NOT NULL DEFAULT 1.0)
- `status` (TEXT NOT NULL DEFAULT 'completed'): scheduled, in_progress, completed, cancelled
- `created_at` (INTEGER NOT NULL)
- `updated_at` (INTEGER NOT NULL)

### 2.8 `attendance_records`
Atomic attendance mark for a student in a session.
- `id` (TEXT PRIMARY KEY)
- `session_id` (TEXT NOT NULL REFERENCES course_sessions(id) ON DELETE CASCADE)
- `student_id` (TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE)
- `status` (TEXT NOT NULL): present, absent, late, excused, unmarked
- `credit_weight` (REAL NOT NULL DEFAULT 1.0)
- `source` (TEXT NOT NULL DEFAULT 'manual'): manual, csv_import, vision_ai, verified_import
- `visual_confidence` (REAL NULL)
- `name_match_score` (REAL NULL)
- `roll_match_score` (REAL NULL)
- `context_score` (REAL NULL)
- `final_match_score` (REAL NULL)
- `notes` (TEXT NULL)
- `created_at` (INTEGER NOT NULL)
- `updated_at` (INTEGER NOT NULL)
- **UNIQUE constraint**: `(session_id, student_id)`

### 2.9 `attendance_policies`
Custom threshold and weighting parameters per classroom.
- `id` (TEXT PRIMARY KEY)
- `classroom_id` (TEXT NOT NULL UNIQUE REFERENCES classrooms(id) ON DELETE CASCADE)
- `minimum_percentage` (REAL NOT NULL DEFAULT 75.0)
- `late_weight` (REAL NOT NULL DEFAULT 0.5)
- `excused_counted` (INTEGER NOT NULL DEFAULT 1): 1=counted as present, 0=excluded from total
- `short_threshold` (REAL NOT NULL DEFAULT 65.0)
- `debar_threshold` (REAL NOT NULL DEFAULT 50.0)
- `created_at` (INTEGER NOT NULL)
- `updated_at` (INTEGER NOT NULL)

### 2.10 `audit_logs`
Immutable record of all modifications to attendance records and critical entities.
- `id` (TEXT PRIMARY KEY)
- `user_id` (TEXT NOT NULL)
- `entity_type` (TEXT NOT NULL): attendance_record, student, classroom, session
- `entity_id` (TEXT NOT NULL)
- `action` (TEXT NOT NULL): create, update, delete
- `before_json` (TEXT NULL)
- `after_json` (TEXT NOT NULL)
- `reason` (TEXT NULL)
- `source` (TEXT NOT NULL DEFAULT 'ui')
- `created_at` (INTEGER NOT NULL)

### 2.11 `import_jobs`
Metadata for document ingestion workflows.
- `id` (TEXT PRIMARY KEY)
- `classroom_id` (TEXT NOT NULL REFERENCES classrooms(id) ON DELETE CASCADE)
- `filename` (TEXT NOT NULL)
- `mime_type` (TEXT NOT NULL)
- `file_hash` (TEXT NOT NULL): SHA-256
- `source_type` (TEXT NOT NULL): csv, xlsx, txt, pdf, image
- `processing_status` (TEXT NOT NULL DEFAULT 'queued'): queued, processing, waiting_for_ai, awaiting_review, completed, failed, cancelled
- `raw_extraction_json` (TEXT NULL)
- `error_message` (TEXT NULL)
- `created_at` (INTEGER NOT NULL)
- `updated_at` (INTEGER NOT NULL)

### 2.12 `extraction_rows`
Extracted raw row items awaiting human verification or committed status.
- `id` (TEXT PRIMARY KEY)
- `import_job_id` (TEXT NOT NULL REFERENCES import_jobs(id) ON DELETE CASCADE)
- `row_index` (INTEGER NOT NULL)
- `raw_roll_number` (TEXT NULL)
- `raw_name` (TEXT NULL)
- `raw_attendance` (TEXT NULL)
- `normalized_roll_number` (TEXT NULL)
- `normalized_name` (TEXT NULL)
- `matched_student_id` (TEXT NULL REFERENCES students(id) ON DELETE SET NULL)
- `match_score` (REAL NOT NULL DEFAULT 0.0)
- `ai_confidence` (REAL NOT NULL DEFAULT 0.0)
- `review_state` (TEXT NOT NULL DEFAULT 'pending'): matched, review_required, unmatched, rejected, committed
- `evidence_json` (TEXT NULL)
- `source_region` (TEXT NULL)
- `created_at` (INTEGER NOT NULL)
- `updated_at` (INTEGER NOT NULL)

### 2.13 `attendance_alerts`
Automated threshold alerts triggered when student attendance drops below thresholds.
- `id` (TEXT PRIMARY KEY)
- `student_id` (TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE)
- `classroom_id` (TEXT NOT NULL REFERENCES classrooms(id) ON DELETE CASCADE)
- `alert_type` (TEXT NOT NULL): at_risk, short, debarred
- `percentage` (REAL NOT NULL)
- `threshold` (REAL NOT NULL)
- `acknowledged` (INTEGER NOT NULL DEFAULT 0)
- `created_at` (INTEGER NOT NULL)

### 2.14 `backup_jobs`
History of zero-knowledge encrypted database snapshots.
- `id` (TEXT PRIMARY KEY)
- `snapshot_hash` (TEXT NOT NULL)
- `encrypted_size` (INTEGER NOT NULL)
- `drive_file_id` (TEXT NULL)
- `status` (TEXT NOT NULL): pending, uploading, verified, failed
- `created_at` (INTEGER NOT NULL)
- `completed_at` (INTEGER NULL)
- `error_message` (TEXT NULL)

---

## 3. Indexing Strategy

```sql
CREATE INDEX idx_students_classroom_roll ON students(classroom_id, roll_number);
CREATE INDEX idx_students_normalized_name ON students(normalized_name);
CREATE INDEX idx_enrollments_classroom ON enrollments(classroom_id, status);
CREATE INDEX idx_attendance_session_student ON attendance_records(session_id, student_id);
CREATE INDEX idx_attendance_student ON attendance_records(student_id);
CREATE INDEX idx_course_sessions_class_date ON course_sessions(classroom_id, session_date);
CREATE INDEX idx_audit_logs_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX idx_import_jobs_class_status ON import_jobs(classroom_id, processing_status);
CREATE INDEX idx_extraction_rows_job_state ON extraction_rows(import_job_id, review_state);
CREATE INDEX idx_attendance_alerts_class_ack ON attendance_alerts(classroom_id, acknowledged);
```
