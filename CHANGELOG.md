# Changelog

All notable changes to Attendium will be documented in this file.

## [1.0.0] - 2026-09-17
### Added
- Complete offline-first desktop attendance management architecture.
- SQLite WAL mode database engine with foreign-key enforcement and 14 relational tables.
- Weighted attendance calculation engine with configurable policies (Safe, At Risk, Short, Debarred).
- Composite fuzzy matching engine (Levenshtein, Jaro-Winkler, Token Similarity, OCR heuristics).
- Multimodal document ingestion supporting CSV, XLSX, TXT, PDF, and image formats.
- AI Provider abstraction for Gemini (official structured schema) and OpenAI.
- Dual-pane human-in-the-loop verification workbench.
- Keyboard-first attendance taking grid with single-key shortcuts and undo/redo.
- Immutable audit log system tracking all attendance modifications.
- Multi-sheet Excel (.xlsx) and print-ready PDF reporting.
- Zero-knowledge AES-256-GCM encrypted Google Drive cloud backup and restore.
- Comprehensive automated test suite and Windows build pipeline.
