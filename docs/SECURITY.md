# Security Model

## Threat Model

### What This Pipeline Protects Against

| Threat | Mitigation | Status |
|--------|-----------|--------|
| File tampering after audit | SHA-256 hashes in manifest detect any bit change | Active |
| Manifest tampering | Merkle root changes if any hash changes | Active |
| Second-preimage attack on Merkle tree | RFC 6962 domain separation (0x00/0x01 prefixes) | Active |
| Unauthorized file addition | Directory scanning compares disk vs manifest | Active |
| Pipeline script modification | DoD records SHA-256 of all pipeline scripts | Active |
| Clock manipulation | NTP drift measurement cross-references external time servers | Active |
| Repudiation ("I never signed this") | GPG signatures bind identity to audit | Optional |
| Backdated audits | OpenTimestamps blockchain anchor proves existence time | Optional |

### What This Pipeline Does NOT Protect Against

| Threat | Explanation |
|--------|-------------|
| Compromised machine | If the machine running the pipeline is compromised, all bets are off |
| Pre-audit tampering | The pipeline audits current state; it cannot detect changes before first audit |
| Key compromise | If the GPG private key is stolen, signatures can be forged |
| Quantum computing | SHA-256 is not quantum-resistant (not a near-term threat) |
| Physical access attacks | Hardware keyloggers, cold boot attacks, etc. |

## Cryptographic Standards

| Component | Standard | Reference |
|-----------|----------|-----------|
| File hashing | SHA-256 | NIST FIPS 180-4 |
| Merkle tree | Domain-separated SHA-256 | RFC 6962 §2.1 |
| Signatures | GPG/PGP | RFC 4880 |
| Timestamping | OpenTimestamps | opentimestamps.org |

## RFC 6962 Domain Separation

The Merkle tree uses prefix bytes to prevent second-preimage attacks (CVE-2012-2459 class):

```
Leaf node:     SHA-256(0x00 || leaf_data)
Internal node: SHA-256(0x01 || left_child || right_child)
```

This ensures an attacker cannot construct a leaf that collides with an internal node, which would allow substituting an entire subtree.

## Verification Layers

The pipeline implements defense in depth with 9 verification checks:

```
Layer 1: File Existence
  └── Are DoD.json, manifest.csv, merkle_root.txt present?

Layer 2: Cross-Reference Integrity
  └── Does DoD.merkle_root match merkle_root.txt?

Layer 3: Schema Validation
  └── Is the DoD format version known?

Layer 4: Merkle Recomputation
  └── Does recomputed Merkle root match the stored root?

Layer 5: Disk Integrity
  └── Do files on disk match manifest SHA-256 hashes?

Layer 6: Unauthorized File Detection
  └── Are there files on disk NOT in the manifest?

Layer 7: Cryptographic Authentication
  └── Are GPG signatures valid?

Layer 8: Pipeline Self-Integrity
  └── Do pipeline scripts match their recorded hashes?

Layer 9: Time Validation
  └── Is NTP drift within acceptable bounds?
```

## Script Integrity

The DoD records SHA-256 hashes of all pipeline scripts:

- `src/run_demo.ps1`
- `tools/Merkle.ps1`
- `tools/verify.ps1`
- `tools/DoD.ps1`
- `tools/NtpDrift.ps1`
- `tools/Sign-Audit.ps1`
- `tools/OTS-Stamp.ps1`

During verification, these hashes are compared against the scripts on disk. Any modification to a pipeline script after the audit will be detected.

## Trust Anchors

| Anchor | Provides | Strength |
|--------|----------|----------|
| SHA-256 hash chain | Tamper detection | Mathematical (collision-resistant) |
| GPG signature | Identity binding + non-repudiation | Depends on key management |
| OpenTimestamps | Existence proof at a point in time | Blockchain-level immutability |
| NTP measurement | Clock accuracy evidence | Network-dependent |

## Recommendations

### For Maximum Security

1. **Always sign audits** with GPG (`pwsh tools/Sign-Audit.ps1`)
2. **Timestamp with OpenTimestamps** for independent time proof
3. **Publish the Merkle root** to a public channel (email, git tag, etc.)
4. **Store GPG keys securely** — hardware tokens (YubiKey) recommended
5. **Run from a trusted machine** — the pipeline cannot protect against a compromised runtime

### For Sharing Audit Results

1. Send the entire `output/` directory
2. Recipient runs `pwsh tools/verify.ps1` to independently verify
3. GPG signatures allow verification without trusting the sender
4. OTS proofs can be verified by anyone against the public blockchain

## Known Limitations

1. **No incremental auditing** — each run scans all files from scratch
2. **No remote attestation** — verification runs locally
3. **PowerShell dependency** — requires PowerShell 7+ runtime
4. **GPG optional** — without GPG, there is no identity binding
5. **OTS latency** — blockchain confirmation takes 4-24 hours
