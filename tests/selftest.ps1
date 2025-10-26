$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$goldenPath = Join-Path $repoRoot 'docs\golden-hashes.json'
if(-not (Test-Path $goldenPath)){ Write-Error "FAIL: golden-hashes.json missing"; exit 3 }

# Run demo to (re)generate manifest
$Out = Join-Path $repoRoot 'output'
pwsh -NoProfile -File (Join-Path $repoRoot 'src\run_demo.ps1') -Out $Out | Write-Host

$mf = Join-Path $Out 'manifest.csv'
if(-not (Test-Path $mf)){ Write-Error "FAIL: manifest.csv missing"; exit 4 }

# Load manifest into map Rel->SHA256
$lines = Get-Content -Path $mf -Encoding UTF8
# Drop header line, parse CSV
$parsed = @()
$hdr = $true
foreach($ln in $lines){
  if($hdr){ $hdr=$false; continue }
  $cols = $ln -split ','
  if($cols.Count -lt 4){ continue }
  # CSV fields may have quotes; trim them
  $rel = $cols[1].Trim('"')
  $sha = $cols[2].Trim('"')
  $parsed += ,@($rel,$sha)
}

$rel2sha = @{}
foreach($row in $parsed){
  $rel2sha[$row[0]] = $row[1]
}

# Load golden hashes
$golden = Get-Content -Raw -Path $goldenPath | ConvertFrom-Json

# Compare
$fail = $false
foreach($kv in $golden.files.GetEnumerator()){
  $rel = $kv.Key
  $need = $kv.Value.ToUpperInvariant()
  if(-not $rel2sha.ContainsKey($rel)){
    Write-Host "MISSING: $rel" -ForegroundColor Yellow
    $fail = $true
    continue
  }
  $got = $rel2sha[$rel].ToUpperInvariant()
  if($got -ne $need){
    Write-Host "HASH MISMATCH: $rel`n  expected: $need`n  got     : $got" -ForegroundColor Red
    $fail = $true
  } else {
    Write-Host "OK: $rel" -ForegroundColor Green
  }
}

if($fail){ Write-Error "SELFTEST FAIL"; exit 10 } else { Write-Host "SELFTEST PASS"; exit 0 }
