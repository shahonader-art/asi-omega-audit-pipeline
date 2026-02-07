<p align="center">
  <strong>ASI-Omega Audit Pipeline</strong><br>
  <em>Portable forensic notary — cryptographic proof that your files are authentic and unchanged.</em>
</p>

<p align="center">
  <a href="https://github.com/shahonader-art/asi-omega-audit-pipeline/actions/workflows/ci.yml">
    <img src="https://github.com/shahonader-art/asi-omega-audit-pipeline/actions/workflows/ci.yml/badge.svg" alt="CI">
  </a>
  <a href="https://github.com/shahonader-art/asi-omega-audit-pipeline/actions/workflows/verify.yml">
    <img src="https://github.com/shahonader-art/asi-omega-audit-pipeline/actions/workflows/verify.yml/badge.svg" alt="Verify">
  </a>
  <img src="https://img.shields.io/badge/PowerShell-7%2B-blue" alt="PowerShell 7+">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

---

## The only tool that combines all three

| Capability | Tripwire | CrowdStrike | Wazuh | Windows SFC | **ASI-Omega** |
|:--|:--:|:--:|:--:|:--:|:--:|
| SHA-256 file hashing | Yes | Yes | Yes | Internal | **Yes** |
| RFC 6962 Merkle tree | - | - | - | - | **Yes** |
| GPG digital signatures | - | - | - | - | **Yes** |
| Blockchain timestamping (OTS) | - | - | - | - | **Yes** |
| Self-contained evidence package | - | - | - | - | **Yes** |
| No infrastructure required | - | - | - | Yes | **Yes** |
| Free | - | - | Yes | Yes | **Yes** |

> **One script. Zero dependencies. Court-admissible proof.**

---

## What does it do?

Point it at a folder. It calculates a unique fingerprint for every file, combines them into a single number (a Merkle root), and generates a report. Change a single byte in a single file — the entire proof changes.

```
Your files  →  SHA-256 per file  →  Merkle tree  →  Report + Signature + Timestamp
```

**No one can forge this. Not even you.**

---

## Why not just use Windows SFC?

Windows SFC is a **repair tool** — it checks Windows system files and fixes them.

ASI-Omega is a **forensic proof tool** — it proves to a third party that specific files existed in a specific state at a specific time.

| | Windows SFC | ASI-Omega |
|--|--|--|
| **Purpose** | Repair Windows files | Prove files are unchanged |
| **Scope** | Windows system files only | Any files you choose |
| **Proof** | None — repairs only | Cryptographic evidence chain |
| **Timestamp** | None | Bitcoin blockchain (OTS) |
| **Signature** | None | GPG |
| **In court** | Worthless | Legally defensible |

---

## Installation

### Option 1: One-command install (recommended)

```powershell
irm https://raw.githubusercontent.com/shahonader-art/asi-omega-audit-pipeline/main/install.ps1 | iex
```

### Option 2: Manual

```powershell
git clone https://github.com/shahonader-art/asi-omega-audit-pipeline.git
cd asi-omega-audit-pipeline
pwsh audit.ps1 -Help
```

### Option 3: Build as .exe

```powershell
git clone https://github.com/shahonader-art/asi-omega-audit-pipeline.git
cd asi-omega-audit-pipeline
pwsh build-exe.ps1
```

### Requirements

