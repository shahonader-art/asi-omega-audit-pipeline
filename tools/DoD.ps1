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
try{
  if(Test-Path $manifestPath){
    pwsh -NoProfile -File (Join-Path $repoRoot 'tools\Merkle.ps1') -CsvPath $manifestPath | Out-Null
    $mrPath = Join-Path $repoRoot 'output\merkle_root.txt'
    if(Test-Path $mrPath){
      $data.merkle_root = (Get-Content -Raw -Path $mrPath).Trim()
    }
  }
}catch{}

# NTP drift seconds (average)
try{
  $data.ntp_drift_seconds = (pwsh -NoProfile -File (Join-Path $repoRoot 'tools\NtpDrift.ps1'))
}catch{
  $data.ntp_drift_seconds = 9999
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
