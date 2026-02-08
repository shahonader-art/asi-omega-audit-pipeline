# Contributing to ASI-Omega Audit Pipeline

## Quick Start

```powershell
git clone https://github.com/shahonader-art/asi-omega-audit-pipeline.git
cd asi-omega-audit-pipeline
pwsh test.ps1          # Run all 12 test suites — must pass before any PR
```

## Architecture

```
audit.ps1                 # Single entry point — all user interaction
  ├── src/run_demo.ps1      # Scans files → manifest.csv
  ├── tools/Merkle.ps1      # Builds Merkle tree → merkle_root.txt
  ├── tools/DoD.ps1         # Generates report → DoD.json
  ├── tools/verify.ps1      # 9-check verification
  ├── tools/Sign-Audit.ps1  # GPG signing
  ├── tools/OTS-Stamp.ps1   # OpenTimestamps
  └── tools/NtpDrift.ps1    # NTP time validation

lib/crypto.ps1            # ALL crypto lives here. Single source of truth.
```

**Rule:** New features go in `tools/`. Never add logic directly to `audit.ps1`.

## The 5 Rules

Every contributor MUST follow these. Violating them will break things silently.

### 1. Always set `$PSNativeCommandUseErrorActionPreference = $false`

Add this to the top of EVERY `.ps1` file:

```powershell
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
```

**Why:** PowerShell 7.5 defaults to `$true`, which turns non-zero exit codes from subprocesses into terminating errors. This breaks exit code propagation.

### 2. Never use `ConvertTo-Json` / `ConvertFrom-Json` for critical data

Use string templates and regex extraction instead:

```powershell
# BAD — fails randomly in PS 7.5
$data | ConvertTo-Json | Set-Content file.json

# GOOD — reliable
$json = @"
{
  "key": "$value"
}
"@
$json | Set-Content file.json
```

### 3. Always wrap string multiplication in parentheses inside arrays

```powershell
# BAD — PS 7.5 misparses this
$arr = @("a" * 64, "b" * 64)

# GOOD
$arr = @(("a" * 64), ("b" * 64))
```

### 4. `lib/crypto.ps1` is the single source of truth

All hashing functions live in `lib/crypto.ps1`. Every script that needs crypto must dot-source it:

```powershell
. (Join-Path $PSScriptRoot '..\lib\crypto.ps1')
```

Never duplicate hash logic. Never import from anywhere else.

### 5. All 12 test suites must pass

```powershell
pwsh test.ps1
```

If any test fails, your PR will be rejected.

## How to Add a Feature

Example: adding PDF export.

1. Create `tools/Export-Pdf.ps1`
2. Dot-source crypto if needed: `. (Join-Path $PSScriptRoot '..\lib\crypto.ps1')`
3. Add the call in `audit.ps1` (keep it minimal — just the call)
4. Create test: `tests/criteria/test-C9-pdf-export.ps1`
5. Add C9 to `tests/criteria/run-all-criteria.ps1` and `test.ps1`
6. Run `pwsh test.ps1` — all green before PR

## Test Structure

| Suite | What it tests |
|-------|---------------|
| C1 | Determinism — same inputs, same outputs |
| C2 | Tamper detection — file changes caught |
| C3 | Merkle correctness — RFC 6962 compliance |
| C4 | No silent failures — errors produce non-zero exit |
| C5 | Timestamp trust — NTP and OTS validation |
| C6 | End-to-end — full pipeline chain |
| C7 | Crypto stress — 13 in-process cryptographic tests |
| C8 | User workflow — 9 real-user scenarios |
| + 4 utility suites | Golden hashes, Merkle edge cases, determinism, error paths |

## Commit Messages

Follow conventional commits:

```
feat(tools): add PDF export
fix(verify): correct exit code on missing manifest
test(C9): add PDF export acceptance tests
docs: update README with PDF section
```

## Pull Request Checklist

- [ ] `pwsh test.ps1` passes (all 12 suites)
- [ ] `$PSNativeCommandUseErrorActionPreference = $false` in all new scripts
- [ ] No `ConvertTo-Json` / `ConvertFrom-Json` for critical data paths
- [ ] New features have corresponding tests
- [ ] Norwegian (nb-NO) in user-facing text, English in code/comments

## Project Conventions

- **User-facing text:** Norwegian (nb-NO)
- **Code comments:** English
- **Hash format:** Lowercase hex (64 chars for SHA-256)
- **Platform:** PowerShell 7+ (Windows, macOS, Linux)
- **Line endings:** CRLF normalized before hashing for cross-platform consistency
