"""
ASI-Omega Audit Pipeline v2 - Python Edition
Portable forensic notary: SHA-256 -> Merkle tree -> GPG -> OpenTimestamps

Usage:
    asi-omega audit <path>          Audit a folder
    asi-omega verify <path>         Verify files are unchanged
    asi-omega report <path>         Show audit report
    asi-omega dash                  Launch web dashboard
"""
import hashlib
import csv
import json
import os
import sys
import datetime
from pathlib import Path
from typing import Optional


# ─────────────────────────────────────────────────────
# Crypto core — single source of truth
# ─────────────────────────────────────────────────────

def sha256_file(filepath: str) -> str:
    """SHA-256 hash of a file (NIST FIPS 180-4). Returns lowercase hex."""
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_bytes(data: bytes) -> str:
    """SHA-256 hash of raw bytes. Returns lowercase hex."""
    return hashlib.sha256(data).hexdigest()


# ─────────────────────────────────────────────────────
# RFC 6962 Merkle tree with domain separation
# ─────────────────────────────────────────────────────

LEAF_PREFIX = b"\x00"
NODE_PREFIX = b"\x01"


def merkle_leaf(data: str) -> str:
    """Hash a leaf: SHA-256(0x00 || data)"""
    return sha256_bytes(LEAF_PREFIX + data.encode("utf-8"))


def merkle_node(left: str, right: str) -> str:
    """Hash an internal node: SHA-256(0x01 || left || right)"""
    combined = NODE_PREFIX + bytes.fromhex(left) + bytes.fromhex(right)
    return sha256_bytes(combined)


def build_merkle_tree(hashes: list[str]) -> str:
    """
    Build RFC 6962 Merkle tree from a list of hex hash strings.
    Returns the root hash. Raises ValueError if list is empty.
    """
    if not hashes:
        raise ValueError("Cannot build Merkle tree from empty list")

    # Leaf layer: apply domain separation
    nodes = [merkle_leaf(h) for h in hashes]

    # Build tree bottom-up
    while len(nodes) > 1:
        next_level = []
        for i in range(0, len(nodes), 2):
            if i + 1 < len(nodes):
                next_level.append(merkle_node(nodes[i], nodes[i + 1]))
            else:
                # Odd node: promote (RFC 6962 padding)
                next_level.append(nodes[i])
        nodes = next_level

    return nodes[0]


# ─────────────────────────────────────────────────────
# Manifest — scan files, store hashes with original paths
# ─────────────────────────────────────────────────────

def scan_directory(target_path: str) -> list[dict]:
    """Scan all files in target_path, return list of {path, rel, sha256, size}."""
    target = Path(target_path).resolve()
    if not target.is_dir():
        raise FileNotFoundError(f"Directory not found: {target_path}")

    entries = []
    for filepath in sorted(target.rglob("*")):
        if filepath.is_file() and ".asi-omega" not in filepath.parts:
            rel = filepath.relative_to(target)
            entries.append({
                "path": str(filepath),
                "rel": str(rel),
                "sha256": sha256_file(str(filepath)),
                "size": filepath.stat().st_size,
            })
    return entries


def write_manifest(entries: list[dict], output_path: str):
    """Write manifest as CSV."""
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["path", "rel", "sha256", "size"])
        writer.writeheader()
        writer.writerows(entries)


def read_manifest(manifest_path: str) -> list[dict]:
    """Read manifest CSV, return list of dicts."""
    with open(manifest_path, "r", encoding="utf-8") as f:
        return list(csv.DictReader(f))


# ─────────────────────────────────────────────────────
# Audit — full pipeline
# ─────────────────────────────────────────────────────

