# One-shot: run demo, test, DoD
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root
pwsh -NoProfile -File .\src\run_demo.ps1 -Out .\output
pwsh -NoProfile -File .\tests\selftest.ps1
pwsh -NoProfile -File .\tools\DoD.ps1 -Out .\output\DoD
Write-Host "BOOTSTRAP PASS"
