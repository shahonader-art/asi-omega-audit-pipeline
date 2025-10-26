param([string]$File="output\DoD\DoD.json",[string]$KeyId="")
$ErrorActionPreference = 'Stop'
if(-not (Test-Path $File)){ Write-Error "Missing DoD file"; exit 2 }
if(-not $KeyId){ Write-Error "Provide -KeyId (last 8 hex)"; exit 3 }
$asc = "$File.asc"
& gpg --yes --local-user $KeyId --output $asc --armor --detach-sign $File
if($LASTEXITCODE -ne 0){ throw "GPG failed" } else { Write-Host "SIGNED: $asc" }
