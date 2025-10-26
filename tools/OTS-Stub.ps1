param([string]$Target="output\merkle_root.txt")
$ErrorActionPreference = 'Stop'
if(-not (Test-Path $Target)){ Write-Error "Missing target"; exit 2 }
$hex = (Get-FileHash -Algorithm SHA256 -LiteralPath $Target).Hash.ToLower()
$req = "# OpenTimestamps request (hex of file):`n$hex"
$dir = Split-Path -Parent $Target
$out = Join-Path $dir 'ots_request.txt'
$req | Set-Content -Encoding utf8 -Path $out
Write-Host "OTS stub created: $out"
