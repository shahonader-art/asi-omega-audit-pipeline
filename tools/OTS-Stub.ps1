param([string]$Target="output\merkle_root.txt")
$ErrorActionPreference = 'Stop'
if(-not (Test-Path $Target)){ Write-Error "Missing target: $Target"; exit 2 }

$merkleContent = (Get-Content -Raw -Path $Target).Trim().ToLower()
$fileHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Target).Hash.ToLower()

$dir = Split-Path -Parent $Target
$out = Join-Path $dir 'ots_request.txt'

# Include both the Merkle root value AND the file hash for anchoring
$req = @"
# OpenTimestamps Attestation Request
# Generated: $((Get-Date).ToString("o"))
# Pipeline:  asi-omega-audit-pipeline
#
# Merkle root (from file content):
$merkleContent
#
# SHA-256 of merkle_root.txt file:
$fileHash
#
# To complete attestation, submit the Merkle root to:
#   https://opentimestamps.org  (browser)
#   ots stamp merkle_root.txt   (CLI: https://github.com/opentimestamps/opentimestamps-client)
"@

$req | Set-Content -Encoding utf8 -Path $out
Write-Host "OTS request created: $out"
Write-Host "  Merkle root: $merkleContent"
Write-Host "  File hash:   $fileHash"
Write-Host ""
Write-Host "NOTE: This is a LOCAL stub. For legal-grade timestamps, submit to an OTS service." -ForegroundColor Yellow
