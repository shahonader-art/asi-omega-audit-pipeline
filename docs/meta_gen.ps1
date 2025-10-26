@{
  name     = "asi-omega-audit-pipeline"
  created  = (Get-Date).ToString("o")
  platform = "PowerShell 7+"
  author   = "Shaho Nader"
} | ConvertTo-Json | Set-Content -Encoding UTF8 -Path (Join-Path $PSScriptRoot 'meta.json')

Write-Host "meta.json generated"
