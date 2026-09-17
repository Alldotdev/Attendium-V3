# ATTENDIUM — AUTONOMOUS ENTERPRISE ATTENDANCE MANAGEMENT SYSTEM
## Antigravity Master Build Directive v1.0

> **MISSION:** Build, test, verify, package, and document a production-ready offline-first desktop Attendance Management System called **Attendium** for educators, professors, teachers, and school/university administrators.
>
> **PRIMARY PRINCIPLE:** The application must be a reliable local attendance database with AI-powered document ingestion. AI is an extraction assistant, never the source of truth.
>
> **AUTONOMY:** Execute the entire engineering lifecycle autonomously. Do not stop after scaffolding, do not leave TODO placeholders, do not ask the user to manually implement routine steps, and do not request approval for every small action. Inspect the workspace, plan internally, implement, run commands, test, diagnose, repair, retest, and continue until the acceptance criteria are satisfied.
>
> **IMPORTANT:** Do not claim a feature is complete merely because code exists. Verify it by running the relevant tests/builds and inspecting the resulting application. If a build or test fails, diagnose and fix it before continuing.
>
> **HUMAN APPROVAL BOUNDARY:** Never bypass OS security, authentication consent, API credentials, package-signing requirements, or destructive actions that the operating system explicitly requires the user to authorize. Everything else should be automated. If Antigravity's environment supports an "Always Proceed" terminal execution mode, use it for routine project commands where permitted by the user's configured environment. Do not repeatedly pause for routine command confirmations.

---

# 1. PRODUCT IDENTITY

**Product name:** Attendium  
**Product type:** Offline-first desktop attendance management system  
**Target users:** Teachers, professors, lecturers, school administrators, university administrators  
**Primary platform:** Windows desktop first, with architecture prepared for macOS/Linux  
**Primary design language:** Modern, simple, elegant, premium, highly usable  
**Primary UI color:** White  
**Secondary palette:** Soft gray, slate, charcoal text, subtle violet accent, emerald success, amber warning, red danger  
**Design character:** Clean academic SaaS/productivity software; minimal; spacious; professional; calm; high information density without visual clutter.

The application must feel like a polished commercial desktop product, not a prototype or admin template.

---

# 2. NON-NEGOTIABLE REQUIREMENTS

Implement every requirement below.

## 2.1 Local-first data

The following must be stored locally in SQLite:

- User profile/configuration required for offline operation
- Academic terms
- Classrooms/classes
- Courses
- Sections
- Student rosters
- Student aliases
- Enrollment history
- Attendance sessions
- Attendance records
- Attendance policies
- Attendance calculations/cache where useful
- Import jobs
- Extracted document rows
- Human verification decisions
- Audit history
- Alerts
- Application settings
- Backup metadata
- Job queue state

The application must remain useful without an internet connection.

Offline operation must support:

- Opening the application
- Viewing classes
- Viewing students
- Creating/editing classes
- Creating/editing students
- Taking attendance manually
- Editing historical attendance
- Calculating attendance
- Searching/filtering
- Viewing reports generated from local data
- Exporting local reports
- Reviewing previously imported documents
- Maintaining audit logs

Network-dependent functions:

- Cloud AI extraction
- Google authentication
- Google Drive backup
- Application update checks
- Other explicitly network-dependent integrations

Never make cloud availability a prerequisite for basic attendance operation.

---

# 3. TECHNOLOGY ARCHITECTURE

Use the following stack unless a concrete technical incompatibility requires an alternative. If an alternative is necessary, document the reason and preserve the architectural requirements.

## 3.1 Primary stack

- Flutter Desktop
- Dart
- Riverpod for state management
- Clean Architecture / feature-first architecture
- Drift ORM
- SQLite
- Dart FFI/native SQLite
- Dio or equivalent robust HTTP client
- Secure OS credential/keychain storage
- Native desktop file dialogs
- Native drag-and-drop support
- PDF generation
- XLSX generation
- JSON Schema validation
- Unit/integration/widget/E2E testing

## 3.2 Architecture layers

Use:

UI
→ Presentation State
→ Application Use Cases
→ Domain
→ Repository Interfaces
→ Infrastructure
→ Drift/SQLite / File System / AI APIs / Google APIs

Do not allow widgets to directly access SQLite.

Do not allow AI provider code to directly mutate the database.

All persistent changes must pass through application/domain logic.

---

# 4. REQUIRED PROJECT STRUCTURE

Create a clean structure similar to:

lib/
  core/
    database/
    encryption/
    networking/
    logging/
    errors/
    result/
    utilities/
    platform/
    jobs/
  domain/
    entities/
    value_objects/
    repositories/
    services/
  application/
    use_cases/
    services/
    dto/
  features/
    authentication/
    dashboard/
    classrooms/
    students/
    attendance/
    imports/
    ai/
    matching/
    reports/
    backups/
    settings/
    audit/
  shared/
    widgets/
    design_system/
    extensions/
    validators/

