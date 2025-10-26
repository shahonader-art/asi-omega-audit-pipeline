param([string]$Path)
$j = Get-Content $Path -Raw | ConvertFrom-Json
if(-not (Test-Path $j.manifest)){ Write-Error 'Manifest mangler'; exit 1 }
$ok = (Get-FileHash $j.manifest -Algorithm SHA256).Hash -eq $j.manifest_hash
if($ok){ Write-Host "VERIFIED: " -ForegroundColor Green } else { Write-Host "FAILED" -ForegroundColor Red }