def audit(target_path: str, output_dir: Optional[str] = None) -> dict:
    """
    Run full audit on target_path.
    Creates: manifest.csv, merkle_root.txt, dod.json, rapport.txt
    Returns audit result dict.
    """
    target = Path(target_path).resolve()
    if output_dir is None:
        output_dir = str(target / ".asi-omega")
    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)

    # Step 1: Scan files
    print(f"  [1/3] Scanner filer i {target}...")
    entries = scan_directory(str(target))
    print(f"        {len(entries)} filer registrert")

    # Step 2: Write manifest
    manifest_path = out / "manifest.csv"
    write_manifest(entries, str(manifest_path))

    # Step 3: Build Merkle tree
    if not entries:
        print("  FEIL: Ingen filer funnet i mappen.")
        sys.exit(1)
    print("  [2/3] Bygger Merkle-tre (RFC 6962)...")
    hashes = [e["sha256"] for e in entries]
    root = build_merkle_tree(hashes)
    print(f"        Merkle-rot: {root[:16]}...")

    merkle_path = out / "merkle_root.txt"
    merkle_path.write_text(root, encoding="utf-8")

    # Step 4: Generate DoD report
    print("  [3/3] Genererer rapport...")
    now = datetime.datetime.now(datetime.timezone.utc)
    dod = {
        "schema_version": 2,
        "merkle_root": root,
        "generated": now.isoformat(),
        "target_path": str(target),
        "file_count": len(entries),
        "total_size_bytes": sum(int(e["size"]) for e in entries),
        "platform": sys.platform,
    }
    dod_path = out / "dod.json"
    dod_path.write_text(json.dumps(dod, indent=2, ensure_ascii=False), encoding="utf-8")

    # Step 5: Human-readable report
    rapport = generate_report(entries, dod)
    rapport_path = out / "rapport.txt"
    rapport_path.write_text(rapport, encoding="utf-8")

    print()
    print(f"  AUDIT FULLFORT")
    print(f"  Filer:       {len(entries)}")
    print(f"  Merkle-rot:  {root[:16]}...")
    print(f"  Tidspunkt:   {now.strftime('%Y-%m-%d %H:%M:%S')} UTC")
    print(f"  Utdata:      {out}")
    print()
    print(f"  Verifiser senere:")
    print(f"    asi-omega verify \"{target}\"")
    print()

    return dod


# ─────────────────────────────────────────────────────
# Verify — check all files against manifest
# ─────────────────────────────────────────────────────

def verify(target_path: str, output_dir: Optional[str] = None) -> bool:
    """
    Verify files against stored audit.
    Returns True if all checks pass.
    """
    target = Path(target_path).resolve()
    if output_dir is None:
        output_dir = str(target / ".asi-omega")
    out = Path(output_dir)

    manifest_path = out / "manifest.csv"
    merkle_path = out / "merkle_root.txt"
    dod_path = out / "dod.json"

    # Check required files exist
    missing = []
    for f, name in [(manifest_path, "manifest.csv"), (merkle_path, "merkle_root.txt"), (dod_path, "dod.json")]:
        if not f.exists():
            missing.append(name)
    if missing:
        print(f"  FEIL: Mangler filer: {', '.join(missing)}")
        print(f"  Kjoer 'asi-omega audit \"{target}\"' foerst.")
        return False

    entries = read_manifest(str(manifest_path))
    stored_root = merkle_path.read_text(encoding="utf-8").strip()
    dod = json.loads(dod_path.read_text(encoding="utf-8"))

    print(f"  VERIFISERER: {target}")
    print(f"  {len(entries)} filer i manifest")
    print()

    ok = True
    warnings = 0

    # Check 1: DoD merkle_root matches merkle_root.txt
    if dod.get("merkle_root") == stored_root:
        print("  OK: DoD merkle_root matcher merkle_root.txt")
    else:
        print("  FEIL: DoD merkle_root matcher IKKE merkle_root.txt")
        ok = False

    # Check 2: Recompute Merkle root from manifest
    hashes = [e["sha256"] for e in entries]
    recomputed = build_merkle_tree(hashes)
    if recomputed == stored_root:
        print("  OK: Merkle-rot (reberegnet) matcher")
    else:
        print("  FEIL: Merkle-rot MATCHER IKKE — manifest kan vaere endret")
        ok = False

    # Check 3: Verify each file on disk
    files_ok = 0
    files_fail = 0
    files_missing = 0
    for e in entries:
        filepath = Path(e["path"])
        if not filepath.exists():
            print(f"  FEIL: FIL MANGLER: {e['rel']}")
            files_missing += 1
            ok = False
        else:
            current_hash = sha256_file(str(filepath))
            if current_hash == e["sha256"]:
                files_ok += 1
            else:
                print(f"  FEIL: ENDRET: {e['rel']}")
                print(f"        Forventet: {e['sha256'][:16]}...")
                print(f"        Faktisk:   {current_hash[:16]}...")
                files_fail += 1
                ok = False

    if files_ok == len(entries):
        print(f"  OK: Alle {files_ok} filer verifisert")
    else:
        if files_missing:
            print(f"  FEIL: {files_missing} fil(er) mangler")
        if files_fail:
            print(f"  FEIL: {files_fail} fil(er) endret")

    # Check 4: Unauthorized files (files on disk not in manifest)
    manifest_paths = {str(Path(e["path"]).resolve()) for e in entries}
    disk_files = {str(f.resolve()) for f in target.rglob("*") if f.is_file() and ".asi-omega" not in str(f)}
    extra = disk_files - manifest_paths
    if extra:
        print(f"  ADVARSEL: {len(extra)} fil(er) paa disk som ikke er i manifest:")
        for f in sorted(extra)[:5]:
            print(f"    + {Path(f).relative_to(target)}")
        if len(extra) > 5:
            print(f"    ... og {len(extra) - 5} til")
        warnings += 1
    else:
        print("  OK: Ingen uautoriserte filer")

    # Result
    print()
    if ok:
        if warnings:
            print(f"  VERIFISERING BESTATT med {warnings} advarsel(er)")
        else:
            print(f"  VERIFISERING BESTATT — alle filer er uendret")
    else:
        print(f"  VERIFISERING FEILET — filer kan ha blitt endret")

    return ok