test/
  unit/
  integration/
  widget/
  fixtures/
  golden/
  e2e/

assets/
  icons/
  fonts/
  sample_documents/
  templates/

docs/
  architecture/
  database/
  ai/
  security/
  testing/
  deployment/

scripts/
  build/
  test/
  packaging/

.github/
  workflows/

Also create:

README.md
ARCHITECTURE.md
SECURITY.md
AI_PIPELINE.md
DATABASE.md
TESTING.md
DEPLOYMENT.md
CHANGELOG.md
.env.example
.gitignore

Never commit secrets.

---

# 5. DATABASE DESIGN

Use SQLite with foreign-key enforcement.

Required SQLite settings:

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA busy_timeout = 5000;

Use migrations. Never destroy user data during schema upgrades.

## 5.1 users

Fields:

- id
- google_subject nullable/unique
- email
- display_name
- institution_name
- created_at
- updated_at

## 5.2 academic_terms

Fields:

- id
- user_id
- name
- start_date
- end_date
- status
- created_at
- updated_at

## 5.3 classrooms

Fields:

- id
- user_id
- academic_term_id
- course_code
- course_name
- section
- instructor_name
- default_credit_hours
- attendance_threshold
- status
- created_at
- updated_at

## 5.4 students

Fields:

- id
- classroom_id where legacy/simple mode is needed
- roll_number
- full_name
- normalized_name
- email
- status
- enrolled_at
- withdrawn_at
- created_at
- updated_at

Do not identify students solely by name.

## 5.5 enrollments

Implement this even if a simple classroom_id exists for compatibility.

Fields:

- id
- student_id
- classroom_id
- roll_number
- enrolled_at
- withdrawn_at
- status
- created_at
- updated_at

Unique constraint:

(student_id, classroom_id)

Preserve historical enrollment records.

## 5.6 student_aliases

Fields:

- id
- student_id
- alias
- normalized_alias
- source
- created_at

## 5.7 course_sessions

Fields:

- id
- classroom_id
- session_date
- start_time
- end_time
- topic
- session_type
- credit_weight
- status
- created_at
- updated_at

Support:

- lecture
- lab
- tutorial
- seminar
- practical
- other

Credit weight must be configurable per session.

## 5.8 attendance_records

Fields:

- id
- session_id
- student_id
- status

Allowed:

- present
- absent
- late
- excused
- unmarked

Additional:

- credit_weight
- source
- visual_confidence
- name_match_score
- roll_match_score
- context_score
- final_match_score
- notes
- created_at
- updated_at

Unique:

(session_id, student_id)

## 5.9 attendance_policies

Fields:

- id
- classroom_id
- minimum_percentage
- late_weight
- excused_counted
- short_threshold
- debar_threshold
- created_at
- updated_at

All thresholds configurable.

Do not hardcode 75% as an immutable institutional rule.

## 5.10 audit_logs

Fields:

- id
- user_id
- entity_type
- entity_id
- action
- before_json
- after_json
- reason
- source
- created_at

Every historical attendance modification must generate an audit event.

## 5.11 import_jobs

Fields:

- id
- classroom_id
- filename
- mime_type
- file_hash
- source_type
- processing_status
- raw_extraction_json
- error_message
- created_at
- updated_at

Statuses:

- queued
- processing
- waiting_for_ai
- awaiting_review
- completed
- failed
- cancelled

## 5.12 extraction_rows

Fields:

- id
- import_job_id
- row_index
- raw_roll_number
- raw_name
- raw_attendance
- normalized_roll_number
- normalized_name
- matched_student_id
- match_score
- ai_confidence
- review_state
- evidence_json
- source_region
- created_at
- updated_at

## 5.13 attendance_alerts

Fields:

- id
- student_id
- classroom_id
- alert_type
- percentage
- threshold
- acknowledged
- created_at

## 5.14 backup_jobs

Fields:

- id
- snapshot_hash
- encrypted_size
- drive_file_id
- status
- created_at
- completed_at
- error_message

---

# 6. ATTENDANCE CALCULATION ENGINE

Do not use simplistic raw session counting.

Support weighted attendance.

Conceptually:

attendance_percentage =
weighted_attended_units / weighted_counted_units * 100

The late weight must be configurable.

Example:

Present = 1.0
Late = configurable, e.g. 0.5
Absent = 0
Excused = policy-dependent
Unmarked = excluded until resolved

Never silently convert unknown/unmarked to absent.

Provide configurable status labels such as:

- Safe
- At Risk
- Short
- Debarred

