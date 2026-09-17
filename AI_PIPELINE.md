# Attendium — AI Extraction Pipeline & Schema Contract

## 1. Core Principle
AI is strictly an extraction assistant. It reads visual and textual documents and transforms them into structured JSON. It never maps records to database IDs, never mutates local state, and never overwrites verified data.

---

## 2. Canonical JSON Schema Contract

Every provider must output JSON conforming strictly to this specification:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "AttendanceExtraction",
  "type": "object",
  "additionalProperties": false,
  "required": ["document_date", "course_name", "course_code", "section", "rows"],
  "properties": {
    "document_date": {
      "type": ["string", "null"],
      "description": "ISO-8601 Date (YYYY-MM-DD) if visible, else null"
    },
    "course_name": {
      "type": ["string", "null"]
    },
    "course_code": {
      "type": ["string", "null"]
    },
    "section": {
      "type": ["string", "null"]
    },
    "rows": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["row_index", "roll_number", "name", "attendance_status", "confidence", "evidence"],
        "properties": {
          "row_index": {
            "type": "integer",
            "minimum": 1
          },
          "roll_number": {
            "type": ["string", "null"]
          },
          "name": {
            "type": ["string", "null"]
          },
          "attendance_status": {
            "type": "string",
            "enum": ["present", "absent", "late", "excused", "unknown"]
          },
          "confidence": {
            "type": "number",
            "minimum": 0.0,
            "maximum": 1.0,
            "description": "Visual legibility confidence only"
          },
          "evidence": {
            "type": "string",
            "description": "Brief description of visual mark (e.g., 'check mark in col 3', 'P written in pen')"
          }
        }
      }
    }
  }
}
```

---

## 3. System Prompt Specification

```
You are an attendance-document extraction engine.
Extract only information visibly present in the supplied document.
Do not infer or invent student identities, roll numbers, dates, course details, or attendance statuses.
Preserve the document's row order.
If a value cannot be read confidently, return null.
If an attendance mark is ambiguous, return unknown.
Do not decide which local roster student a row represents.
Identity matching is performed separately by deterministic software.
Your confidence score measures visual extraction confidence only.
Provide concise evidence describing what is visibly present.
Return only schema-valid JSON.
```

---

## 4. Multi-Stage Ingestion Pipeline

```
1. Ingest: File dropped or selected (CSV, XLSX, TXT, PDF, Image).
2. Triage:
   - If Tabular (CSV/XLSX/TXT): Deterministic column parser parses directly. Zero cloud transmission.
   - If PDF with text layer: Extract text lines and parse tabular columns.
   - If Image or Scanned PDF: Apply image preprocessing (deskew, contrast enhancement, grayscale) and invoke configured AI provider.
3. Validate: Response parsed against Canonical JSON schema. Rejection on unknown keys or invalid enums.
4. Normalize:
   - Unicode NFKC normalization
   - Lowercase & whitespace trimming
   - Roll number punctuation removal
   - OCR character disambiguation (O/0, I/1/l, S/5)
5. Fuzzy Matching Engine:
   - Compute RollScore, NameScore (Levenshtein + Jaro-Winkler + Token Sort), AliasScore, ContextScore.
   - Composite FinalScore = 0.40*Roll + 0.35*Name + 0.15*Alias + 0.10*Context.
6. Review Classification:
   - ≥ 0.95: Auto-Match Candidate (Green)
   - 0.85 - 0.949: Review Recommended (Amber)
   - 0.70 - 0.849: Confirmation Required (Orange)
   - < 0.70: Unmatched (Red)
7. Human Verification:
   - User reviews dual-pane UI with source document zoomed to row evidence.
   - User accepts, edits, links to student, creates new student, or rejects.
8. Transaction Commit:
   - Records written to `course_sessions` and `attendance_records` inside atomic SQLite transaction.
   - `audit_logs` records change event.
```
