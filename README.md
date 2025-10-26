# ASI-Omega Audit Pipeline

Deterministic evidence pipeline: manifest + hashing + self-test + DoD report.

**Keywords**: deterministic logging, forensics, PowerShell, audit pipeline, legal evidence, Merkle (planned), reproducible builds

## Quickstart
```powershell
# In PowerShell 7+
Set-Location .\asi-omega-audit-pipeline
pwsh -NoProfile -File .\src\run_demo.ps1 -Out .\output
pwsh -NoProfile -File .\tests\selftest.ps1
pwsh -NoProfile -File .\tools\DoD.ps1 -Out .\output\DoD
```

## What it does
- Generates a manifest (CSV) with SHA-256 for tracked artifacts in `sample/`
- Compares against `docs/golden-hashes.json`
- Emits DoD (Definition of Done) report with timestamps + hashes
- CI workflow (GitHub Actions) runs demo + tests on each push

## Author
**Shaho Nader** — LinkedIn/GitHub links to be added by owner.


## Integrity & CI
- Merkle root included in DoD
- NTP drift measure
- OTS request stub (offline)
- Optional GPG signature of DoD
- CI uploads audit artifacts per commit
![CI](https://github.com/shahonader-art/asi-omega-audit-pipeline/actions/workflows/ci.yml/badge.svg)

## Contact / Partnerships
For inquiries, please open an issue at  
👉 https://github.com/shahonader-art/asi-omega-audit-pipeline/issues
![CI](https://github.com/shahonader-art/asi-omega-audit-pipeline/actions/workflows/ci.yml/badge.svg)

## Contact / Partnerships
For inquiries, please open an issue at  
👉 https://github.com/shahonader-art/asi-omega-audit-pipeline/issues

![Verify](https://github.com/shahonader-art/asi-omega-audit-pipeline/actions/workflows/verify.yml/badge.svg)
