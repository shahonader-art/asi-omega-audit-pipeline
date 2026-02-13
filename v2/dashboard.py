"""
ASI-Omega Audit Pipeline — Web Dashboard
Visuelt dashboard for audit-resultater, Merkle-tre, og verifisering.

Usage:
    python dashboard.py                     # Start på port 5050
    python dashboard.py --port 8080         # Annen port

Eller via CLI:
    python asi_omega.py dash
"""
import json
import csv
import os
import sys
import subprocess
import hashlib
from pathlib import Path
from datetime import datetime
from flask import Flask, render_template_string, request, jsonify

app = Flask(__name__)

# ─────────────────────────────────────────────────────
# Backend-integrasjon: les .asi-omega data
# ─────────────────────────────────────────────────────

def find_audits(base_path: str = None) -> list[dict]:
    """Finn alle .asi-omega mapper rekursivt under base_path."""
    if base_path is None:
        base_path = str(Path(__file__).parent.parent)  # audit-pipeline/

    audits = []
    base = Path(base_path)

    for asi_dir in sorted(base.rglob(".asi-omega")):
        if not asi_dir.is_dir():
            continue
        dod_file = asi_dir / "dod.json"
        if not dod_file.exists():
            continue
        try:
            dod = json.loads(dod_file.read_text(encoding="utf-8"))
            manifest_file = asi_dir / "manifest.csv"
            file_count = 0
            if manifest_file.exists():
                with open(manifest_file, "r", encoding="utf-8") as f:
                    file_count = sum(1 for _ in csv.DictReader(f))

            audits.append({
                "path": str(asi_dir.parent),
                "asi_dir": str(asi_dir),
                "merkle_root": dod.get("merkle_root", ""),
                "generated": dod.get("generated", ""),
                "file_count": file_count,
                "total_size": dod.get("total_size_bytes", 0),
                "platform": dod.get("platform", ""),
            })
        except Exception:
            pass
    return audits