- [PowerShell 7+](https://github.com/PowerShell/PowerShell/releases) (free, Windows/Mac/Linux)
- [Gpg4win](https://gpg4win.org) (optional, for digital signatures)

---

## Usage

### GUI

Double-click **ASI-Omega Audit** on your desktop, or:

```powershell
pwsh audit-gui.ps1
```

### CLI

```powershell
# Audit a folder
pwsh audit.ps1 -Path "C:\My\Documents"

# Verify files are unchanged
pwsh audit.ps1 -Verify

# Full audit with signing and timestamping
pwsh audit.ps1 -Full

# Show all commands
pwsh audit.ps1 -Help
```

### Commands

| Command | Description |
|---------|-------------|
| `pwsh audit.ps1` | Audit the default folder |
| `pwsh audit.ps1 -Path <folder>` | Audit any folder |
| `pwsh audit.ps1 -Verify` | Verify files are unchanged |
| `pwsh audit.ps1 -Sign` | Audit + GPG signing |
| `pwsh audit.ps1 -Timestamp` | Audit + independent timestamp |
| `pwsh audit.ps1 -Full` | Everything: audit + signing + timestamp |

---

## Output

| File | Description |
|------|-------------|
| `rapport.txt` | Human-readable report |
| `manifest.csv` | SHA-256 fingerprint per file |
| `merkle_root.txt` | Single combined fingerprint |
| `DoD/DoD.json` | Machine-readable report (JSON) |
| `*.asc` | GPG signatures (with `-Sign`) |
| `ots_receipt.txt` | Timestamp receipt (with `-Timestamp`) |

---

## Use cases

### Lawyers
> *"The client delivered documents on January 15th. We need proof they haven't been modified."*

Run `audit.ps1 -Full` on the documents. The report is cryptographic evidence.

### Auditors
> *"The accounts must be identical to what was submitted to the tax authority."*

Audit at delivery. Verify anytime with `audit.ps1 -Verify`.

### IT / Developers
> *"The customer claims the software we delivered had a bug. We need to prove what we actually shipped."*

Audit the `release/` folder before delivery. Store `output/` with the release.

### Researchers
> *"The peer reviewer requires proof the dataset wasn't manipulated after analysis."*

Audit the dataset. Attach the report to the publication.

### AI / ML teams
> *"We need to prove our training data and model weights are authentic and unmodified."*

Audit data and models. The blockchain-anchored timestamp proves provenance.

---

## How it works

```
┌─────────────┐     ┌──────────────┐     ┌────────────┐     ┌───────────┐
│  Your files  │ ──→ │  SHA-256 per  │ ──→ │ Merkle tree │ ──→ │  Report   │
│              │     │  file         │     │ (RFC 6962)  │     │ + Sign    │
└─────────────┘     └──────────────┘     └────────────┘     │ + OTS     │
                                                             └───────────┘
```

1. **Scans** all files and computes SHA-256 fingerprints (NIST FIPS 180-4)
2. **Combines** fingerprints into a Merkle tree with RFC 6962 domain separation
3. **Self-tests** to verify all computations are correct
4. **Generates** report with timestamp and system info
5. **Signs** (optional) with GPG for personal guarantee
6. **Timestamps** (optional) via OpenTimestamps for blockchain anchoring

### Verification

When you run `audit.ps1 -Verify`, it performs 9 checks:

1. All required files exist
2. DoD.json Merkle root matches merkle_root.txt
3. Schema version check
4. Merkle root recomputed from manifest matches
5. Every file on disk matches its manifest hash
6. No unauthorized files on disk (not in manifest)
7. GPG signatures valid (if present)
8. Pipeline script integrity (script_hashes in DoD)
9. NTP drift sanity check

---

## Testing

```powershell
# Run all tests
pwsh test.ps1

# Run only specific suites
pwsh test.ps1 -Only criteria    # C1-C8 acceptance tests
pwsh test.ps1 -Only merkle      # Merkle tree tests
pwsh test.ps1 -Only quick       # Golden hash selftest
```

### 8 Acceptance Criteria + 4 Utility Tests

| Test | What it validates |
|------|-------------------|
| C1 | **Determinism** — same inputs always produce same outputs |
| C2 | **Tamper detection** — any file change is caught |
| C3 | **Merkle correctness** — RFC 6962 domain separation, padding |
| C4 | **No silent failures** — every error produces non-zero exit |
| C5 | **Timestamp trust** — time validation and OTS anchoring |
| C6 | **End-to-end** — full pipeline chain of custody |
| C7 | **Crypto stress** — 13 in-process tests: avalanche, collisions, scale |
| C8 | **User workflow** — 9 real-user scenarios including tamper detection |

---

## Technical

| Property | Value |
|----------|-------|
| Language | PowerShell 7+ |
| Hashing | SHA-256 (NIST FIPS 180-4) |
| Merkle tree | RFC 6962 binary tree with domain separation |
| Signing | GPG detached signatures (.asc) |
| Timestamping | OpenTimestamps (Bitcoin blockchain) |
| NTP | Cross-platform (w32tm / ntpdate / sntp / chronyc) |
| Platform | Windows, macOS, Linux |
| CI/CD | GitHub Actions |
| Tests | 12 test suites, 8 acceptance criteria, 50+ individual checks |

---

## Project structure

```
asi-omega-audit-pipeline/
├── audit.ps1            Main CLI entry point
├── audit-gui.ps1        GUI (Windows Forms)
├── install.ps1          One-command installer
├── build-exe.ps1        Build standalone .exe
├── test.ps1             Test runner
├── lib/
│   └── crypto.ps1       Shared cryptographic library
├── src/
│   └── run_demo.ps1     Manifest generation
├── tools/
│   ├── Merkle.ps1       Merkle tree builder
│   ├── verify.ps1       9-check verification
│   ├── DoD.ps1          DoD report generator
│   ├── NtpDrift.ps1     NTP time validation
│   ├── Sign-Audit.ps1   GPG signing
│   ├── OTS-Stamp.ps1    OpenTimestamps
│   └── OTS-Stub.ps1     Local OTS fallback
├── tests/               12 test suites
├── docs/                Architecture, security, schemas
└── sample/              Sample files for testing
```

---

## License

MIT — see [LICENSE](LICENSE)

## Author

**Shaho Nader** — [GitHub](https://github.com/shahonader-art)

## Issues

[github.com/shahonader-art/asi-omega-audit-pipeline/issues](https://github.com/shahonader-art/asi-omega-audit-pipeline/issues)