These are configurable institutional labels, not hardcoded assumptions.

---

# 7. STUDENT MANAGEMENT

Provide:

- Manual student creation
- Bulk import
- Search
- Sort
- Filter
- Edit
- Archive
- Enrollment dates
- Withdrawal dates
- Email
- Roll number
- Alias management
- Duplicate detection
- Import history
- Attendance history

Prevent accidental duplicate roll numbers inside the same classroom.

Support identical student names by relying on stable student IDs plus additional identifiers.

Never delete historical attendance merely because a student leaves a class.

---

# 8. CLASS CREATION

Allow creation of a class with:

- Course code
- Course name
- Section
- Instructor
- Academic term
- Default credit hours
- Attendance threshold
- Late weighting
- Excused absence policy

Allow class creation from an imported attendance document.

The user must be able to inspect the inferred course/class information before committing it.

---

# 9. MULTIMODAL IMPORT ENGINE

Support:

- CSV
- XLSX
- XLS where feasible
- TXT
- PDF
- PNG
- JPG/JPEG
- WEBP
- scanned attendance sheets
- photographs of paper registers
- whiteboards
- screenshots
- daily attendance sheets

## 9.1 File handling

Implement:

- file type detection
- extension validation
- MIME detection
- magic-byte validation where applicable
- safe file size limits
- temporary file management
- duplicate file hash detection
- cancellation
- retry
- progress reporting

Never trust the filename extension alone.

---

# 10. IMPORT STRATEGY

Use deterministic parsers whenever possible.

CSV/XLSX/TXT:

Parser first → normalization → matching

Do NOT send structured CSV/XLSX to vision AI unnecessarily.

PDF:

1. Detect text layer.
2. If text is usable, parse it.
3. If scanned/image-based, render pages and use OCR/vision.
4. For mixed PDFs, process page-by-page.

Images:

Preprocess before vision:

- orientation correction
- crop
- deskew
- perspective correction
- contrast enhancement
- denoise
- adaptive threshold where useful
- resolution normalization

Never alter the original source file.

Store the original hash.

---

# 11. AI PROVIDER ARCHITECTURE

Create a provider abstraction.

Example:

abstract class AiProvider {
  Future<AttendanceExtraction> extractAttendance(
    AttendanceDocument document,
    ExtractionContext context,
  );
}

Implement:

- GeminiProvider
- OpenAiProvider
- LocalOcrProvider

The UI must not depend directly on a specific AI vendor.

Allow provider selection:

- Local only
- Gemini
- OpenAI
- Auto

Cloud AI must be opt-in/configurable because cloud vision means source documents temporarily leave the device.

---

# 12. AI EXTRACTION RULES

AI must:

- Extract visible information only.
- Never invent names.
- Never invent roll numbers.
- Never invent dates.
- Never invent attendance marks.
- Preserve row order.
- Return null when unreadable.
- Return unknown for ambiguous attendance.
- Never decide final student identity.
- Never directly write to SQLite.
- Never merge students.
- Never split rows unless visually justified.
- Keep extraction confidence separate from identity matching confidence.
- Provide short visual evidence.
- Return strict schema-compliant JSON.

Gemini supports schema-constrained structured output; use the current official API/SDK behavior rather than relying on free-form JSON parsing alone. Validate every returned object locally before using it. citeturn0search10

---

# 13. CANONICAL AI JSON CONTRACT

Use a schema equivalent to:

{
  "document_date": "YYYY-MM-DD|null",
  "course_name": "string|null",
  "course_code": "string|null",
  "section": "string|null",
  "rows": [
    {
      "row_index": 1,
      "roll_number": "string|null",
      "name": "string|null",
      "attendance_status": "present|absent|late|excused|unknown",
      "confidence": 0.0,
      "evidence": "string"
    }
  ]
}

Requirements:

- additionalProperties = false
- required fields explicitly declared
- confidence range 0.0–1.0
- validate after API response
- reject malformed output
- never silently repair dangerous semantic errors

---

# 14. AI SYSTEM PROMPT

Use this conceptual system instruction for attendance extraction:

"You are an attendance-document extraction engine. Extract only information visibly present in the supplied document. Do not infer or invent student identities, roll numbers, dates, course details, or attendance statuses. Preserve the document's row order. If a value cannot be read confidently, return null. If an attendance mark is ambiguous, return unknown. Do not decide which local roster student a row represents. Identity matching is performed separately by deterministic software. Your confidence score measures visual extraction confidence only. Provide concise evidence describing what is visibly present. Return only schema-valid JSON."

Create vendor-specific adapters without changing the canonical domain contract.

---

# 15. FUZZY STUDENT MATCHING

AI extraction is followed by deterministic local matching.

