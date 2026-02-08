# Acceptance Criteria: Forensic Evidence Pipeline

## Overview

These criteria define what a deterministic evidence pipeline MUST satisfy
to be considered reliable for forensic auditing and legal proceedings.
Each criterion maps to one or more test scripts in `tests/criteria/`.

---

## Criterion 1: DETERMINISM
> Same inputs MUST produce byte-identical outputs, every time, on every platform.

| ID | Requirement | Test |
|----|------------|------|
| D1 | Manifest row order must be stable across runs | `test-C1-determinism.ps1` |
| D2 | Merkle root must be identical for identical manifests | `test-C1-determinism.ps1` |
| D3 | File ordering must use explicit sort (not filesystem order) | `test-C1-determinism.ps1` |

**Why it matters:** If two runs of the same files produce different outputs,
the evidence is not reproducible and cannot be independently verified.

---

## Criterion 2: TAMPER DETECTION
> Any modification to source files, manifest, or Merkle root MUST be detected.

| ID | Requirement | Test |
|----|------------|------|
| T1 | Modifying a source file must cause verification failure | `test-C2-tamper-detection.ps1` |
| T2 | Adding an extra file must be detected | `test-C2-tamper-detection.ps1` |
| T3 | Removing a file must be detected | `test-C2-tamper-detection.ps1` |
| T4 | Reordering manifest rows must be detected | `test-C2-tamper-detection.ps1` |
| T5 | Replacing manifest+merkle together must be detected (if signed) | `test-C2-tamper-detection.ps1` |

**Why it matters:** The entire purpose of the pipeline is to prove files
haven't been altered. If tampering goes undetected, the pipeline is useless.

---

## Criterion 3: MERKLE TREE CORRECTNESS
> The Merkle tree must be cryptographically sound and follow established standards.

| ID | Requirement | Test |
|----|------------|------|
| M1 | Single leaf: root == leaf hash | `test-C3-merkle-correctness.ps1` |
| M2 | Two leaves: root == Hash(L0+L1) | `test-C3-merkle-correctness.ps1` |
| M3 | Odd leaves: padding must be deterministic | `test-C3-merkle-correctness.ps1` |
| M4 | Changing one leaf must change the root | `test-C3-merkle-correctness.ps1` |
| M5 | Swapping two leaves must change the root (order matters) | `test-C3-merkle-correctness.ps1` |

**Why it matters:** A weak Merkle tree allows collisions or undetected reordering.

---

## Criterion 4: NO SILENT FAILURES
> Every failure mode must produce a non-zero exit code and a logged error message.

| ID | Requirement | Test |
|----|------------|------|
| S1 | Missing input files must exit non-zero | `test-C4-silent-failures.ps1` |
| S2 | NTP failure must not silently return magic values | `test-C4-silent-failures.ps1` |
| S3 | Merkle computation failure must propagate to DoD | `test-C4-silent-failures.ps1` |
| S4 | Empty/malformed CSV must exit non-zero | `test-C4-silent-failures.ps1` |

**Why it matters:** In forensics, you must prove validation actually ran.
Silent failures mean the operator cannot certify the results.

---

## Criterion 5: TIMESTAMP TRUSTWORTHINESS
> Timestamps must be verifiable against an external time source.

| ID | Requirement | Test |
|----|------------|------|
| TS1 | DoD.json must contain an ISO 8601 timestamp | `test-C5-timestamp.ps1` |
| TS2 | NTP drift must be measured (not magic value 9999) | `test-C5-timestamp.ps1` |
| TS3 | OTS stub must reference the actual Merkle root hash | `test-C5-timestamp.ps1` |

**Why it matters:** Without trusted timestamps, evidence can be claimed
to be backdated. System clock alone is not sufficient.

---

## Criterion 6: END-TO-END CHAIN OF CUSTODY
> The full pipeline must produce a verifiable, complete evidence chain.

| ID | Requirement | Test |
|----|------------|------|
| E1 | bootstrap runs all steps without error | `test-C6-end-to-end.ps1` |
| E2 | All output artifacts exist after pipeline run | `test-C6-end-to-end.ps1` |
| E3 | verify.ps1 passes on fresh pipeline output | `test-C6-end-to-end.ps1` |
| E4 | DoD.json references correct Merkle root | `test-C6-end-to-end.ps1` |
| E5 | Manifest hashes match actual files on disk | `test-C6-end-to-end.ps1` |

**Why it matters:** Each link in the chain must hold. If any step is
broken or skipped, the entire evidence package is compromised.

---

## Test Result Key

Tests use these exit codes:
- `0` = PASS (criterion met)
- `1` = FAIL (criterion violated — pipeline has a defect)
- `2` = KNOWN-GAP (criterion cannot be met by current implementation)

KNOWN-GAP results identify areas where the pipeline needs improvement
to meet forensic standards. They are not failures in the test itself,
but documented weaknesses in the pipeline.
