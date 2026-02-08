# ASI-Omega Audit Pipeline — Hurtigstart
# Kjoer fra hvor som helst:
#   pwsh C:\Users\Bruker\asi-omega-audit-pipeline\start.ps1
#
# Eller dobbeltklikk paa denne filen i Windows Utforsker.

$ErrorActionPreference = 'Stop'

# Finn prosjektmappen (der dette skriptet ligger)
$projectDir = $PSScriptRoot
if(-not $projectDir){ $projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

# Gaa inn i prosjektmappen
Set-Location $projectDir

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "  ASI-OMEGA AUDIT PIPELINE" -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Du er naa i prosjektmappen:" -ForegroundColor White
Write-Host "    $projectDir" -ForegroundColor Gray
Write-Host ""
Write-Host "  PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Gray
Write-Host ""
Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  Kommandoer du kan kjoere:" -ForegroundColor Yellow
Write-Host ""
Write-Host "    pwsh test.ps1              Kjoer alle tester" -ForegroundColor White
Write-Host "    pwsh test.ps1 -Only quick  Bare hurtigtest" -ForegroundColor White
Write-Host "    pwsh test.ps1 -Only merkle Bare Merkle-tester" -ForegroundColor White
Write-Host ""
Write-Host "    pwsh audit.ps1             Kjoer full audit" -ForegroundColor White
Write-Host "    pwsh audit.ps1 -Sign       Audit + GPG-signering" -ForegroundColor White
Write-Host "    pwsh audit.ps1 -Timestamp  Audit + OpenTimestamps" -ForegroundColor White
Write-Host ""
Write-Host "    pwsh tools\verify.ps1      Verifiser audit" -ForegroundColor White
Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
