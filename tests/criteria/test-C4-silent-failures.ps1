# Criterion 4: NO SILENT FAILURES
# Every failure mode must produce a non-zero exit code and visible error output.
$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "C4-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$fail = $false; $gap = $false

function Pass($id,$m){ Write-Host "PASS [$id]: $m" -ForegroundColor Green }
function Fail($id,$m){ Write-Host "FAIL [$id]: $m" -ForegroundColor Red; $script:fail=$true }
function Gap($id,$m){ Write-Host "KNOWN-GAP [$id]: $m" -ForegroundColor Yellow; $script:gap=$true }

function Run-Script([string]$ScriptPath, [string[]]$ScriptArgs){
    $outFile = Join-Path $tmpDir "out-$([guid]::NewGuid().ToString('N').Substring(0,8)).txt"
    $errFile = Join-Path $tmpDir "err-$([guid]::NewGuid().ToString('N').Substring(0,8)).txt"
    $argString = ($ScriptArgs | ForEach-Object { "`"$_`"" }) -join ' '
    $proc = Start-Process -FilePath pwsh -ArgumentList "-NoProfile -File `"$ScriptPath`" $argString" `
            -Wait -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile -NoNewWindow
    $stdout = if(Test-Path $outFile){ Get-Content -Raw $outFile } else { "" }
    $stderr = if(Test-Path $errFile){ Get-Content -Raw $errFile } else { "" }
    return @{ ExitCode=$proc.ExitCode; Stdout=$stdout; Stderr=$stderr }
}

# =====================================================================
# S1: Missing input files must exit non-zero
# =====================================================================
$merkleScript = Join-Path $repoRoot 'tools\Merkle.ps1'
$verifyScript = Join-Path $repoRoot 'tools\verify.ps1'

# Merkle with missing CSV
$r = Run-Script $merkleScript @("-CsvPath", (Join-Path $tmpDir 'ghost.csv'))
if($r.ExitCode -ne 0){ Pass "S1a" "Merkle.ps1 exits non-zero on missing CSV (exit $($r.ExitCode))" }
else { Fail "S1a" "Merkle.ps1 exits 0 on missing CSV — silent failure" }

# verify with missing files
$r = Run-Script $verifyScript @("-DoD","ghost.json","-Manifest","ghost.csv","-MerkleRoot","ghost.txt")
if($r.ExitCode -ne 0){ Pass "S1b" "verify.ps1 exits non-zero on missing files (exit $($r.ExitCode))" }
else { Fail "S1b" "verify.ps1 exits 0 on missing files — silent failure" }

# =====================================================================
# S2: NTP failure must not silently return magic values
# =====================================================================
$ntpScript = Join-Path $repoRoot 'tools\NtpDrift.ps1'
$r = Run-Script $ntpScript @("-Server","invalid.ntp.server.example.com","-Samples","1")
$ntpOutput = $r.Stdout.Trim()

# Check if the script returns 9999 (magic value for failure)
if($ntpOutput -eq '9999'){
    Gap "S2" "NtpDrift.ps1 returns magic value 9999 on failure — no error message, exit code is $($r.ExitCode)"
} elseif($r.ExitCode -ne 0){
    Pass "S2" "NtpDrift.ps1 exits non-zero on NTP failure (exit $($r.ExitCode))"
} else {
    # Could be legitimate measurement or silent failure
    try {
        $val = [double]$ntpOutput
        if([math]::Abs($val) -lt 100){
            Pass "S2" "NtpDrift.ps1 returned plausible value: $val"
        } else {
            Gap "S2" "NtpDrift.ps1 returned suspicious value $val with exit 0"
        }
    } catch {
        Gap "S2" "NtpDrift.ps1 returned unparseable output: '$ntpOutput'"
    }
}

# =====================================================================
# S3: Merkle computation failure must propagate to DoD
# =====================================================================
$dodScript = Join-Path $repoRoot 'tools\DoD.ps1'

# Check DoD.ps1 source code for try/catch{} (empty catch blocks)
$dodSrc = Get-Content -Raw $dodScript
$emptyCatchCount = ([regex]::Matches($dodSrc, 'catch\s*\{\s*\}')).Count
if($emptyCatchCount -gt 0){
    Gap "S3" "DoD.ps1 has $emptyCatchCount empty catch{} blocks — errors are silently swallowed"
} else {
    Pass "S3" "DoD.ps1 has no empty catch blocks"
}

# Also check verify.ps1
$verifySrc = Get-Content -Raw $verifyScript
$emptyCatchVerify = ([regex]::Matches($verifySrc, 'catch\s*\{\s*\}')).Count
if($emptyCatchVerify -gt 0){
    Gap "S3" "verify.ps1 has $emptyCatchVerify empty catch{} blocks — errors are silently swallowed"
}

# Also check NtpDrift.ps1
$ntpSrc = Get-Content -Raw $ntpScript
if($ntpSrc -match "SilentlyContinue"){
    Gap "S3" "NtpDrift.ps1 uses ErrorActionPreference='SilentlyContinue' — all errors suppressed"
}

# =====================================================================
# S4: Empty/malformed CSV must exit non-zero
# =====================================================================
# Empty file
$emptyCsv = Join-Path $tmpDir 'empty.csv'
"" | Set-Content -Encoding UTF8 $emptyCsv
$r = Run-Script $merkleScript @("-CsvPath", $emptyCsv)
if($r.ExitCode -ne 0){ Pass "S4a" "Merkle.ps1 exits non-zero on empty CSV (exit $($r.ExitCode))" }
else { Fail "S4a" "Merkle.ps1 exits 0 on empty CSV — silent failure" }

# CSV with wrong columns
$badCsv = Join-Path $tmpDir 'bad.csv'
@('"Col1","Col2"','"val1","val2"') | Set-Content -Encoding UTF8 $badCsv
$r = Run-Script $merkleScript @("-CsvPath", $badCsv)
if($r.ExitCode -ne 0){ Pass "S4b" "Merkle.ps1 exits non-zero on malformed CSV (exit $($r.ExitCode))" }
else { Fail "S4b" "Merkle.ps1 exits 0 on malformed CSV — silent failure" }

# Cleanup
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

if($fail){ Write-Error "CRITERION 4 (NO SILENT FAILURES): FAILED"; exit 1 }
if($gap){ Write-Host "CRITERION 4 (NO SILENT FAILURES): KNOWN GAPS FOUND"; exit 2 }
Write-Host "CRITERION 4 (NO SILENT FAILURES): PASS" -ForegroundColor Green; exit 0
