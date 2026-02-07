param([string]$CsvPath = "")

# ASI-Omega Merkle Tree Builder
# Reads manifest.csv and builds an RFC 6962 compliant Merkle tree.
# Output: merkle_root.txt in the same directory as the CSV.

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

# Load shared crypto library
. (Join-Path $PSScriptRoot '..\lib\crypto.ps1')

if(-not $CsvPath){ Write-Host "ERROR: CsvPath is required. Usage: pwsh Merkle.ps1 -CsvPath <path>" -ForegroundColor Red; exit 1 }
if(-not (Test-Path $CsvPath)){ Write-Host "ERROR: CSV not found: $CsvPath" -ForegroundColor Red; exit 2 }

$rows = Import-Csv -Path $CsvPath
if(-not $rows -or $rows.Count -eq 0){ Write-Host "ERROR: Empty CSV" -ForegroundColor Red; exit 3 }

$leaves = @()
foreach($r in $rows){
  if($r.Rel -and $r.SHA256){ $leaves += $r.SHA256.ToLower() }
}
if($leaves.Count -eq 0){ Write-Host "ERROR: No valid Rel/SHA256 columns found" -ForegroundColor Red; exit 4 }

$root = Build-MerkleTree $leaves

$rootPath = Join-Path (Split-Path -Parent $CsvPath) 'merkle_root.txt'
$root | Set-Content -Encoding ASCII -Path $rootPath
Write-Host "MERKLE_ROOT: $root"