Normalize:

- lowercase
- Unicode normalization
- whitespace
- punctuation
- hyphens
- common OCR artifacts

For numeric fields, cautiously support common OCR substitutions such as:

O ↔ 0
I/l ↔ 1
S ↔ 5

Do not apply these substitutions blindly to names.

Use:

- exact roll matching
- Levenshtein similarity
- Jaro-Winkler
- token similarity
- aliases
- classroom context
- enrollment state

Suggested initial composite:

FinalScore =
0.40 * RollScore +
0.35 * NameScore +
0.15 * AliasScore +
0.10 * ContextScore

Treat these as tunable starting parameters, not universal truth.

Initial review bands:

>= 0.95: candidate for auto-accept
0.85–0.949: review
0.70–0.849: confirmation required
< 0.70: unmatched

These are matching scores, not calibrated probabilities.

Keep:

- AI visual confidence
- roll similarity
- name similarity
- alias similarity
- context score
- final match score

as separate fields.

Candidate generation should narrow by roll number/context before expensive name comparison.

---

# 16. HUMAN-IN-THE-LOOP REVIEW

This is a core product feature.

Layout:

LEFT:
- source image/PDF/document preview
- zoom
- pan
- page navigation
- selected-row evidence highlight when available

RIGHT:
- editable attendance grid
- extracted roll
- extracted name
- matched student
- attendance status
- confidence
- review state

Highlight low-confidence rows.

Provide:

- Accept
- Edit
- Reject
- Re-match
- Skip
- Create student
- Map to existing student
- Bulk approve safe matches

No extracted row should automatically become trusted historical attendance when confidence is insufficient.

---

# 17. KEYBOARD-FIRST ATTENDANCE GRID

The grid must be fast enough for real classroom use.

Keyboard:

Arrow keys = navigation
P = Present
A = Absent
L = Late
E = Excused
U = Unmarked
Space = optional status interaction
Ctrl+Z = undo
Ctrl+Shift+Z = redo

Support:

- multi-select
- batch updates
- search
- filtering
- sticky student identity columns
- virtualization for large classes
- instant visual state updates
- transactional save

Every committed change must create an audit record when appropriate.

---

# 18. HISTORICAL EDITING

Users must be able to edit past attendance.

Before commit:

- show affected student/session
- show previous value
- show new value
- optionally require reason based on settings

Record:

- who
- what
- previous value
- new value
- timestamp
- reason
- source

Audit records must be immutable from normal UI operations.

---

# 19. DASHBOARD

Create a polished dashboard.

Show:

- total classes
- today's sessions
- pending imports
- students requiring attention
- recent activity
- attendance summaries
- low attendance alerts
- backup status
- AI provider status
- offline/online status

Avoid excessive charts.

Use charts only where they communicate useful information.

---

# 20. REPORTING

Provide:

## Student report

- Student information
- Class
- Attendance percentage
- Sessions attended
- Sessions missed
- Late count
- Excused count
- Current status
- Date range

## Class report

- Student list
- Attendance percentage
- status
- present/absent/late/excused counts

## Session matrix

Rows = students
Columns = sessions

## Audit report

- historical changes
- timestamp
- user
- source
- reason

---

# 21. XLSX EXPORT

Export professional Excel workbooks.

Suggested sheets:

1. Attendance Summary
2. Session Matrix
3. Student Statistics
4. Audit Summary
5. Metadata

Include:

- institution name
- course name
- course code
- section
- instructor
- academic term
- date generated

Use readable widths, frozen headers, filters, consistent typography, borders, and print settings.

---

# 22. PDF EXPORT

Generate print-ready PDFs.

Include:

- institution header/logo if configured
- report title
- class metadata
- date range
- student table
- attendance percentage
- status
- page numbering
- generated timestamp

Use clean white-paper presentation.

---

# 23. GOOGLE AUTHENTICATION

Implement Google Sign-In/OAuth as an identity layer.

Requirements:

- account verification
- user profile retrieval
- secure token lifecycle
- refresh handling
- logout
- offline continuity

Never store OAuth tokens as plaintext in SQLite.

Use OS secure credential storage.

Do not make Google authentication mandatory for local attendance functionality unless explicitly required by the product deployment mode.

---

# 24. ENCRYPTED CLOUD BACKUP

Use Google Drive `appDataFolder` for application-specific backup data. Google documents this as hidden app-specific storage accessible to the application and requiring the `drive.appdata` scope. citeturn0search13

Backup pipeline:

SQLite consistent snapshot
→ compress
→ encrypt
→ hash
→ upload
→ verify
→ record backup metadata

Use authenticated encryption such as AES-256-GCM.

The cloud provider must receive ciphertext, not plaintext attendance data.

Keys must not be uploaded alongside backups.

