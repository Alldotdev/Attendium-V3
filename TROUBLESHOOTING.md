# Attendium — Troubleshooting Manual

## 1. Common Diagnostics & Solutions

### Database Issues
- **Error**: `database is locked (5)`
  - **Cause**: Concurrent write connection without WAL mode.
  - **Resolution**: Ensure `PRAGMA journal_mode = WAL;` is set. Attendium runs write transactions through a synchronized queue with 5000ms busy timeout.

### AI Extraction Issues
- **Error**: `Invalid schema: missing required property 'rows'`
  - **Cause**: AI model returned free-form text or hallucinated markdown wrapper.
  - **Resolution**: Use official schema-constrained JSON mode in Gemini (`responseSchema`) or OpenAI (`response_format: { type: "json_schema" }`).

### Document Ingestion
- **Error**: `Duplicate file detected`
  - **Cause**: The exact file hash (SHA-256) matches an earlier import.
  - **Resolution**: Use the "Re-process intentionally" toggle in the Import Center if updating a previously ingested roster.