def load_manifest(asi_dir: str) -> list[dict]:
    """Les manifest.csv fra en .asi-omega mappe."""
    manifest_path = Path(asi_dir) / "manifest.csv"
    if not manifest_path.exists():
        return []
    with open(manifest_path, "r", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def run_verify(target_path: str) -> dict:
    """Kjør verifisering via subprocess og returner resultat."""
    script = str(Path(__file__).parent / "asi_omega.py")
    try:
        result = subprocess.run(
            [sys.executable, script, "verify", target_path],
            capture_output=True, text=True, timeout=120
        )
        lines = (result.stdout + result.stderr).strip().split("\n")
        passed = result.returncode == 0
        return {"passed": passed, "output": lines, "returncode": result.returncode}
    except subprocess.TimeoutExpired:
        return {"passed": False, "output": ["Timeout etter 120 sekunder"], "returncode": -1}
    except Exception as e:
        return {"passed": False, "output": [str(e)], "returncode": -1}


def run_audit(target_path: str) -> dict:
    """Kjør audit via subprocess og returner resultat."""
    script = str(Path(__file__).parent / "asi_omega.py")
    try:
        result = subprocess.run(
            [sys.executable, script, "audit", target_path],
            capture_output=True, text=True, timeout=300
        )
        lines = (result.stdout + result.stderr).strip().split("\n")
        success = result.returncode == 0
        return {"success": success, "output": lines, "returncode": result.returncode}
    except subprocess.TimeoutExpired:
        return {"success": False, "output": ["Timeout etter 300 sekunder"], "returncode": -1}
    except Exception as e:
        return {"success": False, "output": [str(e)], "returncode": -1}


def format_size(size_bytes):
    """Formater bytes til lesbar størrelse."""
    if not size_bytes:
        return "0 B"
    size_bytes = int(size_bytes)
    for unit in ["B", "KB", "MB", "GB"]:
        if size_bytes < 1024:
            return f"{size_bytes:,.1f} {unit}"
        size_bytes /= 1024
    return f"{size_bytes:,.1f} TB"


# ─────────────────────────────────────────────────────
# HTML Template — single-page dashboard
# ─────────────────────────────────────────────────────

DASHBOARD_HTML = """
<!DOCTYPE html>
<html lang="no">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>ASI-Omega Audit Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
            background: #0a0a0f;
            color: #e0e0e0;
            min-height: 100vh;
        }

        /* Header */
        .header {
            background: linear-gradient(135deg, #0f1923 0%, #1a1a2e 100%);
            border-bottom: 1px solid #1e3a5f;
            padding: 20px 32px;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }
        .header h1 {
            font-size: 20px;
            font-weight: 600;
            color: #4fc3f7;
            letter-spacing: 1px;
        }
        .header h1 span { color: #78909c; font-weight: 400; }
        .header-actions { display: flex; gap: 12px; }

        /* Layout */
        .container { max-width: 1400px; margin: 0 auto; padding: 24px 32px; }

        /* Stats bar */
        .stats-bar {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 16px;
            margin-bottom: 24px;
        }
        .stat-card {
            background: #12121a;
            border: 1px solid #1e1e2e;
            border-radius: 8px;
            padding: 16px 20px;
        }
        .stat-card .label { font-size: 12px; color: #666; text-transform: uppercase; letter-spacing: 1px; }
        .stat-card .value { font-size: 28px; font-weight: 700; color: #4fc3f7; margin-top: 4px; }
        .stat-card .value.green { color: #66bb6a; }
        .stat-card .value.red { color: #ef5350; }
        .stat-card .value.amber { color: #ffa726; }

        /* Audit list */
        .section { margin-bottom: 32px; }
        .section-title {
            font-size: 14px;
            font-weight: 600;
            color: #78909c;
            text-transform: uppercase;
            letter-spacing: 1.5px;
            margin-bottom: 12px;
            padding-bottom: 8px;
            border-bottom: 1px solid #1e1e2e;
        }

        .audit-card {
            background: #12121a;
            border: 1px solid #1e1e2e;
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 12px;
            cursor: pointer;
            transition: border-color 0.2s;
        }
        .audit-card:hover { border-color: #4fc3f7; }
        .audit-card.expanded { border-color: #4fc3f7; }

        .audit-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .audit-path {
            font-family: 'Cascadia Code', 'Consolas', monospace;
            font-size: 14px;
            color: #4fc3f7;
        }
        .audit-meta {
            display: flex;
            gap: 24px;
            margin-top: 8px;
            font-size: 13px;
            color: #666;
        }
        .audit-meta span { display: flex; align-items: center; gap: 4px; }

        .merkle-hash {
            font-family: 'Cascadia Code', 'Consolas', monospace;
            font-size: 11px;
            color: #78909c;
            margin-top: 8px;
            word-break: break-all;
        }

        /* Status badge */
        .badge {
            padding: 4px 12px;
            border-radius: 4px;
            font-size: 12px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .badge.verified { background: #1b5e20; color: #66bb6a; }
        .badge.failed { background: #b71c1c33; color: #ef5350; }
        .badge.pending { background: #1a1a2e; color: #78909c; }

        /* Detail panel */
        .detail-panel {
            display: none;
            margin-top: 16px;
            padding-top: 16px;
            border-top: 1px solid #1e1e2e;
        }
        .detail-panel.visible { display: block; }

        /* File table */
        .file-table {
            width: 100%;
            border-collapse: collapse;
            font-size: 13px;
        }
        .file-table th {
            text-align: left;
            padding: 8px 12px;
            color: #78909c;
            font-weight: 600;
            font-size: 11px;
            text-transform: uppercase;
            letter-spacing: 1px;
            border-bottom: 1px solid #1e1e2e;
        }
        .file-table td {
            padding: 6px 12px;
            border-bottom: 1px solid #0f0f17;
            font-family: 'Cascadia Code', 'Consolas', monospace;
            font-size: 12px;
        }
        .file-table tr:hover td { background: #1a1a2e; }
        .hash-cell { color: #78909c; font-size: 11px; }
        .size-cell { color: #4fc3f7; text-align: right; }

        /* Verify output */
        .verify-output {
            background: #0a0a0f;
            border: 1px solid #1e1e2e;
            border-radius: 4px;
            padding: 16px;
            margin-top: 12px;
            font-family: 'Cascadia Code', 'Consolas', monospace;
            font-size: 12px;
            white-space: pre-wrap;
            max-height: 400px;
            overflow-y: auto;
        }
        .verify-output .line-ok { color: #66bb6a; }
        .verify-output .line-fail { color: #ef5350; }
        .verify-output .line-warn { color: #ffa726; }
        .verify-output .line-info { color: #78909c; }

        /* Buttons */
        .btn {
            padding: 8px 16px;
            border: 1px solid #1e3a5f;
            border-radius: 6px;
            background: #0f1923;
            color: #4fc3f7;
            font-size: 13px;
            cursor: pointer;
            transition: all 0.2s;
            font-family: inherit;
        }
        .btn:hover { background: #1a2940; border-color: #4fc3f7; }
        .btn:disabled { opacity: 0.4; cursor: not-allowed; }
        .btn.primary { background: #1565c0; border-color: #1565c0; color: white; }
        .btn.primary:hover { background: #1976d2; }
        .btn.danger { border-color: #c62828; color: #ef5350; }
        .btn.danger:hover { background: #1a0a0a; }

        /* Merkle tree visualization */
        .merkle-viz {
            padding: 16px;
            background: #0a0a0f;
            border: 1px solid #1e1e2e;
            border-radius: 4px;
            margin-top: 12px;
            overflow-x: auto;
        }
        .merkle-node {
            display: inline-block;
            padding: 4px 8px;
            margin: 2px;
            border-radius: 3px;
            font-family: 'Cascadia Code', monospace;
            font-size: 10px;
        }
        .merkle-root { background: #1565c0; color: white; }
        .merkle-internal { background: #1e1e2e; color: #78909c; }
        .merkle-leaf { background: #1b5e20; color: #66bb6a; }
        .merkle-level { margin: 8px 0; text-align: center; }
        .merkle-level-label { color: #444; font-size: 10px; margin-right: 8px; }

        /* New audit form */
        .audit-form {
            display: none;
            background: #12121a;
            border: 1px solid #1e1e2e;
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 16px;
        }
        .audit-form.visible { display: block; }
        .audit-form input {
            background: #0a0a0f;
            border: 1px solid #1e1e2e;
            border-radius: 4px;
            padding: 10px 14px;
            color: #e0e0e0;
            font-family: 'Cascadia Code', monospace;
            font-size: 14px;
            width: 100%;
            margin-top: 8px;
        }
        .audit-form input:focus { outline: none; border-color: #4fc3f7; }
        .audit-form label { font-size: 13px; color: #78909c; }
        .form-actions { margin-top: 12px; display: flex; gap: 8px; }

        /* Spinner */
        .spinner {
            display: inline-block;
            width: 14px;
            height: 14px;
            border: 2px solid #1e3a5f;
            border-top: 2px solid #4fc3f7;
            border-radius: 50%;
            animation: spin 0.8s linear infinite;
            margin-right: 6px;
            vertical-align: middle;
        }
        @keyframes spin { to { transform: rotate(360deg); } }

        /* Empty state */
        .empty-state {
            text-align: center;
            padding: 60px 20px;
            color: #444;
        }
        .empty-state h2 { color: #555; margin-bottom: 8px; }

        /* Tabs */
        .tab-bar {
            display: flex;
            gap: 0;
            margin-bottom: 16px;
        }
        .tab {
            padding: 8px 20px;
            font-size: 13px;
            color: #666;
            border-bottom: 2px solid transparent;
            cursor: pointer;
            transition: all 0.2s;
        }
        .tab:hover { color: #aaa; }
        .tab.active { color: #4fc3f7; border-bottom-color: #4fc3f7; }
    </style>
</head>
<body>

<div class="header">
    <h1>ASI-OMEGA <span>Audit Dashboard</span></h1>
    <div class="header-actions">
        <button class="btn" onclick="toggleAuditForm()">+ Ny audit</button>
        <button class="btn" onclick="refreshAll()">Oppdater</button>
    </div>
</div>

<div class="container">
    <!-- Stats -->
    <div class="stats-bar">
        <div class="stat-card">
            <div class="label">Audits</div>
            <div class="value" id="stat-audits">-</div>
        </div>
        <div class="stat-card">
            <div class="label">Filer totalt</div>
            <div class="value" id="stat-files">-</div>
        </div>
        <div class="stat-card">
            <div class="label">Total storrelse</div>
            <div class="value" id="stat-size">-</div>
        </div>
        <div class="stat-card">
            <div class="label">Siste audit</div>
            <div class="value" id="stat-last" style="font-size:16px;">-</div>
        </div>
    </div>

    <!-- New audit form -->
    <div class="audit-form" id="auditForm">
        <label>Mappe-sti:</label>
        <input type="text" id="auditPath" placeholder="F.eks. C:\\Users\\Bruker\\Documents\\prosjekt">
        <div class="form-actions">
            <button class="btn primary" onclick="startAudit()">Start audit</button>
            <button class="btn" onclick="toggleAuditForm()">Avbryt</button>
        </div>
    </div>

    <!-- Audit list -->
    <div class="section">
        <div class="section-title">Registrerte audits</div>
        <div id="auditList"></div>
    </div>
</div>

<script>
let audits = [];
let verifyResults = {};

async function loadAudits() {
    const resp = await fetch('/api/audits');
    audits = await resp.json();
    renderAudits();
    updateStats();
}

function updateStats() {
    document.getElementById('stat-audits').textContent = audits.length;
    document.getElementById('stat-files').textContent = audits.reduce((s, a) => s + a.file_count, 0);

    const totalBytes = audits.reduce((s, a) => s + (a.total_size || 0), 0);
    document.getElementById('stat-size').textContent = formatSize(totalBytes);

    if (audits.length > 0) {
        const dates = audits.map(a => a.generated).filter(Boolean).sort().reverse();
        if (dates[0]) {
            const d = new Date(dates[0]);
            document.getElementById('stat-last').textContent = d.toLocaleDateString('nb-NO') + ' ' + d.toLocaleTimeString('nb-NO', {hour:'2-digit', minute:'2-digit'});
        }
    }
}

function formatSize(bytes) {
    if (!bytes) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    let i = 0;
    let size = bytes;
    while (size >= 1024 && i < units.length - 1) { size /= 1024; i++; }
    return size.toFixed(1) + ' ' + units[i];
}

function renderAudits() {
    const container = document.getElementById('auditList');
    if (audits.length === 0) {
        container.innerHTML = '<div class="empty-state"><h2>Ingen audits funnet</h2><p>Klikk "+ Ny audit" for aa starte</p></div>';
        return;
    }

    container.innerHTML = audits.map((a, i) => `
        <div class="audit-card" id="card-${i}" onclick="toggleDetail(${i}, event)">
            <div class="audit-header">
                <div>
                    <div class="audit-path">${escHtml(a.path)}</div>
                    <div class="audit-meta">
                        <span>${a.file_count} filer</span>
                        <span>${formatSize(a.total_size)}</span>
                        <span>${a.generated ? new Date(a.generated).toLocaleString('nb-NO') : 'ukjent'}</span>
                        <span>${a.platform}</span>
                    </div>
                </div>
                <span class="badge ${verifyResults[i] === true ? 'verified' : verifyResults[i] === false ? 'failed' : 'pending'}">
                    ${verifyResults[i] === true ? 'VERIFISERT' : verifyResults[i] === false ? 'FEILET' : 'IKKE SJEKKET'}
                </span>
            </div>
            <div class="merkle-hash">Merkle: ${a.merkle_root}</div>

            <div class="detail-panel" id="detail-${i}">
                <div class="tab-bar">
                    <div class="tab active" onclick="showTab(${i}, 'files')">Filer</div>
                    <div class="tab" onclick="showTab(${i}, 'merkle')">Merkle-tre</div>
                    <div class="tab" onclick="showTab(${i}, 'verify')">Verifiser</div>
                </div>
                <div id="tab-files-${i}"><div style="color:#666">Laster...</div></div>
                <div id="tab-merkle-${i}" style="display:none"></div>
                <div id="tab-verify-${i}" style="display:none">
                    <button class="btn primary" onclick="runVerify(${i})">Kjor verifisering</button>
                    <div id="verify-output-${i}"></div>
                </div>
            </div>
        </div>
    `).join('');
}

function escHtml(s) {
    return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

async function toggleDetail(idx, ev) {
    // Don't toggle if clicking inside detail panel (tabs, buttons, etc)
    if (ev && ev.target.closest('.detail-panel')) return;

    const panel = document.getElementById(`detail-${idx}`);
    const card = document.getElementById(`card-${idx}`);
    const isVisible = panel.classList.contains('visible');

    // Close all
    document.querySelectorAll('.detail-panel').forEach(p => p.classList.remove('visible'));
    document.querySelectorAll('.audit-card').forEach(c => c.classList.remove('expanded'));

    if (!isVisible) {
        panel.classList.add('visible');
        card.classList.add('expanded');
        loadFiles(idx);
    }
}

async function loadFiles(idx) {
    const a = audits[idx];
    const resp = await fetch('/api/manifest?path=' + encodeURIComponent(a.asi_dir));
    const files = await resp.json();

    const container = document.getElementById(`tab-files-${idx}`);
    if (files.length === 0) {
        container.innerHTML = '<div style="color:#666">Ingen filer i manifest</div>';
        return;
    }

    container.innerHTML = `
        <table class="file-table">
            <thead><tr><th>Fil</th><th>SHA-256</th><th style="text-align:right">Storrelse</th></tr></thead>
            <tbody>
                ${files.map(f => `
                    <tr>
                        <td>${escHtml(f.rel)}</td>
                        <td class="hash-cell" title="${f.sha256}">${f.sha256.substring(0,16)}...</td>
                        <td class="size-cell">${formatSize(parseInt(f.size))}</td>
                    </tr>
                `).join('')}
            </tbody>
        </table>
    `;

    // Build merkle visualization
    buildMerkleViz(idx, files.map(f => f.sha256));
}

function buildMerkleViz(idx, hashes) {
    if (hashes.length === 0) return;

    // Simulate Merkle tree levels
    let levels = [hashes.map(h => h.substring(0, 12))];
    let current = hashes;

    while (current.length > 1) {
        let next = [];
        for (let i = 0; i < current.length; i += 2) {
            if (i + 1 < current.length) {
                // Simplified viz hash
                next.push(('N' + current[i].substring(0, 5) + current[i+1].substring(0, 5)).substring(0, 12));
            } else {
                next.push(current[i].substring(0, 12));
            }
        }
        levels.push(next.map(h => h.substring(0, 12)));
        current = next;
    }

    levels.reverse();

    const container = document.getElementById(`tab-merkle-${idx}`);
    let html = '<div class="merkle-viz">';

    levels.forEach((level, li) => {
        const cls = li === 0 ? 'merkle-root' : li === levels.length - 1 ? 'merkle-leaf' : 'merkle-internal';
        const label = li === 0 ? 'ROT' : li === levels.length - 1 ? 'BLADER' : `NIVAA ${levels.length - 1 - li}`;
        html += `<div class="merkle-level">`;
        html += `<span class="merkle-level-label">${label}</span>`;
        // Show max 16 nodes per level for readability
        const shown = level.slice(0, 16);
        shown.forEach(h => {
            html += `<span class="merkle-node ${cls}">${h}...</span>`;
        });
        if (level.length > 16) {
            html += `<span class="merkle-node ${cls}">+${level.length - 16} til</span>`;
        }
        html += '</div>';
    });

    html += '</div>';
    container.innerHTML = html;
}

function showTab(idx, tab) {
    ['files', 'merkle', 'verify'].forEach(t => {
        const el = document.getElementById(`tab-${t}-${idx}`);
        if (el) el.style.display = t === tab ? 'block' : 'none';
    });
    // Update active tab
    const card = document.getElementById(`card-${idx}`);
    card.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    event.target.classList.add('active');
}

async function runVerify(idx) {
    const a = audits[idx];
    const outputEl = document.getElementById(`verify-output-${idx}`);
    outputEl.innerHTML = '<div style="margin-top:12px"><span class="spinner"></span> Verifiserer...</div>';

    const resp = await fetch('/api/verify', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({path: a.path})
    });
    const result = await resp.json();
    verifyResults[idx] = result.passed;

    let html = '<div class="verify-output">';
    result.output.forEach(line => {
        let cls = 'line-info';
        if (line.includes('OK:')) cls = 'line-ok';
        else if (line.includes('FEIL:')) cls = 'line-fail';
        else if (line.includes('ADVARSEL:')) cls = 'line-warn';
        else if (line.includes('BESTATT')) cls = 'line-ok';
        else if (line.includes('FEILET')) cls = 'line-fail';
        html += `<div class="${cls}">${escHtml(line)}</div>`;
    });
    html += '</div>';
    outputEl.innerHTML = html;

    // Update badge without re-rendering entire list
    const card = document.getElementById(`card-${idx}`);
    const badge = card.querySelector('.badge');
    if (badge) {
        badge.className = 'badge ' + (result.passed ? 'verified' : 'failed');
        badge.textContent = result.passed ? 'VERIFISERT' : 'FEILET';
    }
}

function toggleAuditForm() {
    document.getElementById('auditForm').classList.toggle('visible');
    document.getElementById('auditPath').focus();
}

async function startAudit() {
    const path = document.getElementById('auditPath').value.trim();
    if (!path) return;

    const form = document.getElementById('auditForm');
    form.innerHTML = '<div><span class="spinner"></span> Kjorer audit paa ' + escHtml(path) + '...</div>';

    const resp = await fetch('/api/audit', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({path: path})
    });
    const result = await resp.json();

    if (result.success) {
        form.classList.remove('visible');
        form.innerHTML = `
            <label>Mappe-sti:</label>
            <input type="text" id="auditPath" placeholder="F.eks. C:\\\\Users\\\\Bruker\\\\Documents\\\\prosjekt">
            <div class="form-actions">
                <button class="btn primary" onclick="startAudit()">Start audit</button>
                <button class="btn" onclick="toggleAuditForm()">Avbryt</button>
            </div>
        `;
        await loadAudits();
    } else {
        form.innerHTML = `
            <div style="color:#ef5350;margin-bottom:12px">Audit feilet: ${escHtml(result.output.join(', '))}</div>
            <label>Mappe-sti:</label>
            <input type="text" id="auditPath" value="${escHtml(path)}" placeholder="F.eks. C:\\\\Users\\\\Bruker\\\\Documents\\\\prosjekt">
            <div class="form-actions">
                <button class="btn primary" onclick="startAudit()">Prov igjen</button>
                <button class="btn" onclick="toggleAuditForm()">Avbryt</button>
            </div>
        `;
    }
}

async function refreshAll() {
    verifyResults = {};
    await loadAudits();
}

// Init
loadAudits();
</script>
</body>
</html>
"""


# ─────────────────────────────────────────────────────
# Flask routes
# ─────────────────────────────────────────────────────

@app.route("/")
def index():
    return render_template_string(DASHBOARD_HTML)


@app.route("/api/audits")
def api_audits():
    # Search common locations
    search_paths = []

    # Check query param
    base = request.args.get("base")
    if base:
        search_paths.append(base)

    # Default search paths
    search_paths.extend([
        str(Path(__file__).parent.parent),  # audit-pipeline/
        "E:/IT-TECH",
        "C:/Claude/Projects",
    ])

    all_audits = []
    seen = set()
    for p in search_paths:
        if os.path.isdir(p):
            for a in find_audits(p):
                if a["asi_dir"] not in seen:
                    seen.add(a["asi_dir"])
                    all_audits.append(a)

    return jsonify(all_audits)


@app.route("/api/manifest")
def api_manifest():
    asi_dir = request.args.get("path", "")
    if not asi_dir or not os.path.isdir(asi_dir):
        return jsonify([])
    entries = load_manifest(asi_dir)
    return jsonify(entries)


@app.route("/api/verify", methods=["POST"])
def api_verify():
    data = request.get_json()
    target = data.get("path", "")
    if not target or not os.path.isdir(target):
        return jsonify({"passed": False, "output": ["Ugyldig sti"], "returncode": -1})
    result = run_verify(target)
    return jsonify(result)


@app.route("/api/audit", methods=["POST"])
def api_audit():
    data = request.get_json()
    target = data.get("path", "")
    if not target or not os.path.isdir(target):
        return jsonify({"success": False, "output": ["Ugyldig sti"], "returncode": -1})
    result = run_audit(target)
    return jsonify(result)


# ─────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────

def start_dashboard(port: int = 5050):
    """Start dashboard server."""
    print(f"\n  ASI-Omega Audit Dashboard")
    print(f"  http://localhost:{port}")
    print(f"  Trykk Ctrl+C for aa stoppe\n")
    app.run(host="0.0.0.0", port=port, debug=False)


if __name__ == "__main__":
    port = 5050
    if "--port" in sys.argv:
        idx = sys.argv.index("--port")
        if idx + 1 < len(sys.argv):
            port = int(sys.argv[idx + 1])
    start_dashboard(port)