Implement:

- manual backup
- automatic backup
- backup history
- last successful backup
- failed backup state
- restore
- integrity verification
- snapshot versioning

Never copy a live SQLite database file while it is being modified without using a consistent SQLite snapshot/backup mechanism.

---

# 25. ZERO-KNOWLEDGE BACKUP REQUIREMENT

The application must support a key/recovery design where:

- backup file is encrypted before upload
- Google Drive cannot decrypt it
- API providers cannot decrypt it
- application logs cannot contain the encryption key

Provide recovery options such as:

- recovery passphrase
- encrypted recovery key
- institution-managed recovery mechanism

Clearly warn users that if all encryption keys/recovery material are lost, encrypted backups may be unrecoverable.

---

# 26. OFFLINE STATE MACHINE

Implement:

ONLINE
OFFLINE
SYNCING
ERROR

Offline mode must never make the main application unusable.

Queued network operations should use:

- exponential backoff
- jitter
- bounded retries
- explicit failure states

Do not retry malformed files, invalid schemas, invalid credentials, or permanent API errors indefinitely.

---

# 27. BACKGROUND JOB QUEUE

Create a persistent job queue.

Job types:

IMPORT_DOCUMENT
OCR_DOCUMENT
AI_EXTRACTION
MATCH_DOCUMENT
GENERATE_PDF
GENERATE_XLSX
BACKUP_DATABASE
RESTORE_DATABASE

Fields:

- id
- type
- status
- progress
- retry_count
- created_at
- started_at
- completed_at
- error

Long-running work must not block the UI thread.

Use isolates/background execution where appropriate.

---

# 28. SECURITY REQUIREMENTS

Threat model:

- lost laptop
- stolen database
- malicious import file
- malformed PDF/XLSX
- malicious document content
- compromised AI API
- API key exposure
- OAuth token theft
- accidental data deletion
- database corruption
- AI hallucination
- unauthorized historical modification

Mitigations:

- validate file types
- enforce file-size limits
- sanitize temporary files
- use secure storage
- never log secrets
- never log full student attendance by default
- parameterized DB queries
- strict migrations
- transactions
- audit logs
- encrypted backups
- API timeout limits
- response schema validation
- provider abstraction
- no embedded long-lived vendor API secrets in distributed binaries

If cloud AI is used, clearly communicate that selected documents are transmitted to the configured provider.

---

# 29. API KEY ARCHITECTURE

Never hardcode a Gemini/OpenAI production API key into the desktop executable.

Support:

- user-provided API key
- institution-managed configuration
- optional Alldotdev backend/gateway architecture

Store local secrets in OS secure storage.

Provide a settings screen for AI provider configuration.

---

# 30. UI/UX DESIGN SYSTEM

## Main color

White should be the dominant color.

Recommended:

Background: #FFFFFF
Primary text: #111827
Secondary text: #6B7280
Borders: #E5E7EB
Soft surface: #F8FAFC
Accent violet: #6D5DFB
Success emerald: #10B981
Warning amber: #F59E0B
Danger red: #EF4444

Do not make the application neon.

Use accent color sparingly.

## Visual principles

- white canvas
- subtle gray surfaces
- rounded but restrained cards
- thin borders
- generous spacing
- modern typography
- clear hierarchy
- minimal shadows
- smooth transitions
- consistent iconography
- no visual clutter
- no unnecessary gradients
- no excessive glassmorphism
- accessible contrast
- clear focus states

The product should feel like a modern premium productivity application.

---

# 31. REQUIRED NAVIGATION

Sidebar:

Dashboard
Classes
Students
Attendance
Imports
Reports
Audit Log
Backups
Settings

Top bar:

- current class/context
- global search
- sync/offline indicator
- notifications
- account menu

Use breadcrumbs where useful.

---

# 32. IMPORTANT SCREENS

Implement all of these:

1. Onboarding
2. Login/account setup
3. Dashboard
4. Class list
5. Create class
6. Class overview
7. Student list
8. Student profile
9. Attendance session
10. Attendance grid
11. Historical attendance
12. Import center
13. Import dropzone
14. AI extraction progress
15. Human verification
16. Reports
17. Report preview
18. Audit log
19. Backup center
20. Restore flow
21. Settings
22. AI settings
23. Account settings
24. About
25. Error/empty/loading states

Every screen must have polished states.

---

# 33. DRAG AND DROP

Support native drag-and-drop.

Drop files into:

- Import Center
- Class page
- Attendance page

Show:

- file name
- type
- size
- validation
- processing state
- errors

Allow multiple files.

---

# 34. ACCESSIBILITY

Implement:

- keyboard navigation
- visible focus states
- semantic labels
- readable typography
- sufficient contrast
- tooltips
- predictable tab order
- no color-only information

