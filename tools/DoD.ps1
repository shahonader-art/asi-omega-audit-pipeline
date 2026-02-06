param([string]$Out = "output\DoD")

$ErrorActionPreference = 'Stop'

# Load shared crypto library
. (Join-Path $PSScriptRoot '..\lib\crypto.ps1')

New-Item -ItemType Directory -Force -Path $Out | Out-Null

$now = (Get-Date).ToString("o")
$tz  = (Get-TimeZone).Id
$culture = (Get-Culture).Name

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$manifestPath = Join-Path $repoRoot 'output\manifest.csv'

$data = @{
  schema_version = 2
  name      = "asi-omega-audit-pipeline"
  generated = $now
  timezone  = $tz
  culture   = $culture
  platform  = "PowerShell 7+"
  merkle_root = $null
  merkle_algorithm = "SHA-256 with RFC 6962 domain separation"
  ntp_drift_seconds = $null
  artefacts = @{
    manifest_csv = (Test-Path $manifestPath)
    golden_hashes = (Test-Path (Join-Path $repoRoot 'docs\golden-hashes.json'))
  }
  script_hashes = @{}
}

# ─────────────────────────────────────────────────────
# Script integrity: hash all pipeline scripts
# ─────────────────────────────────────────────────────
$pipelineScripts = @(
    'src\run_demo.ps1',
    'tools\Merkle.ps1',
    'tools\verify.ps1',
    'tools\DoD.ps1',
    'tools\NtpDrift.ps1',
    'tools\Sign-Audit.ps1',
    'tools\OTS-Stamp.ps1'
)

foreach($s in $pipelineScripts){
    $scriptPath = Join-Path $repoRoot $s
    if(Test-Path $scriptPath){
        $h = Get-Sha256FileHash $scriptPath
        $relPath = $s.Replace('\','/')
        $data.script_hashes[$relPath] = $h
    }
}

# ─────────────────────────────────────────────────────
# Compute Merkle root if manifest exists
# ─────────────────────────────────────────────────────
if(Test-Path $manifestPath){
    $merkleOut = pwsh -NoProfile -File (Join-Path $repoRoot 'tools\Merkle.ps1') -CsvPath $manifestPath 2>&1
    if($LASTEXITCODE -ne 0){
        Write-Host "WARNING: Merkle computation failed (exit $LASTEXITCODE): $merkleOut" -ForegroundColor Yellow
        $data.merkle_root = $null
    } else {
        $mrPath = Join-Path $repoRoot 'output\merkle_root.txt'
        if(Test-Path $mrPath){
            $data.merkle_root = (Get-Content -Raw -Path $mrPath).Trim()
        } else {
            Write-Host "WARNING: Merkle script ran but merkle_root.txt not found" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "WARNING: manifest.csv not found at $manifestPath — skipping Merkle" -ForegroundColor Yellow
}

# ─────────────────────────────────────────────────────
# NTP drift seconds (average)
# ─────────────────────────────────────────────────────
$ntpResult = pwsh -NoProfile -File (Join-Path $repoRoot 'tools\NtpDrift.ps1') 2>&1
# NtpDrift.ps1 may output Write-Host messages + the numeric value
# Extract the last numeric-looking token from the output
$ntpRaw = @($ntpResult) | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^-?\d+(\.\d+)?$' } | Select-Object -Last 1
if(-not $ntpRaw){
    # Fallback: try the very last line
    $ntpRaw = "$(@($ntpResult)[-1])".Trim()
}
try {
    $parsed = [double]$ntpRaw
    if($parsed -eq 9999){
        Write-Host "WARNING: NTP measurement unavailable (returned 9999)" -ForegroundColor Yellow
    }
    $data.ntp_drift_seconds = $parsed
} catch {
    Write-Host "WARNING: NTP returned non-numeric value: '$ntpRaw'" -ForegroundColor Yellow
    $data.ntp_drift_seconds = $null
}

$data | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -Path (Join-Path $Out 'DoD.json')

# Hash all top-level files for the report
$top = Get-ChildItem -Path $repoRoot -File
$lines = @()
foreach($f in $top){
  $h = (Get-Sha256FileHash $f.FullName).ToUpper()
  $lines += "$($f.Name),$($f.Length),$h"
}
$lines | Set-Content -Encoding UTF8 -Path (Join-Path $Out 'TopLevelHashes.csv')

Write-Host "DoD report emitted to $Out"