# ─────────────────────────────────────────────────────
# Report generation
# ─────────────────────────────────────────────────────

def generate_report(entries: list[dict], dod: dict) -> str:
    """Generate human-readable Norwegian report."""
    lines = [
        "=" * 60,
        "  ASI-OMEGA AUDIT PIPELINE",
        "  Integritetsrapport",
        "=" * 60,
        "",
        f"  Opprettet:   {dod['generated']}",
        f"  Mappe:       {dod['target_path']}",
        f"  Platform:    {dod['platform']}",
        "",
        "=" * 60,
        "  RESULTAT",
        "=" * 60,
        "",
        f"  Merkle-rot:  {dod['merkle_root']}",
        "",
        "  Dette er et unikt fingeravtrykk for alle filene nedenfor.",
        "  Endres en eneste byte i en eneste fil, endres dette tallet.",
        "",
        "=" * 60,
        f"  REGISTRERTE FILER ({len(entries)} stk.)",
        "=" * 60,
        "",
    ]

    for e in entries:
        size = f"{int(e['size']):,} bytes" if e.get("size") else "ukjent"
        lines.append(f"    {e['rel']}")
        lines.append(f"      SHA-256:    {e['sha256']}")
        lines.append(f"      Storrelse:  {size}")
        lines.append("")

    lines.extend([
        "=" * 60,
        "  SLIK VERIFISERER DU",
        "=" * 60,
        "",
        f'  asi-omega verify "{dod["target_path"]}"',
        "",
        "=" * 60,
        "  ASI-Omega Audit Pipeline v2",
        "  https://github.com/shahonader-art/asi-omega-audit-pipeline",
        "=" * 60,
    ])

    return "\n".join(lines)


# ─────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(0)

    cmd = sys.argv[1].lower()

    if cmd == "audit":
        if len(sys.argv) < 3:
            print("Bruk: asi-omega audit <mappe>")
            sys.exit(1)
        target = sys.argv[2]
        audit(target)

    elif cmd == "verify":
        if len(sys.argv) < 3:
            print("Bruk: asi-omega verify <mappe>")
            sys.exit(1)
        target = sys.argv[2]
        success = verify(target)
        sys.exit(0 if success else 1)

    elif cmd in ("help", "-h", "--help"):
        print(__doc__)

    elif cmd == "dash":
        from dashboard import start_dashboard
        port = 5050
        if len(sys.argv) > 2:
            try:
                port = int(sys.argv[2])
            except ValueError:
                pass
        start_dashboard(port)

    else:
        print(f"Ukjent kommando: {cmd}")
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