---

# 35. ERROR HANDLING

Never show raw stack traces to normal users.

Use structured errors:

- validation error
- import error
- AI error
- authentication error
- network error
- database error
- backup error
- permission error

Provide useful recovery actions.

Example:

"Unable to read this spreadsheet. The file appears damaged or uses an unsupported format."

Not:

"Exception: Null check operator used..."

---

# 36. DATA INTEGRITY RULES

AI must NEVER write directly to the database.

The only safe path is:

Document
→ extraction
→ schema validation
→ normalization
→ matching
→ confidence evaluation
→ human verification where needed
→ domain validation
→ database transaction
→ audit log

If any validation step fails, do not commit.

---

# 37. EDGE CASES

Explicitly test:

- poor lighting
- rotated paper
- perspective distortion
- handwritten marks
- faint marks
- overlapping marks
- duplicate names
- duplicate rolls
- missing rolls
- missing names
- changed student names
- mid-semester enrollment
- withdrawal
- same student in multiple classes
- duplicate import
- duplicate AI rows
- wrong date
- wrong class
- empty document
- corrupt PDF
- corrupt XLSX
- unsupported file
- malformed AI JSON
- AI timeout
- no internet
- expired OAuth
- Drive upload failure
- database locked
- interrupted backup
- interrupted import
- application crash during transaction
- partial export
- huge class sizes

---

# 38. PERFORMANCE TARGETS

Aim for:

- startup under ~2 seconds on a normal modern machine
- class page opening under ~500 ms from local DB for normal datasets
- attendance cell update perceived under ~50 ms
- search under ~100 ms for ordinary class sizes
- UI target around 60 FPS
- no blocking UI during AI/OCR/import/export/backup
- efficient virtualized attendance grids
- indexed search fields
- batched DB operations

Test at:

- 100 students
- 1,000 students
- 10,000 students
- 500 sessions
- 50,000+ attendance records

---

# 39. DATABASE INDEXING

Create appropriate indexes, including:

- students(classroom_id, roll_number)
- students(normalized_name)
- enrollments(classroom_id, status)
- attendance_records(session_id, student_id)
- attendance_records(student_id)
- course_sessions(classroom_id, session_date)
- audit_logs(entity_type, entity_id)
- import_jobs(classroom_id, status)
- extraction_rows(import_job_id, review_state)
- attendance_alerts(classroom_id, acknowledged)

Review query plans for common dashboard/search/report queries.

---

# 40. TESTING STRATEGY

Implement:

## Unit tests

- name normalization
- roll normalization
- Levenshtein
- Jaro-Winkler
- candidate generation
- scoring
- attendance calculation
- threshold evaluation
- policy handling
- validation
- encryption utilities

## Database tests

- foreign keys
- uniqueness
- cascading behavior
- transactions
- migrations
- rollback
- concurrent access behavior

## Integration tests

Import
→ extraction fixture
→ normalization
→ matching
→ human approval
→ DB commit
→ report

## UI tests

- navigation
- attendance keyboard controls
- import review
- class creation
- student editing
- report generation

## E2E

Full document-to-attendance workflow.

## Regression fixtures

Create synthetic and representative attendance documents with known expected outputs.

Do not require external AI for deterministic CI tests. Mock AI provider responses.

---

# 41. AI TESTING

Create a provider contract test.

For every AI response:

1. Parse JSON.
2. Validate schema.
3. Validate enum values.
4. Validate confidence ranges.
5. Validate required fields.
6. Validate row indexes.
7. Reject unexpected properties.
8. Normalize.
9. Pass to matcher.

AI extraction tests must include malformed and adversarial responses.

---

# 42. AUDITABILITY

Provide a visible audit log.

Example:

"Attendance changed from Absent → Present"

Metadata:

- Student
- Class
- Session
- Previous state
- New state
- User
- Time
- Source
- Reason

Audit data must not be silently overwritten.

---

# 43. PRIVACY

Default logs must not contain:

- API keys
- OAuth tokens
- full student lists
- attendance content
- raw document images

Crash diagnostics should be privacy-conscious and opt-in where applicable.

---

# 44. CONFIGURATION

Create centralized configuration.

Examples:

- institution name
- logo
- timezone
- date format
- default attendance threshold
- late weight
- AI provider
- AI API settings
- backup frequency
- retention policy
- report branding
- theme settings

Do not hardcode institutional assumptions.

---

# 45. TIMEZONE AND DATES

Store timestamps consistently.

Use local timezone for classroom-facing dates/times.

Avoid ambiguous date parsing.

Provide explicit date formatting.

Attendance dates must not shift unexpectedly when crossing UTC boundaries.

---

