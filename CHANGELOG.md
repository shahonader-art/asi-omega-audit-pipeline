# Changelog

## [1.0.0] — 2026-02-07

### Core Pipeline
- SHA-256 file hashing with NIST FIPS 180-4 compliance
- RFC 6962 Merkle tree with domain separation (0x00 leaf, 0x01 internal)
- DoD (Declaration of Data) report generation with schema v2
- 9-check verification system (verify.ps1)
- GPG detached signature support (.asc files)
- OpenTimestamps blockchain anchoring (with local stub fallback)
- NTP drift measurement (cross-platform)
- Human-readable report generation (rapport.txt)

### User Interface
- CLI entry point (audit.ps1) with -Path, -Verify, -Sign, -Timestamp, -Full, -Help
- GUI (audit-gui.ps1) with dark theme, folder browser, audit/verify/report buttons
- Norwegian (nb-NO) user-facing text in CLI and GUI
- One-command installer (install.ps1)
- Standalone .exe builder (build-exe.ps1)

### Testing
- 8 acceptance criteria (C1-C8) with 50+ individual checks
- C1: Determinism — same inputs produce identical outputs
- C2: Tamper detection — file modifications caught
- C3: Merkle correctness — RFC 6962 compliance verified
- C4: No silent failures — all errors produce non-zero exits
- C5: Timestamp trust — time validation and OTS anchoring
- C6: End-to-end — full pipeline chain of custody
- C7: Crypto stress — 13 in-process cryptographic property tests
- C8: User workflow — 9 real-user scenarios
- 4 utility test suites (golden hashes, Merkle edge cases, determinism, error paths)
- Shared crypto library (lib/crypto.ps1) as single source of truth

### Architecture
- Shared cryptographic library (lib/crypto.ps1)
- Self-integrity verification via script_hashes in DoD schema
- CRLF normalization for cross-platform hash consistency
- PS 7.5 compatibility (JSON string templates, regex extraction)

### Documentation
- Architecture guide (docs/ARCHITECTURE.md)
- Security model (docs/SECURITY.md)
- Data models (docs/DATA-MODELS.md)
- Golden hashes baseline (docs/golden-hashes.json)

### CI/CD
- GitHub Actions: CI pipeline with full test suite
- GitHub Actions: Verify pipeline (DoD + Merkle + Manifest)
