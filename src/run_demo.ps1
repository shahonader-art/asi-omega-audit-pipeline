param(
  [string]$Out = "output",
  [switch]$DryRun
)

# Ensure output dir
New-Item -ItemType Directory -Force -Path $Out | Out-Null

# Target: only sample artifacts for deterministic test
$targetRoot = Join-Path $PSScriptRoot "..\sample"

if(-not (Test-Path $targetRoot)){
  Write-Error "Sample folder not found: $targetRoot"
  exit 2
}

# Sort explicitly by relative path for deterministic manifest ordering across platforms
$files = Get-ChildItem -Path $targetRoot -Recurse -File | Sort-Object { $_.FullName.Replace('\','/') }

$manifest = @()
foreach($f in $files){
  $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash
  $manifest += [pscustomobject]@{
    Path   = $f.FullName
    Rel    = (Resolve-Path -LiteralPath $f.FullName).Path.Replace((Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path,'').TrimStart('\','/').Replace('\','/')
    SHA256 = $h
    Size   = $f.Length
  }
}

# Write manifest only if not DryRun
$mf = Join-Path $Out "manifest.csv"
if($DryRun){
  Write-Host "DRYRUN: Would write $mf with $($manifest.Count) rows"
}else{
  $manifest | ConvertTo-Csv -NoTypeInformation | Set-Content -Encoding UTF8 -Path $mf
  Write-Host "SELFTEST: manifest written to $mf"
}
