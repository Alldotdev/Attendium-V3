# Attendium V3 — Comprehensive Project Documentation & Technical Specification

<p align="center">
  <img src="assets/images/alldotdev_logo.png" alt="Alldotdev Logo" width="160" />
</p>

<p align="center">
  <strong>Enterprise Offline-First Attendance Intelligence Platform</strong><br>
  <em>Developed by Alldotdev • Built with Flutter Desktop & SQLite</em>
</p>

---

## Table of Contents

1. [Executive Summary & System Objectives](#1-executive-summary--system-objectives)
2. [Architectural Principles & Clean Architecture Layers](#2-architectural-principles--clean-architecture-layers)
3. [Relational Data Model & SQLite Persistence](#3-relational-data-model--sqlite-persistence)
4. [Multi-Model AI Vision Extraction Engine](#4-multi-model-ai-vision-extraction-engine)
5. [Deterministic Fuzzy Matching & Identity Resolution](#5-deterministic-fuzzy-matching--identity-resolution)
6. [Dynamic Student Roster Management](#6-dynamic-student-roster-management)
7. [Live Attendance Taking & Keyboard-First Matrix](#7-live-attendance-taking--keyboard-first-matrix)
8. [Session Duration Analytics & Student History Timelines](#8-session-duration-analytics--student-history-timelines)
9. [Audit Trail, Compliance & Risk Classification](#9-audit-trail-compliance--risk-classification)
10. [Export Engines (Excel & Print-Ready PDF)](#10-export-engines-excel--print-ready-pdf)
11. [Security, Privacy & Local Credential Storage](#11-security-privacy--local-credential-storage)
12. [Alldotdev Brand System & Customer Support](#12-alldotdev-brand-system--customer-support)
13. [Testing, Build Verification & Windows Deployment](#13-testing-build-verification--windows-deployment)

---

## 1. Executive Summary & System Objectives

**Attendium V3** is an enterprise-grade desktop attendance management and institutional analytics application created by **Alldotdev**. 

Academic institutions and universities grapple with complex attendance workflows:
- Teachers frequently capture attendance on handwritten physical sign-in sheets, paper registers, whiteboard lists, spreadsheets, or printouts.
- Translating these records into digital rosters is slow, prone to human error, and delays the identification of at-risk students.
- Cloud-only software fails when campus internet is spotty, raises student privacy concerns, and forces lock-in.

Attendium addresses these challenges through a hybrid architecture:
1. **Offline-First Authority**: An embedded SQLite database with Write-Ahead Logging (`WAL`) provides zero-latency operations, transactional safety, and full offline autonomy.
2. **Multimodal Vision AI**: Educators can upload photos or documents of attendance sheets. Attendium connects to leading Vision AI models (Google Gemini, OpenAI GPT-4o, Anthropic Claude) to extract raw student rows with structured JSON contracts.
3. **Deterministic Identity Resolution**: Extracts are mapped to authoritative student rosters using composite fuzzy matching (Levenshtein distance, Jaro-Winkler similarity, OCR digit normalization).
4. **Interactive Roster Expansion**: If an uploaded sheet contains students not enrolled in the class, Attendium gives teachers the immediate option to register them with a single click.
5. **Real-Time Duration & Timeline Insights**: Teachers can view student attendance records across the entire semester, inspecting exact sessions attended and missed.

---

## 2. Architectural Principles & Clean Architecture Layers

Attendium adheres to Feature-First Clean Architecture, ensuring complete decoupling between presentation, business rules, persistence, and external AI providers.

```
┌─────────────────────────────────────────────────────────────┐
│                     PRESENTATION LAYER                      │
│   Screens (Dashboard, Classrooms, AttendanceGrid, Support)  │
│   Dialogs (ImportRoster, ScanAttendance, StudentHistory)    │
│   State Management: Riverpod (Notifiers, FutureProviders)   │
└──────────────────────────────┬──────────────────────────────┘
                               │ uses
┌──────────────────────────────▼─────────────────────────────┐
│                      APPLICATION LAYER                      │
│   Use Cases, Document Ingestion Pipelines, Workflows        │
└──────────────────────────────┬──────────────────────────────┘
                               │ interacts with
┌──────────────────────────────▼─────────────────────────────┐
│                        DOMAIN LAYER                         │
│   Entities: Classroom, Student, Session, AttendanceRecord   │
│   Enums: AttendanceStatus, MatchConfidence, AuditAction     │
│   Services: FuzzyMatcher, AttendanceCalculator, Normalizer │
│   Repository Interfaces (Zero third-party dependencies)     │
└──────────────────────────────▲──────────────────────────────┘
                               │ implemented by
┌──────────────────────────────┴─────────────────────────────┐
│                    INFRASTRUCTURE LAYER                     │
│   SQLite Database (Drift / sqlite3 WAL)                     │
│   AI Vision Providers (Gemini, Claude, OpenAI, Local)       │
│   Document Processing (Syncfusion Excel/PDF, Tabular)       │
│   Local Config & Secure Storage                             │
└─────────────────────────────────────────────────────────────┘
```

### Core Architectural Directives
- **Zero Business Logic in UI**: Screen widgets are purely declarative. State mutation and business algorithms live strictly in Domain Services and Riverpod Notifiers.
- **Fail-Safe Operation**: If external network or AI API endpoints fail, the system falls back to deterministic local parsing or manual grid entry without interrupting the user.
- **Single Source of Truth**: The local SQLite database is the authoritative master. Cloud features are strictly additive.

---

## 3. Relational Data Model & SQLite Persistence

The data engine runs on SQLite 3 in Write-Ahead Logging mode (`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;`).

### Entity Relationship Model

```
                    ┌──────────────┐
                    │    users     │
                    └──────┬───────┘
                           │ 1
                           │ has many
                           ▼ N
                 ┌───────────────────┐
                 │  academic_terms   │
                 └─────────┬─────────┘
                           │ 1
                           │ contains
                           ▼ N
                 ┌───────────────────┐
                 │    classrooms     │
                 └─────┬───────┬─────┘
                       │ 1     │ 1
        has sessions   │       │ has enrollments
                       ▼ N     ▼ N
            ┌──────────────┐ ┌──────────────┐
            │course_sessions│ │ enrollments  │
            └──────┬───────┘ └──────┬───────┘
                   │ 1              │ N
                   │ records        │ links to
                   ▼ N              ▼ 1
          ┌───────────────────┐ ┌──────────────┐
          │attendance_records │ │   students   │
          └───────────────────┘ └──────┬───────┘
                                       │ 1
                                       │ has aliases
                                       ▼ N
                               ┌──────────────┐
                               │student_aliases│
                               └──────────────┘
```

### Table Definitions & Primary Keys

1. **`users`**: System user profiles (`id`, `username`, `display_name`, `email`, `role`, `created_at`).
2. **`academic_terms`**: Semesters or quarters (`id`, `name`, `start_date`, `end_date`, `status`).
3. **`classrooms`**: Course sections (`id`, `term_id`, `code`, `name`, `section`, `color_hex`, `is_archived`).
4. **`students`**: Authoritative student roster (`id`, `roll_number`, `normalized_roll`, `first_name`, `last_name`, `full_name`, `email`, `is_active`).
5. **`enrollments`**: Classroom membership join table (`id`, `classroom_id`, `student_id`, `enrolled_at`).
6. **`student_aliases`**: Alternative identifiers, Nicknames, or OCR variants linked to a student (`id`, `student_id`, `alias_value`, `source`).
7. **`course_sessions`**: Scheduled class meetings (`id`, `classroom_id`, `session_date`, `start_time`, `session_type`, `topic`, `status`).
8. **`attendance_records`**: Core attendance marks (`id`, `session_id`, `student_id`, `status`, `remarks`, `marked_at`, `source`).
9. **`attendance_policies`**: Grading and attendance policies per class (`classroom_id`, `minimum_percentage`, `late_penalty_weight`, `excused_counts_as_present`).
10. **`audit_logs`**: Immutable history of every data alteration (`id`, `entity_type`, `entity_id`, `action`, `previous_state`, `new_state`, `reason`, `timestamp`).
11. **`import_jobs` & `extraction_rows`**: Raw document ingestion staging and verification records.

---

## 4. Multi-Model AI Vision Extraction Engine

Attendium allows teachers to configure and switch between multiple vision providers on demand via `lib/infrastructure/ai/`:

### Supported Vision Providers

1. **Google Gemini Provider** (`gemini_provider.dart`):
   - Models: `gemini-2.5-flash`, `gemini-1.5-pro`
   - Uses direct Google Generative Language REST APIs with multimodal inline base64 image encoding.
   - Enforces structured JSON output schema via `response_mime_type: "application/json"`.

2. **OpenAI Provider** (`openai_provider.dart`):
   - Models: `gpt-4o`, `gpt-4o-mini`
   - Leverages `chat/completions` endpoint with `response_format: { type: "json_object" }`.

3. **Anthropic Claude Provider** (`claude_provider.dart`):
   - Models: `claude-3-5-sonnet`, `claude-3-7-sonnet`
   - Direct Anthropic Messages API with image source blocks and strict system prompt constraints.

4. **Deterministic Local Provider** (`deterministic_local_provider.dart`):
   - Fully offline fallback parser using regex tokenization and coordinate pattern heuristics.

### Strict Extraction JSON Schema

All AI models must conform to this contract:
```json
{
  "document_type": "attendance_sheet",
  "detected_date": "2026-09-17",
  "confidence": 0.96,
  "rows": [
    {
      "raw_text": "21-CS-104  Muhammad Ali  P",
      "extracted_roll": "21-CS-104",
      "extracted_name": "Muhammad Ali",
      "status": "PRESENT",
      "confidence": 0.98,
      "bounding_box": [120, 45, 800, 75]
    }
  ]
}
```

---

## 5. Deterministic Fuzzy Matching & Identity Resolution

When an AI extraction or OCR scan produces student rows, Attendium resolves noisy text to enrolled students using a deterministic 4-stage matching algorithm:

### Scoring Formula
$$\text{CompositeScore} = (W_{\text{roll}} \times S_{\text{roll}}) + (W_{\text{name}} \times S_{\text{name}}) + (W_{\text{alias}} \times S_{\text{alias}}) + (W_{\text{context}} \times S_{\text{context}})$$

- **$W_{\text{roll}} = 0.40$**: Exact or normalized roll number match.
- **$W_{\text{name}} = 0.35$**: Jaro-Winkler similarity with token sorting.
- **$W_{\text{alias}} = 0.15$**: Known alias or OCR confusion match.
- **$W_{\text{context}} = 0.10$**: Serial order sequence alignment.

### Confidence Bands
- **Green (Confidence $\ge 0.85$)**: High confidence; automatically matched.
- **Amber ($0.65 \le \text{Confidence} < 0.85$)**: Ambiguous match; flagged for teacher confirmation.
- **Red ($\text{Confidence} < 0.65$)**: Unrecognized student. Triggers the **"Add to Roster"** dialog.

---

## 6. Dynamic Student Roster Management

Educators have full control over class rosters:

### Multi-Format Roster Ingestion
In [import_students_dialog.dart](file:///c:/Users/Usman%20Khan/Desktop/Main/Mini%20projects/Attendium%20V3/lib/presentation/widgets/import_students_dialog.dart), educators can import rosters from:
1. **Excel & Spreadsheets** (`.xlsx`, `.xls`, `.csv`): Automatically detects headers (`Roll No`, `Reg No`, `Student Name`, `Full Name`, `Email`).
2. **PDF Documents**: Extracts tabular text streams and matches regex patterns.
3. **Images & Photos**: Passes roster photos through the Vision AI extraction pipeline.
4. **Direct Text / OCR Paste**: Teachers can paste raw tab-separated or line-separated text. A real-time listener updates the parsed preview table live.

### Interactive "Add to Roster" Prompt
When scanning attendance for a session:
- If a student roll number or name in the document is not present in the classroom roster, Attendium highlights it with a notification badge.
- Teachers can click **"Add to Roster"** to immediately enroll the student, choose their section, and assign them an authoritative ID without leaving the attendance session.

---

## 7. Live Attendance Taking & Keyboard-First Matrix

For in-class attendance taking, [attendance_grid_screen.dart](file:///c:/Users/Usman%20Khan/Desktop/Main/Mini%20projects/Attendium%20V3/lib/presentation/screens/attendance_grid_screen.dart) provides a high-speed interface:

### Keyboard Hotkeys
- `P`: Mark Present (Green)
- `A`: Mark Absent (Red)
- `L`: Mark Late (Amber)
- `E`: Mark Excused (Blue)
- `U`: Mark Unmarked (Slate)
- `Arrow Keys`: Navigate cells rapidly
- `Ctrl + Z`: Undo last action
- `Ctrl + Shift + Z`: Redo last action
- `Ctrl + S`: Commit changes to database

---

## 8. Session Duration Analytics & Student History Timelines

In addition to whole-class statistics, Attendium features the **Student Attendance History Dialog** (`student_attendance_history_dialog.dart`):

### Features
- **Duration Metrics**: Shows total sessions held, sessions attended, sessions missed, late arrivals, and attendance percentage.
- **Chronological Timeline**: Lists every session date with the student's status, session topic, and teacher remarks.
- **Filterable**: Filter by "Missed Sessions Only" or "All Sessions".
- **One-Click Correction**: Teachers can correct historical attendance marks directly from the history timeline with automatic audit logging.

---

## 9. Audit Trail, Compliance & Risk Classification

### Immutable Audit Engine
Every modification to an attendance record creates a row in `audit_logs`:
- Old Status &rarr; New Status
- Changed by (`user_id`)
- Timestamp (`ISO-8601`)
- Justification reason (e.g., *"Medical certificate submitted"*, *"Corrected OCR mismatch"*)

### Academic Risk Classifications
- **Safe** ($\ge 85\%$): Student in good standing.
- **At Risk** ($75\% - 84\%$): Warning state; automated notification badge.
- **Short** ($60\% - 74\%$): Below institutional threshold.
- **Debarred** ($< 60\%$): Ineligible for final examination.

---

## 10. Export Engines (Excel & Print-Ready PDF)

### Styled Microsoft Excel Workbooks (`.xlsx`)
- Generated via [excel_generator.dart](file:///c:/Users/Usman%20Khan/Desktop/Main/Mini%20projects/Attendium%20V3/lib/infrastructure/export/excel_generator.dart).
- Features frozen headers, custom column widths, colored status cells (`P` green, `A` red), and automated percentage formulas.

### Academic PDF Reports
- Generated via [pdf_generator.dart](file:///c:/Users/Usman%20Khan/Desktop/Main/Mini%20projects/Attendium%20V3/lib/infrastructure/export/pdf_generator.dart).
- Formatted with institutional header, course code, teacher name, student progress bars, and official signature verification blocks.

---

## 11. Security, Privacy & Local Credential Storage

1. **Zero Data Telemetry**: Student names, roll numbers, and attendance records never leave the local machine except during explicit AI vision extraction requests.
2. **API Key Security**: AI credentials are stored locally in the user's `Documents\Attendium\ai_settings.json` file, outside the repository tree, preventing accidental leaks.
3. **Encrypted Cloud Backups**: Database backups are encrypted with AES-256-GCM before export.

---

## 12. Alldotdev Brand System & Customer Support

Attendium includes a dedicated customer support section aligned with Alldotdev brand guidelines:

### Corporate Contact Details
- **Company**: Alldotdev
- **Helpline / Phone**: `03420554448` (`+92 342 0554448`)
- **Support Email**: `alldotdev1@gmail.com`
- **Website**: `www.alldotdev.com`
- **Support Hours**: 
  - Monday – Friday: `9:00 AM – 6:00 PM PKT`
  - Saturday: `10:00 AM – 3:00 PM PKT`

### UI Design System
- **Backgrounds**: Slate Dark & Soft Surface (`#F8FAFC`, `#0F172A`)
- **Primary Brand Accent**: Alldotdev Coral Crimson (`#FF3B30` / `#E11D48`) & Iris Indigo (`#6366F1`)
- **Product vs. Company Separation**: Attendium is the software product; Alldotdev is the vendor and technical support entity.

---

## 13. Testing, Build Verification & Windows Deployment

### Automated Test Suite
- **Unit Tests**: AI contract parsing, Jaro-Winkler string similarity, calculation rules.
- **DAO Integration Tests**: In-memory SQLite transaction rollback, CRUD operations.
- **Pipeline Tests**: Full document ingestion simulation.

Run the test suite:
```powershell
flutter test
```

### Windows Desktop Build
To compile a standalone, optimized Windows x64 binary:
```powershell
flutter build windows --release
```
The output directory will contain:
```
build\windows\x64\runner\Release\
├── attendium.exe
├── flutter_windows.dll
└── data\
```

---

*Attendium V3 is an intellectual property of Alldotdev. Developed for educators worldwide.*
