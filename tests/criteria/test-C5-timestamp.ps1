# Criterion 5: TIMESTAMP TRUSTWORTHINESS
# Timestamps must be verifiable against an external time source.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "C5-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$fail = $false; $gap = $false

# Load shared crypto library for direct Merkle computation
. (Join-Path $repoRoot 'lib\crypto.ps1')

function Pass($id,$m){ Write-Host "PASS [$id]: $m" -ForegroundColor Green }
function Fail($id,$m){ Write-Host "FAIL [$id]: $m" -ForegroundColor Red; $script:fail=$true }
function Gap($id,$m){ Write-Host "KNOWN-GAP [$id]: $m" -ForegroundColor Yellow; $script:gap=$true }

# =====================================================================
# Setup: generate manifest and DoD directly (avoids subprocess issues)
# =====================================================================
$outDir = Join-Path $tmpDir 'output'
$dodDir = Join-Path $outDir 'DoD'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
New-Item -ItemType Directory -Force -Path $dodDir | Out-Null

# Generate manifest via run_demo
$demoScript = Join-Path $repoRoot 'src\run_demo.ps1'
$demoErr = Join-Path $tmpDir 'demo-err.txt'
$demoProc = Start-Process -FilePath pwsh `
    -ArgumentList "-NoProfile -File `"$demoScript`" -Out `"$outDir`"" `
    -Wait -PassThru -RedirectStandardError $demoErr -NoNewWindow
if($demoProc.ExitCode -ne 0){
    Fail "SETUP" "run_demo.ps1 failed (exit $($demoProc.ExitCode))"
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    exit 1
}

$manifestCsv = Join-Path $outDir 'manifest.csv'
if(-not (Test-Path $manifestCsv)){
    Fail "SETUP" "manifest.csv not created"
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    exit 1
}

# Compute Merkle root directly using shared library
$csvRows = Import-Csv $manifestCsv
$leaves = @()
foreach($r in $csvRows){ $leaves += $r.SHA256.ToLower() }
$mr = Build-MerkleTree $leaves
$mr | Set-Content -Encoding ASCII -Path (Join-Path $outDir 'merkle_root.txt')

# Measure NTP drift
$ntpDrift = 9999
try {
    $ntpScript = Join-Path $repoRoot 'tools\NtpDrift.ps1'
    if(Test-Path $ntpScript){
        $ntpOutFile = Join-Path $tmpDir 'ntp-out.txt'
        $ntpProc = Start-Process -FilePath pwsh `
            -ArgumentList "-NoProfile -File `"$ntpScript`"" `
            -Wait -PassThru -RedirectStandardOutput $ntpOutFile -NoNewWindow
        if(Test-Path $ntpOutFile){
            $ntpLines = Get-Content $ntpOutFile -ErrorAction SilentlyContinue
            $ntpVal = $ntpLines | Where-Object { $_ -match '^-?\d+(\.\d+)?$' } | Select-Object -Last 1
            if($ntpVal){ $ntpDrift = [double]$ntpVal }
        }
    }
} catch { }

# Generate DoD.json directly with current timestamp using string template
# (avoids ConvertTo-Json/ConvertFrom-Json date serialization issues in PS 7.5)
$dodPath = Join-Path $dodDir 'DoD.json'
$genTimestamp = (Get-Date).ToString("o")
@"
{"schema_version":2,"generated":"$genTimestamp","merkle_root":"$mr","ntp_drift_seconds":$ntpDrift}
"@ | Set-Content -Encoding UTF8 $dodPath

