param([Parameter(Mandatory)][string]$CsvPath)

# ASI-Omega Merkle Tree Builder
# Reads manifest.csv and builds an RFC 6962 compliant Merkle tree.
# Output: merkle_root.txt in the same directory as the CSV.

$ErrorActionPreference = 'Stop'

# Load shared crypto library
. (Join-Path $PSScriptRoot '..\lib\crypto.ps1')

if(-not (Test-Path $CsvPath)){ Write-Error "CSV not found: $CsvPath"; exit 2 }

$rows = Import-Csv -Path $CsvPath
if(-not $rows -or $rows.Count -eq 0){ Write-Error "Empty CSV"; exit 3 }

$leaves = @()
foreach($r in $rows){
  if($r.Rel -and $r.SHA256){ $leaves += $r.SHA256.ToLower() }
}
if($leaves.Count -eq 0){ Write-Error "No leaves extracted"; exit 4 }

$root = Build-MerkleTree $leaves

$rootPath = Join-Path (Split-Path -Parent $CsvPath) 'merkle_root.txt'
$root | Set-Content -Encoding ASCII -Path $rootPath
Write-Host "MERKLE_ROOT: $root"