# 46. IMPORT DUPLICATE PROTECTION

Hash source files.

If the same file is imported again:

- identify prior import
- show previous import date
- allow intentional reprocess
- avoid silently duplicating attendance

---

# 47. CLASSIFICATION OF IMPORT RESULTS

Each extracted row must end in one of:

MATCHED
REVIEW_REQUIRED
UNMATCHED
REJECTED
COMMITTED

Never silently discard rows.

---

# 48. RESTORE WORKFLOW

Restore must be explicit and safe.

Before restore:

- verify encrypted backup
- verify checksum
- decrypt
- validate SQLite integrity
- validate schema version
- create safety snapshot of current DB
- require explicit confirmation before replacing local state

After restore:

- run integrity checks
- migrate if needed
- reopen repositories
- refresh UI
- record restore audit event

---

# 49. APPLICATION UPDATE STRATEGY

Prepare:

- version metadata
- update-check abstraction
- installer upgrade path
- migration compatibility
- rollback documentation

Never automatically destroy or overwrite the local database during an application update.

---

# 50. BUILD AND PACKAGING

Produce a distribution-ready Windows desktop application.

Required:

- release build
- executable
- installer
- uninstall support
- application icon
- version metadata
- desktop shortcut where appropriate
- clean installation
- upgrade installation
- database migration on upgrade

Also document macOS/Linux packaging architecture.

Create scripts such as:

scripts/build/build_windows.ps1
scripts/build/build_release.ps1

Do not claim packaging is complete until the release build succeeds.

---

# 51. CI/CD

Create CI configuration to run:

- formatting
- static analysis
- unit tests
- integration tests
- build verification
- packaging checks

Do not expose secrets in CI logs.

---

# 52. OBSERVABILITY

Create structured internal logs.

Log:

- lifecycle events
- job states
- import state
- backup state
- errors

Do not log:

- tokens
- API keys
- full attendance datasets
- sensitive document contents

Provide debug mode separately.

---

# 53. DOCUMENTATION

Generate:

README.md
ARCHITECTURE.md
DATABASE.md
AI_PIPELINE.md
SECURITY.md
TESTING.md
DEPLOYMENT.md
TROUBLESHOOTING.md
CHANGELOG.md

Documentation must describe the actual implemented system, not aspirational features.

---

# 54. DEVELOPMENT EXECUTION PROTOCOL

You are an autonomous principal engineer.

Follow this loop:

1. Inspect repository.
2. Determine current state.
3. Create implementation plan.
4. Create/update architecture documentation.
5. Scaffold only what is required.
6. Implement foundation.
7. Run formatting/static analysis.
8. Run tests.
9. Fix failures.
10. Implement next feature.
11. Run relevant tests.
12. Integrate.
13. Run full regression suite.
14. Build release.
15. Inspect the application.
16. Fix UI/UX defects.
17. Rebuild.
18. Verify installer.
19. Update documentation.
20. Produce final completion report.

Do not stop merely because the plan has been written.

---

# 55. AUTONOMOUS DECISION POLICY

When multiple implementation choices are reasonable:

- choose the simplest production-grade option
- prefer stable maintained libraries
- prefer official APIs
- preserve offline-first behavior
- minimize dependencies
- avoid unnecessary complexity
- document significant decisions

Do not repeatedly ask the user to choose between equivalent technical implementations.

Only escalate when a decision requires an external secret, irreversible destructive action, legal/account authorization, or a genuinely product-defining requirement that cannot safely be inferred.

---

# 56. ANTIGRAVITY WORKING RULES

Use Antigravity's ability to operate across editor, terminal, browser, artifacts, and subagents where useful.

Create implementation artifacts and progress documentation as you work.

Use subagents for parallel tasks where beneficial, for example:

Agent A: database/migrations
Agent B: UI/design system
Agent C: import pipeline
Agent D: AI provider adapters
Agent E: testing/security
Agent F: packaging/documentation

Integrate their work rather than allowing conflicting architecture.

Antigravity supports autonomous editor/terminal/browser operation and structured artifacts, so use those capabilities for end-to-end engineering rather than treating the task as a sequence of isolated code snippets.

---

# 57. DO NOT ASK FOR ROUTINE APPROVAL

Do not stop and ask:

"Should I continue?"
"Should I create this file?"
"Should I run tests?"
"Should I fix this error?"
"Do you want me to implement the next phase?"

For routine engineering work, the answer is YES.

Continue autonomously.

If a command fails:

diagnose → fix → rerun.

If a test fails:

inspect → reproduce → fix → rerun.

If UI looks unfinished:

inspect → improve → test again.

If architecture becomes inconsistent:

refactor → test → document.

---

# 58. REQUIRED FINAL VERIFICATION

Before declaring Attendium complete, verify:

