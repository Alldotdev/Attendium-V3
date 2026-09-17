# Attendium — Security Architecture & Threat Model

## 1. Threat Model & Mitigations

| Threat Vector | Potential Impact | Attendium Mitigation |
|---|---|---|
| **Stolen/Lost Laptop** | Local database accessed by unauthorized third parties | Application supports database file encryption; zero plaintext credentials stored on disk; OS keychain integration. |
| **Malicious Import File** | Arbitrary code execution or buffer overflow | Deterministic parsers with strict size limits (50MB max); strict schema validation before processing. |
| **Compromised AI Provider** | Hallucinated marks, injection payloads | Canonical schema-constrained output; strict JSON parsing; visual confidence separated from identity matching; human verification boundary. |
| **API Key / Token Leakage** | Unauthorized usage and account compromise | Secrets never committed; stored in OS secure credentials (Windows Credential Manager); scrubbed from all logs. |
| **Cloud Storage Breach** | Exposure of student attendance records on Google Drive | Zero-knowledge authenticated encryption: database snapshots are encrypted with AES-256-GCM locally before upload; keys never leave machine. |
| **Unauthorized Historical Changes** | Grade/Attendance tampering | Immutable SQLite audit logs for every modification with before/after state, user ID, and mandatory reason. |

---

## 2. Zero-Knowledge Backup Pipeline

```
[Consistent SQLite Snapshot]
       │
       ▼
[GZIP Compression]
       │
       ▼
[Key Derivation: PBKDF2-HMAC-SHA256 (100,000 iterations + 32-byte salt)]
       │
       ▼
[AES-256-GCM Encryption (256-bit Key, 96-bit Nonce, 128-bit Auth Tag)]
       │
       ▼
[Snapshot Hash Verification (SHA-256)]
       │
       ▼
[Upload to Google Drive appDataFolder (Hidden from root drive)]
```

### Critical Security Rules
1. **Zero Key Upload**: The encryption passphrase and derived key are NEVER sent to Google Drive or any remote server.
2. **Authenticated Cipher**: AES-256-GCM ensures both confidentiality and cryptographic integrity. Tampered backups cannot be decrypted.
3. **Safe Restore Process**: Prior to restoring an encrypted backup, Attendium creates an emergency local snapshot of the active database and verifies the integrity of the decrypted SQLite header and schema.
