$ErrorActionPreference='Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$goldenPath = Join-Path $repoRoot 'docs\golden-hashes.json'
$manifestCsv = Join-Path $repoRoot 'output\manifest.csv'
if(-not (Test-Path $goldenPath)){ Write-Error "FAIL: golden-hashes.json missing"; exit 3 }
pwsh -NoProfile -File (Join-Path $repoRoot 'src\run_demo.ps1') -Out (Join-Path $repoRoot 'output') | Out-Null
if(-not (Test-Path $manifestCsv)){ Write-Error "FAIL: manifest.csv missing"; exit 4 }
$rows = Import-Csv -Path $manifestCsv
if(-not $rows -or $rows.Count -eq 0){ Write-Error "FAIL: manifest.csv empty"; exit 5 }
$rel2sha=@{}; foreach($r in $rows){ $rel=($r.Rel -replace '\\','/'); if($rel){ $rel2sha[$rel]=$r.SHA256.ToLower() } }
$golden = Get-Content -Raw -Path $goldenPath | ConvertFrom-Json
$props = $golden.files.PSObject.Properties
$fail=$false
foreach($p in $props){
  $rel=($p.Name -replace '\\','/')
  $need=$p.Value.ToLower()
  if(-not $rel2sha.ContainsKey($rel)){ Write-Host "MISSING: $rel" -ForegroundColor Yellow; $fail=$true; continue }
  $got=$rel2sha[$rel]
  if($got -ne $need){ Write-Host "MISMATCH: $rel"; $fail=$true } else { Write-Host "OK: $rel" -ForegroundColor Green }
}
if($fail){ Write-Error "SELFTEST FAIL"; exit 10 } else { Write-Host "SELFTEST PASS"; exit 0 }
