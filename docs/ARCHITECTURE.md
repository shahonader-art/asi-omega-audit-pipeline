# Architecture

## Overview

The ASI-Omega Audit Pipeline is a PowerShell 7+ forensic audit tool that proves files have not been tampered with. It produces a cryptographic chain: file hashes → manifest → Merkle tree → signed Declaration of Done (DoD).

## Pipeline Phases

```
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│  1.SCAN │───▶│2.MERKLE │───▶│3.REPORT │───▶│ 4.SIGN  │───▶│5.STAMP  │
│         │    │         │    │  (DoD)  │    │  (GPG)  │    │  (OTS)  │
└─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘
                                                   │
                                              ┌────▼────┐
                                              │6.VERIFY │
                                              └─────────┘
```

### Phase 1: Scan (`src/run_demo.ps1`)

Recursively scans the `sample/` directory and computes SHA-256 for each file. Produces `output/manifest.csv` with columns: `Path`, `Rel`, `SHA256`, `Size`.

- Files are sorted by relative path (forward-slash normalized) for deterministic output
- Uses `Get-FileHash -Algorithm SHA256` via the shared crypto library

### Phase 2: Merkle Tree (`tools/Merkle.ps1`)

Builds an RFC 6962 compliant Merkle tree from the manifest hashes.

- Leaf hash: `SHA-256(0x00 || data)` — domain separation prevents second-preimage attacks
- Internal hash: `SHA-256(0x01 || left || right)`
- Odd-count levels: last node is duplicated
- Output: `output/merkle_root.txt` (64-char lowercase hex)

### Phase 3: Report / DoD (`tools/DoD.ps1`)

Generates `output/DoD/DoD.json` — the Declaration of Done containing:

- Merkle root (from Phase 2)
- Schema version and algorithm metadata
- NTP drift measurement (from `tools/NtpDrift.ps1`)
- SHA-256 hashes of all pipeline scripts (self-integrity)
- Artifact presence flags

### Phase 4: Sign (`tools/Sign-Audit.ps1`)

Creates GPG detached signatures (`.asc` files) for:

- `output/manifest.csv.asc`
- `output/merkle_root.txt.asc`
- `output/DoD/DoD.json.asc`

### Phase 5: Timestamp (`tools/OTS-Stamp.ps1`)

Submits the Merkle root to OpenTimestamps calendar servers for blockchain-anchored timestamping. Falls back to a local stub if servers are unreachable.

### Phase 6: Verify (`tools/verify.ps1`)

Independent verification with 9 checks:

| # | Check | Severity |
|---|-------|----------|
| 0 | File existence (DoD, manifest, merkle_root) | FAIL |
| 1 | Read merkle_root.txt | FAIL |
| 2 | DoD.merkle_root matches merkle_root.txt | FAIL |
| 3 | Schema version present | WARN |
| 4 | Recompute Merkle tree from manifest | FAIL |
| 5 | Files on disk match manifest hashes | FAIL |
| 6 | No unauthorized files on disk | FAIL |
| 7 | GPG signature verification | FAIL/WARN |
| 8 | Pipeline script integrity | FAIL/WARN |
| 9 | NTP drift within 5s | WARN |

## Directory Structure

```
asi-omega-audit-pipeline/
├── lib/
│   └── crypto.ps1          # Shared cryptographic library
├── src/
│   └── run_demo.ps1        # Phase 1: File scanner
├── tools/
│   ├── Merkle.ps1          # Phase 2: Merkle tree builder
│   ├── DoD.ps1             # Phase 3: DoD report generator
│   ├── Sign-Audit.ps1      # Phase 4: GPG signing
│   ├── Sign-DoD.ps1        # Quick-sign DoD only
│   ├── OTS-Stamp.ps1       # Phase 5: OpenTimestamps
│   ├── OTS-Stub.ps1        # OTS local stub (offline fallback)
│   ├── NtpDrift.ps1        # NTP clock drift measurement
│   └── verify.ps1          # Phase 6: Independent verification
├── tests/
│   ├── selftest.ps1        # Quick smoke test
│   ├── test-determinism.ps1
│   ├── test-merkle-edge-cases.ps1
│   ├── test-error-paths.ps1
│   └── criteria/           # Acceptance criteria tests (C1–C6)
├── sample/                 # Test artifacts to audit
├── output/                 # Generated artifacts
├── docs/
│   ├── schemas/            # JSON Schemas
│   ├── golden-hashes.json  # Known-good hash values
│   └── ARCHITECTURE.md     # This file
└── logs/
    └── ledger.jsonl        # Audit log
```

## Shared Crypto Library (`lib/crypto.ps1`)

All cryptographic operations are centralized in a single library:

| Function | Purpose |
|----------|---------|
| `Get-Sha256Hash` | SHA-256 of a UTF-8 string |
| `Get-Sha256FileHash` | SHA-256 of a file on disk |
| `Get-MerkleLeafHash` | RFC 6962 leaf: `SHA-256(0x00 \|\| data)` |
| `Get-MerkleInternalHash` | RFC 6962 internal: `SHA-256(0x01 \|\| left \|\| right)` |
| `Build-MerkleTree` | Full Merkle tree from leaf array → root hash |

All scripts import via: `. (Join-Path $PSScriptRoot '..\lib\crypto.ps1')`

## Data Flow

```
sample/*.txt
    │
    ▼
[SHA-256 per file]
    │
    ▼
manifest.csv ──────────────────────────────┐
    │                                       │
    ▼                                       ▼
[RFC 6962 Merkle Tree]              [GPG Sign] → manifest.csv.asc
    │
    ▼
merkle_root.txt ──────┬────────────────────┐
    │                  │                    │
    ▼                  ▼                    ▼
DoD.json        [GPG Sign]          [OTS Stamp]
    │           → merkle_root.txt.asc  → .ots proof
    ▼
[GPG Sign] → DoD.json.asc
```

## Standards Compliance

| Standard | Usage |
|----------|-------|
| NIST FIPS 180-4 | SHA-256 hash algorithm |
| RFC 6962 §2.1 | Merkle tree domain separation (0x00/0x01 prefixes) |
| RFC 4880 | GPG detached signatures |
| OpenTimestamps | Blockchain-anchored timestamping |
