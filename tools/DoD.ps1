param([string]$Out = "output\DoD")

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$now = (Get-Date).ToString("o")
$tz  = (Get-TimeZone).Id
$culture = (Get-Culture).Name

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$manifestPath = Join-Path $repoRoot 'output\manifest.csv'

$data = @{
  name      = "asi-omega-audit-pipeline"
  generated = $now
  timezone  = $tz
  culture   = $culture
  platform  = "PowerShell 7+"
  merkle_root = $null
  ntp_drift_seconds = $null
  artefacts = @{
    manifest_csv = (Test-Path $manifestPath)
    golden_hashes = (Test-Path (Join-Path $repoRoot 'docs\golden-hashes.json'))
  }
}

# Compute Merkle root if manifest exists
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

# NTP drift seconds (average)
$ntpResult = pwsh -NoProfile -File (Join-Path $repoRoot 'tools\NtpDrift.ps1') 2>&1
$ntpVal = "$ntpResult".Trim()
try {
    $parsed = [double]$ntpVal
    if($parsed -eq 9999){
        Write-Host "WARNING: NTP measurement unavailable (returned 9999)" -ForegroundColor Yellow
    }
    $data.ntp_drift_seconds = $parsed
} catch {
    Write-Host "WARNING: NTP returned non-numeric value: '$ntpVal'" -ForegroundColor Yellow
    $data.ntp_drift_seconds = $null
}

$data | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -Path (Join-Path $Out 'DoD.json')

# Hash all top-level files for the report
$top = Get-ChildItem -Path $repoRoot -File
$lines = @()
foreach($f in $top){
  $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash
  $lines += "$($f.Name),$($f.Length),$h"
}
$lines | Set-Content -Encoding UTF8 -Path (Join-Path $Out 'TopLevelHashes.csv')

Write-Host "DoD report emitted to $Out"
