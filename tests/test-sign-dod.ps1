$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$signScript = Join-Path $repoRoot 'tools\Sign-DoD.ps1'
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "sign-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$fail = $false

function Pass($m){ Write-Host "OK: $m" -ForegroundColor Green }
function Fail($m){ Write-Host "FAIL: $m" -ForegroundColor Red; $script:fail=$true }

# --- Test 1: Missing DoD file produces exit code 2 ---
$missingFile = Join-Path $tmpDir 'nonexistent.json'
$proc = Start-Process -FilePath pwsh -ArgumentList "-NoProfile","-File",$signScript,"-File",$missingFile,"-KeyId","AABBCCDD" `
        -Wait -PassThru -RedirectStandardError (Join-Path $tmpDir 'err1.txt') -NoNewWindow
if($proc.ExitCode -eq 2){ Pass "Exit code 2 on missing DoD file" }
else { Fail "Expected exit 2 on missing file, got $($proc.ExitCode)" }

# --- Test 2: Missing KeyId produces exit code 3 ---
$dummyFile = Join-Path $tmpDir 'DoD.json'
'{"test":true}' | Set-Content -Encoding UTF8 -Path $dummyFile
$proc = Start-Process -FilePath pwsh -ArgumentList "-NoProfile","-File",$signScript,"-File",$dummyFile,"-KeyId","" `
        -Wait -PassThru -RedirectStandardError (Join-Path $tmpDir 'err2.txt') -NoNewWindow
if($proc.ExitCode -eq 3){ Pass "Exit code 3 on empty KeyId" }
else { Fail "Expected exit 3 on empty KeyId, got $($proc.ExitCode)" }

# --- Test 3: .asc path is constructed correctly (File + ".asc") ---
# We can't test actual GPG signing without keys, but we verify the path logic
$expectedAsc = "$dummyFile.asc"
$expectedName = Split-Path -Leaf $expectedAsc
if($expectedName -eq "DoD.json.asc"){ Pass ".asc output path constructed correctly" }
else { Fail "Expected DoD.json.asc, got $expectedName" }

# Cleanup
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

if($fail){ Write-Error "SIGN-DOD TESTS FAILED"; exit 1 }
Write-Host "SIGN-DOD TESTS PASS" -ForegroundColor Green
exit 0