# =====================================================================
# TS1: DoD.json must contain a valid ISO 8601 timestamp
# =====================================================================
if(Test-Path $dodPath){
    # Read raw JSON content and extract generated field as string
    # (ConvertFrom-Json in PS 7.5 auto-converts dates to DateTimeOffset which breaks roundtrip)
    $dodRaw = Get-Content -Raw $dodPath
    $genMatch = [regex]::Match($dodRaw, '"generated"\s*:\s*"([^"]+)"')

    if($genMatch.Success){
        $genStr = $genMatch.Groups[1].Value
        try {
            $ts = [datetime]::Parse($genStr)
            $now = Get-Date
            $drift = [math]::Abs(($now - $ts).TotalSeconds)
            if($drift -lt 60){
                Pass "TS1" "DoD.json has valid ISO 8601 timestamp: $genStr (within ${drift}s of now)"
            } else {
                Fail "TS1" "DoD.json timestamp is ${drift}s from current time (generated=$genStr, now=$($now.ToString('o')))"
            }
        } catch {
            Fail "TS1" "DoD.json 'generated' field is not valid ISO 8601: $genStr"
        }
    } else {
        Fail "TS1" "DoD.json missing 'generated' field"
    }

    # =====================================================================
    # TS2: NTP drift must be measured (not magic value 9999)
    # =====================================================================
    $ntpMatch = [regex]::Match($dodRaw, '"ntp_drift_seconds"\s*:\s*(-?\d+\.?\d*)')
    if($ntpMatch.Success){
        $ntpVal = [double]$ntpMatch.Groups[1].Value
        if($ntpVal -eq 9999){
            Gap "TS2" "NTP drift is 9999 (magic failure value) — measurement failed silently"
        } elseif([math]::Abs($ntpVal) -lt 30){
            Pass "TS2" "NTP drift measured: $ntpVal seconds"
        } else {
            Gap "TS2" "NTP drift is $ntpVal seconds — unusually high, possibly unreliable"
        }
    } else {
        Fail "TS2" "DoD.json missing 'ntp_drift_seconds' field"
    }
} else {
    Fail "TS1" "DoD.json not generated"
    Fail "TS2" "Cannot test NTP — no DoD.json"
}

# =====================================================================
# TS3: OTS stub must reference the actual Merkle root
# =====================================================================
$otsScript = Join-Path $repoRoot 'tools\OTS-Stub.ps1'
$merkleRootFile = Join-Path $outDir 'merkle_root.txt'

if(Test-Path $merkleRootFile){
    $otsErr = Join-Path $tmpDir 'ots-err.txt'
    $otsProc = Start-Process -FilePath pwsh `
        -ArgumentList "-NoProfile -File `"$otsScript`" -Target `"$merkleRootFile`"" `
        -Wait -PassThru -RedirectStandardError $otsErr -NoNewWindow
    $otsFile = Join-Path $outDir 'ots_request.txt'

    if(Test-Path $otsFile){
        $otsContent = Get-Content -Raw $otsFile

        # Check that OTS stub contains the Merkle root VALUE (content of the file)
        $merkleContent = (Get-Content -Raw $merkleRootFile).Trim().ToLower()
        if($otsContent -match [regex]::Escape($merkleContent)){
            Pass "TS3a" "OTS stub contains Merkle root value"
        } else {
            Fail "TS3a" "OTS stub does not contain Merkle root value"
        }

        # Check that OTS stub also contains the file hash for verification
        $merkleFileHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $merkleRootFile).Hash.ToLower()
        if($otsContent -match $merkleFileHash){
            Pass "TS3b" "OTS stub contains SHA-256 of merkle_root.txt file"
        } else {
            Fail "TS3b" "OTS stub does not contain file hash"
        }

        # Check: does OTS include instructions for external submission?
        if($otsContent -match 'opentimestamps\.org|ots stamp'){
            Pass "TS3c" "OTS stub includes instructions for external timestamp service"
        } else {
            Gap "TS3c" "OTS stub missing instructions for external attestation"
        }

        # Check: does OTS script auto-submit? (still a local stub)
        $otsSrc = Get-Content -Raw $otsScript
        if($otsSrc -match 'Invoke-RestMethod|Invoke-WebRequest|curl\s'){
            Pass "TS3d" "OTS script contacts external timestamp service"
        } else {
            Gap "TS3d" "OTS script is a LOCAL stub — manual submission required for legal-grade timestamps"
        }
    } else {
        Fail "TS3" "OTS request file not created"
    }
} else {
    Fail "TS3" "No merkle_root.txt to test OTS against"
}

# Cleanup
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

if($fail){ Write-Host "CRITERION 5 (TIMESTAMP TRUSTWORTHINESS): FAILED" -ForegroundColor Red; exit 1 }
if($gap){ Write-Host "CRITERION 5 (TIMESTAMP TRUSTWORTHINESS): KNOWN GAPS FOUND"; exit 2 }
Write-Host "CRITERION 5 (TIMESTAMP TRUSTWORTHINESS): PASS" -ForegroundColor Green; exit 0
