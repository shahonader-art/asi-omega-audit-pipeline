$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$signScript = Join-Path $repoRoot 'tools\Sign-Audit.ps1'
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "sign-audit-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$fail = $false

function Pass($m){ Write-Host "OK: $m" -ForegroundColor Green }
function Fail($m){ Write-Host "FAIL: $m" -ForegroundColor Red; $script:fail=$true }
function Skip($m){ Write-Host "SKIP: $m" -ForegroundColor Yellow }

# --- Test 1: Script exits 10 if GPG is not installed ---
# (May or may not apply depending on CI environment)
$gpgAvailable = $null -ne (Get-Command gpg -ErrorAction SilentlyContinue)

if(-not $gpgAvailable){
    # No GPG — test that script reports it cleanly
    $proc = Start-Process -FilePath pwsh -ArgumentList "-NoProfile","-File",$signScript,"-AuditDir",$tmpDir `
            -Wait -PassThru -RedirectStandardError (Join-Path $tmpDir 'err1.txt') -NoNewWindow
    if($proc.ExitCode -eq 10){ Pass "Exit 10 when GPG not installed (clean error)" }
    else { Fail "Expected exit 10 without GPG, got $($proc.ExitCode)" }
    Skip "GPG not available — skipping signing tests"
} else {
    # GPG is available — test signing flow
    Pass "GPG is installed"

    # Create dummy audit files
    $dodDir = Join-Path $tmpDir 'DoD'
    New-Item -ItemType Directory -Force -Path $dodDir | Out-Null
    "test manifest" | Set-Content (Join-Path $tmpDir 'manifest.csv')
    "test merkle root" | Set-Content (Join-Path $tmpDir 'merkle_root.txt')
    '{"test":true}' | Set-Content (Join-Path $dodDir 'DoD.json')

    # --- Test 2: Signs all files with -Auto flag ---
    $proc = Start-Process -FilePath pwsh `
        -ArgumentList "-NoProfile","-File",$signScript,"-AuditDir",$tmpDir,"-Auto" `
        -Wait -PassThru -RedirectStandardError (Join-Path $tmpDir 'err2.txt') -NoNewWindow

    if($proc.ExitCode -eq 0){
        Pass "Sign-Audit.ps1 completed successfully"

        # Check .asc files were created
        $expectedSigs = @(
            (Join-Path $tmpDir 'manifest.csv.asc'),
            (Join-Path $tmpDir 'merkle_root.txt.asc'),
            (Join-Path $dodDir 'DoD.json.asc')
        )
        foreach($sig in $expectedSigs){
            if(Test-Path $sig){
                $content = Get-Content -Raw $sig
                if($content -match 'BEGIN PGP SIGNATURE'){
                    Pass "Signature created: $(Split-Path -Leaf $sig)"
                } else {
                    Fail "Signature file exists but invalid: $(Split-Path -Leaf $sig)"
                }
            } else {
                Fail "Missing signature: $(Split-Path -Leaf $sig)"
            }
        }
    } elseif($proc.ExitCode -eq 11){
        Skip "No GPG keys found — cannot test signing"
    } else {
        Fail "Sign-Audit.ps1 failed with exit $($proc.ExitCode)"
    }
}

# --- Test 3: Script source handles multiple GPG paths ---
$src = Get-Content -Raw $signScript
if($src -match 'GnuPG'){ Pass "Script checks common GPG install paths" }
else { Fail "Script missing GPG path detection" }

if($src -match 'gpg2'){ Pass "Script tries gpg2 as fallback" }
else { Fail "Script missing gpg2 fallback" }

# Cleanup
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

if($fail){ Write-Error "SIGN-AUDIT TESTS FAILED"; exit 1 }
Write-Host "SIGN-AUDIT TESTS PASS" -ForegroundColor Green
exit 0
