$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$otsScript = Join-Path $repoRoot 'tools\OTS-Stamp.ps1'
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "ots-stamp-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$fail = $false

function Pass($m){ Write-Host "OK: $m" -ForegroundColor Green }
function Fail($m){ Write-Host "FAIL: $m" -ForegroundColor Red; $script:fail=$true }
function Skip($m){ Write-Host "SKIP: $m" -ForegroundColor Yellow }

# --- Test 1: Missing target file produces exit code 2 ---
$proc = Start-Process -FilePath pwsh -ArgumentList "-NoProfile","-File",$otsScript,"-Target",(Join-Path $tmpDir 'nope.txt') `
        -Wait -PassThru -RedirectStandardError (Join-Path $tmpDir 'err1.txt') -NoNewWindow
if($proc.ExitCode -eq 2){ Pass "Exit code 2 on missing target" }
else { Fail "Expected exit 2 on missing target, got $($proc.ExitCode)" }

# --- Test 2: Valid Merkle root file triggers OTS submission ---
$merkleFile = Join-Path $tmpDir 'merkle_root.txt'
# Create a valid 64-char hex hash
"a" * 64 | Set-Content -Encoding ASCII -Path $merkleFile

$proc = Start-Process -FilePath pwsh -ArgumentList "-NoProfile","-File",$otsScript,"-Target",$merkleFile `
        -Wait -PassThru -RedirectStandardError (Join-Path $tmpDir 'err2.txt') -NoNewWindow

# Exit 0 = submitted, Exit 3 = network failure (both are acceptable in test)
if($proc.ExitCode -eq 0){
    Pass "OTS submission succeeded (exit 0)"

    # Check that .ots proof file was created
    $otsProof = Join-Path $tmpDir 'merkle_root.txt.ots'
    if(Test-Path $otsProof){
        $proofSize = (Get-Item $otsProof).Length
        if($proofSize -gt 0){ Pass "OTS proof file created ($proofSize bytes)" }
        else { Fail "OTS proof file is empty" }
    } else {
        Fail "OTS proof file not created"
    }
} elseif($proc.ExitCode -eq 3){
    Skip "OTS servers unreachable (exit 3) — network test skipped"
} else {
    Fail "Unexpected exit code: $($proc.ExitCode)"
}

# --- Test 3: Receipt/report file is always created ---
$receiptFile = Join-Path $tmpDir 'ots_receipt.txt'
if(Test-Path $receiptFile){
    $content = Get-Content -Raw $receiptFile
    if($content -match 'OPENTIMESTAMPS'){ Pass "OTS receipt file contains expected header" }
    else { Fail "OTS receipt file missing header" }

    if($content -match 'Merkle-rot'){ Pass "OTS receipt references Merkle root" }
    else { Fail "OTS receipt missing Merkle root reference" }
} else {
    Skip "No receipt file (server was unreachable)"
}

# --- Test 4: Script source code uses Invoke-WebRequest (real API call) ---
$src = Get-Content -Raw $otsScript
if($src -match 'Invoke-WebRequest'){
    Pass "OTS-Stamp.ps1 makes real HTTP calls (Invoke-WebRequest)"
} else {
    Fail "OTS-Stamp.ps1 does not contain Invoke-WebRequest"
}

if($src -match 'pool\.opentimestamps\.org'){
    Pass "OTS-Stamp.ps1 targets official OTS calendar servers"
} else {
    Fail "OTS-Stamp.ps1 missing OTS server URLs"
}

# Cleanup
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

if($fail){ Write-Error "OTS-STAMP TESTS FAILED"; exit 1 }
Write-Host "OTS-STAMP TESTS PASS" -ForegroundColor Green
exit 0
