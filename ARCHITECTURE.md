# Attendium — Architecture Guide

## 1. System Design Philosophy

Attendium is designed around a single immutable rule:
> **The local database and verified human decisions are authoritative. AI is an extraction assistant, never the source of truth.**

```
+-------------------------------------------------------------------+
|                        PRESENTATION LAYER                         |
|   Flutter Desktop UI  |  Keyboard Grid  |  Split-View Review      |
|   Riverpod State Notifiers & Stream Providers                     |
+---------------------------------+---------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
|                        APPLICATION LAYER                          |
|   Use Cases: TakeAttendance, IngestDocument, CalculateAttendance  |
|   DTOs, Command Handlers, Background Job Orchestration            |
+---------------------------------+---------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
|                          DOMAIN LAYER                             |
|   Entities: Classroom, Student, Session, AttendanceRecord, Policy |
|   Services: FuzzyMatchingEngine, AttendanceCalculationEngine       |
|   Repository Interfaces (Contract-first)                          |
+---------------------------------+---------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
|                      INFRASTRUCTURE LAYER                         |
|   Drift ORM / SQLite Native FFI (WAL mode, Foreign Keys)          |
|   AI Adapters: GeminiProvider, OpenAiProvider, DeterministicLocal |
|   Export Services: ExcelGenerator, PdfGenerator                   |
|   Cloud Backup: AES-256-GCM + Google Drive AppData Folder         |
+-------------------------------------------------------------------+
```

---

## 2. Directory Structure

```
lib/
  core/
    database/          # SQLite Drift connection, WAL pragmas, migrations
    encryption/        # AES-256-GCM authenticated cipher & PBKDF2 key derivation
    networking/        # Dio HTTP client, interceptors, retry with backoff
    logging/           # Structured application logger (scrubbed secrets)
    errors/            # Domain Failure hierarchies & AppExceptions
    result/            # Result<T, E> monad for predictable error flows
    utilities/         # Date formatters, file hashing (SHA-256), string sanitizers
    jobs/              # Background worker isolates and persistent job queue
  domain/
    entities/          # Classroom, Student, Session, AttendanceRecord, AuditLog
    value_objects/     # RollNumber, NormalizedName, MatchScore, Confidence
    repositories/      # Abstract interfaces for all persistence operations
    services/          # Calculation engine, composite fuzzy matcher
  application/
    use_cases/         # Business workflows (RecordAttendance, ProcessImportJob)
    dto/               # Data transfer contracts between UI and domain
    services/          # Backup coordinator, notification dispatcher
  features/
    dashboard/         # Metric cards, today's classes, threshold alerts
    classrooms/        # Class setup, policies, roster management
    students/          # Student directory, aliases, profile & attendance history
    attendance/        # Keyboard-first grid, session matrix, historical editor
    imports/           # Document dropzone, parser pipeline, progress states
    matching/          # Human-in-the-loop split-view review workbench
    reports/           # Class & student summaries, XLSX export, PDF generator
    backups/           # Local snapshot encryption, Google Drive backup & restore
    audit/             # Immutable audit log viewer with before/after diffs
    settings/          # Institution branding, AI API credentials, policy presets
  shared/
    widgets/           # Buttons, dialogs, badges, virtualized data tables
    design_system/     # Color tokens, typography, spacing, elevations
    extensions/        # BuildContext extensions, String & DateTime helpers
    validators/        # Input validation logic
```

---

## 3. Data Flow Pipelines

### 3.1 Attendance Ingestion Pipeline
```
Uploaded File (CSV, XLSX, PDF, Image)
  │
  ▼
[Deterministic File Sniffer & SHA-256 Hash] ──(Duplicate detected?)──► [Prompt Reuse]
  │
  ├─► Tabular (CSV/XLSX/TXT) ──► Deterministic Table Parser ────────┐
  │                                                                 │
  └─► Image / Scanned PDF ────► Preprocessing (Deskew/Contrast)     │
                                 │                                  │
                                 ▼                                  │
                                [AI Provider: Gemini/OpenAI]        │
                                 │                                  │
                                 ▼                                  │
                                [JSON Schema Validator]             │
                                 │                                  │
                                 └──────────────────────────────────┤
                                                                    ▼
                                                    [Student Normalizer]
                                                                    │
                                                                    ▼
                                                    [Composite Fuzzy Matcher]
                                                                    │
                                                                    ▼
                                                    [Confidence Evaluator]
                                                                    │
                                    ┌───────────────────────────────┴──────────────────────────────┐
                                    ▼                                                              ▼
                        [High Confidence (≥0.95)]                                      [Ambiguous / Low (<0.95)]
                                    │                                                              │
                                    │                                                              ▼
                                    │                                                 [Human Verification Workbench]
                                    │                                                              │
                                    └───────────────────────────────┬──────────────────────────────┘
                                                                    ▼
                                                      [Domain Transaction Commit]
                                                                    │
                                                                    ▼
                                                      [Authoritative SQLite DB]
                                                                    │
                                                                    ▼
                                                      [Immutable Audit Log]
```

### 3.2 Data Flow Guarantees
1. **Zero Raw Writes**: AI extractions never commit directly to the database.
2. **Schema Invariance**: Every AI response must pass JSON Schema validation. Unexpected keys or missing required fields cause an immediate validation error.
3. **Transaction Isolation**: Commits to `attendance_records` occur in an atomic SQLite transaction alongside the `course_sessions` update and `audit_logs` record.
