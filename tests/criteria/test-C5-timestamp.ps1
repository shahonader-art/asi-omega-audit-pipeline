# Criterion 5: TIMESTAMP TRUSTWORTHINESS
# Timestamps must be verifiable against an external time source.
$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "C5-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$fail = $false; $gap = $false

function Pass($id,$m){ Write-Host "PASS [$id]: $m" -ForegroundColor Green }
function Fail($id,$m){ Write-Host "FAIL [$id]: $m" -ForegroundColor Red; $script:fail=$true }
function Gap($id,$m){ Write-Host "KNOWN-GAP [$id]: $m" -ForegroundColor Yellow; $script:gap=$true }

# =====================================================================
# TS1: DoD.json must contain a valid ISO 8601 timestamp
# =====================================================================
# Generate a fresh DoD
$outDir = Join-Path $tmpDir 'output'
$dodDir = Join-Path $outDir 'DoD'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
New-Item -ItemType Directory -Force -Path $dodDir | Out-Null

# We need a manifest for DoD to work
pwsh -NoProfile -File (Join-Path $repoRoot 'src\run_demo.ps1') -Out $outDir
pwsh -NoProfile -File (Join-Path $repoRoot 'tools\DoD.ps1') -Out $dodDir

$dodPath = Join-Path $dodDir 'DoD.json'
if(Test-Path $dodPath){
    $dod = Get-Content -Raw $dodPath | ConvertFrom-Json

    if($dod.generated){
        try {
            $ts = [datetime]::Parse($dod.generated)
            $now = Get-Date
            $drift = [math]::Abs(($now - $ts).TotalSeconds)
            if($drift -lt 60){
                Pass "TS1" "DoD.json has valid ISO 8601 timestamp: $($dod.generated) (within ${drift}s of now)"
            } else {
                Fail "TS1" "DoD.json timestamp is ${drift}s from current time — suspicious"
            }
        } catch {
            Fail "TS1" "DoD.json 'generated' field is not valid ISO 8601: $($dod.generated)"
        }
    } else {
        Fail "TS1" "DoD.json missing 'generated' field"
    }

    # =====================================================================
    # TS2: NTP drift must be measured (not magic value 9999)
    # =====================================================================
    if($null -ne $dod.ntp_drift_seconds){
        $drift = [double]$dod.ntp_drift_seconds
        if($drift -eq 9999){
            Gap "TS2" "NTP drift is 9999 (magic failure value) — measurement failed silently"
        } elseif([math]::Abs($drift) -lt 30){
            Pass "TS2" "NTP drift measured: $drift seconds"
        } else {
            Gap "TS2" "NTP drift is $drift seconds — unusually high, possibly unreliable"
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
    pwsh -NoProfile -File $otsScript -Target $merkleRootFile
    $otsFile = Join-Path $outDir 'ots_request.txt'

    if(Test-Path $otsFile){
        $otsContent = Get-Content -Raw $otsFile

        # The OTS stub hashes the merkle_root.txt FILE (not the content)
        $merkleFileHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $merkleRootFile).Hash.ToLower()
        if($otsContent -match $merkleFileHash){
            Pass "TS3" "OTS stub contains SHA-256 of merkle_root.txt file"
        } else {
            Fail "TS3" "OTS stub does not contain expected hash of merkle_root.txt"
        }

        # Check: does OTS actually submit to a timestamp service?
        $otsSrc = Get-Content -Raw $otsScript
        if($otsSrc -match 'Invoke-RestMethod|Invoke-WebRequest|curl|http'){
            Pass "TS3" "OTS script contacts external timestamp service"
        } else {
            Gap "TS3" "OTS script is a LOCAL stub only — does NOT contact any external timestamp service"
        }
    } else {
        Fail "TS3" "OTS request file not created"
    }
} else {
    Fail "TS3" "No merkle_root.txt to test OTS against"
}

# Cleanup
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

if($fail){ Write-Error "CRITERION 5 (TIMESTAMP TRUSTWORTHINESS): FAILED"; exit 1 }
if($gap){ Write-Host "CRITERION 5 (TIMESTAMP TRUSTWORTHINESS): KNOWN GAPS FOUND"; exit 2 }
Write-Host "CRITERION 5 (TIMESTAMP TRUSTWORTHINESS): PASS" -ForegroundColor Green; exit 0
