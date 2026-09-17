# Attendium — Testing & Quality Assurance Strategy

## 1. Test Taxonomy

Attendium enforces a multi-tier testing strategy:

```
[E2E Document-to-Attendance Pipeline]
          ▲
          │
[UI & Integration Tests: Keyboard Grid, Split-View Workbench]
          ▲
          │
[Database & Migration Tests: Foreign Keys, Transactions, WAL]
          ▲
          │
[Unit Tests: Calculations, Fuzzy Matcher, Normalization, AES-GCM]
```

---

## 2. Automated Test Commands

### Run All Unit Tests
```powershell
flutter test test/unit/
```

### Run Database Integrity Tests
```powershell
flutter test test/database/
```

### Run Integration Tests
```powershell
flutter test test/integration/
```

### Run Static Analysis
```powershell
flutter analyze
```

---

## 3. Test Suites

### 3.1 Unit Test Coverage
- **Attendance Calculation**: Weighted units, configurable late weight, zero sessions handling, debarment/short/at-risk thresholds.
- **Normalization**: Unicode NFKC, case folding, diacritics removal, OCR character ambiguity substitutions (O&harr;0, I/l&harr;1, S&harr;5).
- **Fuzzy Matching**: Levenshtein distance, Jaro-Winkler, Token sort, alias resolution, candidate pruning.
- **AI Schema Validation**: Strict canonical JSON validation, invalid type rejection, unexpected key rejection.
- **Cryptography**: AES-256-GCM encryption/decryption roundtrip, PBKDF2 key derivation, authentication tag tamper rejection.

### 3.2 Database & Migration Tests
- Foreign key cascading deletes and constraints.
- Unique constraints (`(student_id, classroom_id)`, `(session_id, student_id)`).
- Atomic transaction rollbacks on failure.
- SQLite WAL mode verification.