[ ] Flutter project builds
[ ] Static analysis passes
[ ] Unit tests pass
[ ] Database tests pass
[ ] Integration tests pass
[ ] UI tests pass where configured
[ ] Release build succeeds
[ ] Installer builds
[ ] Application launches from clean installation
[ ] SQLite migrations work
[ ] Student CRUD works
[ ] Class CRUD works
[ ] Manual attendance works
[ ] Keyboard attendance works
[ ] Historical editing works
[ ] Audit log works
[ ] CSV import works
[ ] XLSX import works
[ ] TXT import works
[ ] PDF import works
[ ] Image import works
[ ] AI provider abstraction works
[ ] Structured JSON validation works
[ ] Matching engine works
[ ] Human review works
[ ] Attendance calculations work
[ ] Threshold alerts work
[ ] XLSX export works
[ ] PDF export works
[ ] Offline mode works
[ ] Google authentication integration is implemented/configured
[ ] Secure token storage works
[ ] Encrypted backup works
[ ] Restore works
[ ] Backup integrity verification works
[ ] Error handling works
[ ] No secrets are committed
[ ] No placeholder TODOs remain in production paths
[ ] Documentation matches implementation
[ ] Release artifacts are generated

---

# 59. DEFINITION OF DONE

The project is NOT DONE if:

- only UI mockups exist
- only database exists
- AI is simulated
- imports are placeholders
- reports are placeholders
- installer is missing
- tests are missing
- error paths are ignored
- offline behavior is broken
- AI can directly modify attendance
- low-confidence matches are silently committed
- audit logs are missing
- backups are unencrypted
- API keys are hardcoded
- database migrations are unsafe
- UI looks like a generic template
- documentation describes features that do not work

The project is DONE only when the entire user workflow works end-to-end.

---

# 60. PRIMARY USER WORKFLOW

The finished application must support this complete flow:

1. Launch Attendium.
2. Create/sign into account if desired.
3. Create academic term.
4. Create class manually OR import class roster.
5. Import CSV/XLSX/TXT/PDF/image.
6. Parse document.
7. Extract structured rows.
8. Normalize data.
9. Match rows against local roster.
10. Display confidence.
11. Human verifies uncertain rows.
12. Create attendance session.
13. Commit attendance transaction.
14. Calculate attendance.
15. Display threshold status.
16. Edit attendance later if required.
17. Record audit trail.
18. Generate PDF/XLSX report.
19. Encrypt local database snapshot.
20. Upload encrypted backup to Google Drive appDataFolder.
21. Restore from backup when needed.

---

# 61. PRODUCT QUALITY BAR

The final product should feel:

- reliable
- fast
- calm
- professional
- academic
- modern
- simple
- elegant
- trustworthy

Avoid:

- clutter
- excessive animations
- huge dashboards
- unnecessary gradients
- excessive color
- gimmicky AI visuals
- fake analytics
- placeholder data in production
- generic CRUD-only appearance

White is the dominant visual language.

---

# 62. IMPORTANT ARCHITECTURAL PRINCIPLE

Treat the system as:

LOCAL DATABASE
↓
HUMAN VERIFICATION
↓
DETERMINISTIC MATCHING
↓
AI EXTRACTION
↓
DOCUMENT/OCR

Not:

AI
↓
DATABASE

The local database and verified human decisions are authoritative.

---

# 63. FIRST EXECUTION

Immediately begin by:

1. Inspecting the workspace.
2. Creating the project architecture.
3. Creating the documentation files.
4. Creating the Flutter application.
5. Configuring dependencies.
6. Creating database migrations.
7. Building the design system with WHITE as the dominant color.
8. Implementing the shell/navigation.
9. Implementing core domain/database layers.
10. Implementing feature modules.
11. Implementing testing infrastructure.
12. Continuing through the full roadmap without waiting for routine approval.

Maintain a machine-readable progress file:

docs/BUILD_STATUS.md

Update it after every major milestone.

Use:

- completed
- in_progress
- blocked
- failed
- verified

Never mark a feature "completed" until verified.

---

# 64. FINAL RESPONSE TO USER

When the entire project is actually built and verified, provide:

1. What was implemented.
2. Architecture summary.
3. Test results.
4. Build/package results.
5. Location of installer/build artifacts.
6. Known limitations, if any.
7. Any configuration/credentials the user must supply.
8. Exact launch instructions.
9. Backup/restore instructions.
10. Security notes.

Do not claim 100% completion if any mandatory requirement remains unverified.

---

# 65. START NOW

Begin implementation immediately.

Do not merely explain how to build Attendium.

Build Attendium.

Inspect → plan → implement → test → repair → verify → package → document.

Continue until the Definition of Done is satisfied.
