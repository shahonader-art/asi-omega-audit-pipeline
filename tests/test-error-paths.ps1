$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "errpath-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$fail = $false

function Pass($m){ Write-Host "OK: $m" -ForegroundColor Green }
function Fail($m){ Write-Host "FAIL: $m" -ForegroundColor Red; $script:fail=$true }

# Helper: run a script and capture exit code (avoids Start-Process argument issues)
function Run-Script{
    param([string]$ScriptPath, [string[]]$ScriptArgs)
    $argString = "-NoProfile -File `"$ScriptPath`""
    foreach($a in $ScriptArgs){ $argString += " $a" }
    $errFile = Join-Path $tmpDir "err-$([guid]::NewGuid().ToString('N').Substring(0,8)).txt"
    $outFile = Join-Path $tmpDir "out-$([guid]::NewGuid().ToString('N').Substring(0,8)).txt"
    $proc = Start-Process -FilePath 'pwsh' -ArgumentList $argString `
            -Wait -PassThru -RedirectStandardError $errFile -RedirectStandardOutput $outFile -NoNewWindow
    Remove-Item $errFile -ErrorAction SilentlyContinue
    Remove-Item $outFile -ErrorAction SilentlyContinue
    return $proc.ExitCode
}

# =====================================================================
# Merkle.ps1 error paths
# =====================================================================
$merkleScript = Join-Path $repoRoot 'tools\Merkle.ps1'

# --- Merkle: missing CsvPath parameter -> exit 1 ---
$code = Run-Script -ScriptPath $merkleScript -ScriptArgs @()
if($code -ne 0){ Pass "Merkle: non-zero exit on missing CsvPath" }
else { Fail "Merkle: expected non-zero exit on missing CsvPath, got $code" }

# --- Merkle: missing CSV file -> exit 2 ---
$code = Run-Script -ScriptPath $merkleScript -ScriptArgs @("-CsvPath", "`"$(Join-Path $tmpDir 'nonexistent.csv')`"")
if($code -eq 2){ Pass "Merkle: exit 2 on missing CSV" }
else { Fail "Merkle: expected exit 2 on missing CSV, got $code" }

# --- Merkle: empty CSV file -> exit 3 ---
$emptyCsv = Join-Path $tmpDir 'empty.csv'
"" | Set-Content -Encoding UTF8 -Path $emptyCsv
$code = Run-Script -ScriptPath $merkleScript -ScriptArgs @("-CsvPath", "`"$emptyCsv`"")
if($code -eq 3){ Pass "Merkle: exit 3 on empty CSV" }
else { Fail "Merkle: expected exit 3 on empty CSV, got $code" }

# --- Merkle: CSV with headers only, no data rows -> exit 3 ---
$headerOnlyCsv = Join-Path $tmpDir 'headers_only.csv'
'"Rel","SHA256"' | Set-Content -Encoding UTF8 -Path $headerOnlyCsv
$code = Run-Script -ScriptPath $merkleScript -ScriptArgs @("-CsvPath", "`"$headerOnlyCsv`"")
if($code -eq 3 -or $code -eq 4){ Pass "Merkle: exit $code on header-only CSV" }
else { Fail "Merkle: expected exit 3 or 4 on header-only CSV, got $code" }

# --- Merkle: CSV with missing Rel/SHA256 columns -> exit 4 ---
$badColsCsv = Join-Path $tmpDir 'bad_cols.csv'
@('"Name","Value"', '"foo","bar"') | Set-Content -Encoding UTF8 -Path $badColsCsv
$code = Run-Script -ScriptPath $merkleScript -ScriptArgs @("-CsvPath", "`"$badColsCsv`"")
if($code -eq 4){ Pass "Merkle: exit 4 on CSV missing Rel/SHA256 columns" }
else { Fail "Merkle: expected exit 4 on bad columns, got $code" }

# =====================================================================
# run_demo.ps1 error paths
# =====================================================================
$demoScript = Join-Path $repoRoot 'src\run_demo.ps1'

# --- run_demo: DryRun flag does not create manifest.csv ---
$dryOutDir = Join-Path $tmpDir 'dryrun_output'
New-Item -ItemType Directory -Force -Path $dryOutDir | Out-Null
$code = Run-Script -ScriptPath $demoScript -ScriptArgs @("-Out", "`"$dryOutDir`"", "-DryRun")
$dryManifest = Join-Path $dryOutDir 'manifest.csv'
if($code -eq 0){ Pass "run_demo: DryRun exits 0" }
else { Fail "run_demo: DryRun expected exit 0, got $code" }
if(-not (Test-Path $dryManifest)){ Pass "run_demo: DryRun does not create manifest.csv" }
else { Fail "run_demo: DryRun should not create manifest.csv" }

# =====================================================================
# verify.ps1 error paths
# =====================================================================
$verifyScript = Join-Path $repoRoot 'tools\verify.ps1'

# --- verify: missing DoD file -> exit 2 ---
$code = Run-Script -ScriptPath $verifyScript -ScriptArgs @(
    "-DoD", "`"$(Join-Path $tmpDir 'nope.json')`"",
    "-Manifest", "`"$(Join-Path $tmpDir 'nope.csv')`"",
    "-MerkleRoot", "`"$(Join-Path $tmpDir 'nope.txt')`""
)
if($code -eq 2){ Pass "verify: exit 2 on missing files" }
else { Fail "verify: expected exit 2 on missing files, got $code" }

# --- verify: DoD with missing merkle_root field -> exit 2 ---
$badDodDir = Join-Path $tmpDir 'bad_dod'
New-Item -ItemType Directory -Force -Path $badDodDir | Out-Null
$badDod = Join-Path $badDodDir 'DoD.json'
'{"name":"test"}' | Set-Content -Encoding UTF8 -Path $badDod
$badManifest = Join-Path $badDodDir 'manifest.csv'
@('"Rel","SHA256"','"sample/file.txt","aabb"') | Set-Content -Encoding UTF8 -Path $badManifest
$badRoot = Join-Path $badDodDir 'merkle_root.txt'
"aabb" | Set-Content -Encoding ASCII -Path $badRoot
$code = Run-Script -ScriptPath $verifyScript -ScriptArgs @(
    "-DoD", "`"$badDod`"",
    "-Manifest", "`"$badManifest`"",
    "-MerkleRoot", "`"$badRoot`""
)
if($code -eq 2){ Pass "verify: exit 2 on DoD missing merkle_root" }
else { Fail "verify: expected exit 2 on DoD missing merkle_root, got $code" }

# Cleanup
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

if($fail){ Write-Error "ERROR-PATH TESTS FAILED"; exit 1 }
Write-Host "ERROR-PATH TESTS PASS" -ForegroundColor Green
exit 0
