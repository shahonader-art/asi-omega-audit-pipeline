param(
    [string]$Out = "output\DoD",
    [string]$Manifest = ""
)

$ErrorActionPreference = 'Stop'
# Prevent PS 7.4+ from promoting native command non-zero exits to terminating errors
$PSNativeCommandUseErrorActionPreference = $false

# Load shared crypto library
. (Join-Path $PSScriptRoot '..\lib\crypto.ps1')

New-Item -ItemType Directory -Force -Path $Out | Out-Null

$now = (Get-Date).ToString("o")
$tz  = (Get-TimeZone).Id
$culture = (Get-Culture).Name

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$manifestPath = if($Manifest -and (Test-Path $Manifest)){ Resolve-Path $Manifest } else { Join-Path $repoRoot 'output\manifest.csv' }

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
    # Compute Merkle root using shared library directly (no subprocess)
    $csvRows = Import-Csv -Path $manifestPath
    if($csvRows -and $csvRows.Count -gt 0){
        $leafHashes = @()
        foreach($r in $csvRows){
            if($r.Rel -and $r.SHA256){ $leafHashes += $r.SHA256.ToLower() }
        }
        if($leafHashes.Count -gt 0){
            $data.merkle_root = Build-MerkleTree $leafHashes
            # Also write merkle_root.txt next to manifest
            $mrDir = Split-Path -Parent (Resolve-Path $manifestPath)
            $data.merkle_root | Set-Content -Encoding ASCII -Path (Join-Path $mrDir 'merkle_root.txt')
        } else {
            Write-Host "WARNING: manifest.csv has no valid Rel/SHA256 rows" -ForegroundColor Yellow
        }
    } else {
        Write-Host "WARNING: manifest.csv is empty" -ForegroundColor Yellow
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

# Build JSON manually to avoid ConvertTo-Json serialization issues on PS 7.5+
$mrVal = if($data.merkle_root){ "`"$($data.merkle_root)`"" } else { "null" }
$ntpVal = if($null -ne $data.ntp_drift_seconds){ "$($data.ntp_drift_seconds)" } else { "null" }
$mcsvVal = if($data.artefacts.manifest_csv){ "true" } else { "false" }
$ghVal = if($data.artefacts.golden_hashes){ "true" } else { "false" }

# Build script_hashes object
$shParts = @()
foreach($k in ($data.script_hashes.Keys | Sort-Object)){
    $v = $data.script_hashes[$k]
    $shParts += "    `"$k`": `"$v`""
}
$shJson = if($shParts.Count -gt 0){ "{`n" + ($shParts -join ",`n") + "`n  }" } else { "{}" }

@"
{
  "schema_version": $($data.schema_version),
  "name": "$($data.name)",
  "generated": "$($data.generated)",
  "timezone": "$($data.timezone)",
  "culture": "$($data.culture)",
  "platform": "$($data.platform)",
  "merkle_root": $mrVal,
  "merkle_algorithm": "$($data.merkle_algorithm)",
  "ntp_drift_seconds": $ntpVal,
  "artefacts": {
    "manifest_csv": $mcsvVal,
    "golden_hashes": $ghVal
  },
  "script_hashes": $shJson
}
"@ | Set-Content -Encoding UTF8 -Path (Join-Path $Out 'DoD.json')

# Hash all top-level files for the report
$top = Get-ChildItem -Path $repoRoot -File
$lines = @()
foreach($f in $top){
  $h = (Get-Sha256FileHash $f.FullName).ToUpper()
  $lines += "$($f.Name),$($f.Length),$h"
}
$lines | Set-Content -Encoding UTF8 -Path (Join-Path $Out 'TopLevelHashes.csv')

Write-Host "DoD report emitted to $Out"
