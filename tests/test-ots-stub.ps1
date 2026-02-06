$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$otsScript = Join-Path $repoRoot 'tools\OTS-Stub.ps1'
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "ots-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$fail = $false

function Pass($m){ Write-Host "OK: $m" -ForegroundColor Green }
function Fail($m){ Write-Host "FAIL: $m" -ForegroundColor Red; $script:fail=$true }

# --- Test 1: Missing target file produces exit code 2 ---
$missingTarget = Join-Path $tmpDir 'nonexistent.txt'
$proc = Start-Process -FilePath pwsh -ArgumentList "-NoProfile","-File",$otsScript,"-Target",$missingTarget `
        -Wait -PassThru -RedirectStandardError (Join-Path $tmpDir 'err1.txt') -NoNewWindow
if($proc.ExitCode -eq 2){ Pass "Exit code 2 on missing target" }
else { Fail "Expected exit 2 on missing target, got $($proc.ExitCode)" }

# --- Test 2: Valid target produces ots_request.txt ---
$targetFile = Join-Path $tmpDir 'merkle_root.txt'
"abc123def456" | Set-Content -Encoding ASCII -Path $targetFile
$proc = Start-Process -FilePath pwsh -ArgumentList "-NoProfile","-File",$otsScript,"-Target",$targetFile `
        -Wait -PassThru -NoNewWindow
$otsOut = Join-Path $tmpDir 'ots_request.txt'
if($proc.ExitCode -eq 0){ Pass "Exit code 0 on valid target" }
else { Fail "Expected exit 0, got $($proc.ExitCode)" }

if(Test-Path $otsOut){ Pass "ots_request.txt created" }
else { Fail "ots_request.txt not created" }

# --- Test 3: Output contains valid 64-char lowercase hex SHA-256 ---
if(Test-Path $otsOut){
    $content = Get-Content -Raw -Path $otsOut
    if($content -match '[0-9a-f]{64}'){ Pass "Output contains valid SHA-256 hex" }
    else { Fail "Output missing valid SHA-256 hex string" }
}

# --- Test 4: Output file is in same directory as target ---
if(Test-Path $otsOut){
    $otsDir = Split-Path -Parent $otsOut
    $targetDir = Split-Path -Parent $targetFile
    if($otsDir -eq $targetDir){ Pass "Output in same directory as target" }
    else { Fail "Output directory mismatch: $otsDir vs $targetDir" }
}

# Cleanup
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

if($fail){ Write-Error "OTS-STUB TESTS FAILED"; exit 1 }
Write-Host "OTS-STUB TESTS PASS" -ForegroundColor Green
exit 0
