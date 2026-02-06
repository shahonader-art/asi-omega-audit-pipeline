# ASI-Omega Audit Pipeline — Installasjon
# Installer med en kommando:
#   irm https://raw.githubusercontent.com/shahonader-art/asi-omega-audit-pipeline/main/install.ps1 | iex
# Eller kjoer lokalt:
#   pwsh install.ps1

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "    ASI-Omega Audit Pipeline — Installasjon" -ForegroundColor Cyan
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host ""

# ─────────────────────────────────────────────────────
# 1. Sjekk PowerShell-versjon
# ─────────────────────────────────────────────────────
if($PSVersionTable.PSVersion.Major -lt 7){
    Write-Host "  Du trenger PowerShell 7+. Du har versjon $($PSVersionTable.PSVersion)" -ForegroundColor Red
    Write-Host "  Last ned: https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
Write-Host "  [OK] PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Green

# ─────────────────────────────────────────────────────
# 2. Finn eller velg installasjonsmappe
# ─────────────────────────────────────────────────────
$defaultDir = Join-Path $env:LOCALAPPDATA "ASI-Omega"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Hvis vi kjoerer fra prosjektmappen, bruk den
if(Test-Path (Join-Path $scriptDir 'audit.ps1')){
    $installDir = $scriptDir
    Write-Host "  [OK] Bruker eksisterende mappe: $installDir" -ForegroundColor Green
} else {
    $installDir = $defaultDir
    Write-Host "  Installerer til: $installDir" -ForegroundColor White

    if(-not (Test-Path $installDir)){
        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    }

    # Klon prosjektet
    $gitAvailable = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
    if($gitAvailable){
        Write-Host "  Laster ned fra GitHub..." -ForegroundColor White
        git clone https://github.com/shahonader-art/asi-omega-audit-pipeline.git $installDir 2>&1 | Out-Null
        if($LASTEXITCODE -ne 0){
            Write-Host "  Kloning feilet. Sjekk internettforbindelsen." -ForegroundColor Red
            exit 2
        }
    } else {
        Write-Host "  git ikke funnet. Laster ned som ZIP..." -ForegroundColor Yellow
        $zipUrl = "https://github.com/shahonader-art/asi-omega-audit-pipeline/archive/refs/heads/main.zip"
        $zipPath = Join-Path $env:TEMP "asi-omega.zip"
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $env:TEMP -Force
        $extracted = Join-Path $env:TEMP "asi-omega-audit-pipeline-main"
        Copy-Item -Recurse -Force "$extracted\*" $installDir
        Remove-Item -Force $zipPath -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $extracted -ErrorAction SilentlyContinue
    }
    Write-Host "  [OK] Nedlasting fullfoert" -ForegroundColor Green
}

# ─────────────────────────────────────────────────────
# 3. Lag snarvei paa skrivebordet
# ─────────────────────────────────────────────────────
try {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktop "ASI-Omega Audit.lnk"

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "pwsh.exe"
    $shortcut.Arguments = "-NoProfile -File `"$installDir\audit-gui.ps1`""
    $shortcut.WorkingDirectory = $installDir
    $shortcut.Description = "ASI-Omega Audit Pipeline — Kryptografisk filintegritet"
    $shortcut.Save()

    Write-Host "  [OK] Snarvei opprettet paa skrivebordet" -ForegroundColor Green
} catch {
    Write-Host "  [!] Kunne ikke lage snarvei: $_" -ForegroundColor Yellow
}

# ─────────────────────────────────────────────────────
# 4. Lag kommandolinje-snarvei (audit-kommando)
# ─────────────────────────────────────────────────────
try {
    $scriptsDir = Join-Path $env:LOCALAPPDATA "Microsoft\PowerShell\Scripts"
    if(-not (Test-Path $scriptsDir)){ New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null }

    $wrapperContent = @"
# ASI-Omega Audit Pipeline — global kommando
param([Parameter(ValueFromRemainingArguments=`$true)]`$args)
pwsh -NoProfile -File "$installDir\audit.ps1" @args
"@
    $wrapperPath = Join-Path $scriptsDir "audit.ps1"
    $wrapperContent | Set-Content -Encoding UTF8 -Path $wrapperPath

    # Sjekk om mappen er i PATH
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if($currentPath -notlike "*$scriptsDir*"){
        [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$scriptsDir", "User")
        Write-Host "  [OK] Lagt til i PATH (start nytt terminalvindu)" -ForegroundColor Green
    }
} catch {
    Write-Host "  [!] Kunne ikke sette opp global kommando: $_" -ForegroundColor Yellow
}

# ─────────────────────────────────────────────────────
# 5. Sjekk valgfrie avhengigheter
# ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "  Valgfrie tillegg:" -ForegroundColor Cyan

$gpg = Get-Command gpg -ErrorAction SilentlyContinue
if($gpg){
    Write-Host "  [OK] GPG installert — signering tilgjengelig" -ForegroundColor Green
} else {
    Write-Host "  [ ] GPG ikke installert — last ned gpg4win.org for signering" -ForegroundColor Gray
}

# Test internettilgang for OTS
try {
    $null = Invoke-WebRequest -Uri "https://a.pool.opentimestamps.org" -TimeoutSec 5 -ErrorAction Stop
    Write-Host "  [OK] OpenTimestamps tilgjengelig — uavhengig tidsstempling klar" -ForegroundColor Green
} catch {
    Write-Host "  [ ] OpenTimestamps utilgjengelig — krever internett" -ForegroundColor Gray
}

# ─────────────────────────────────────────────────────
# Ferdig
# ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ================================================" -ForegroundColor Green
Write-Host "    INSTALLASJON FULLFORT" -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Kom i gang:" -ForegroundColor Cyan
Write-Host ""
Write-Host "    Grafisk:     Dobbeltklikk 'ASI-Omega Audit' paa skrivebordet" -ForegroundColor White
Write-Host "    Terminal:    pwsh audit.ps1" -ForegroundColor White
Write-Host "    Verifiser:   pwsh audit.ps1 -Verify" -ForegroundColor White
Write-Host "    Full audit:  pwsh audit.ps1 -Full" -ForegroundColor White
Write-Host "    Hjelp:       pwsh audit.ps1 -Help" -ForegroundColor White
Write-Host ""
Write-Host "  Installert i: $installDir" -ForegroundColor Gray
Write-Host ""
Write-Host "  Dokumentasjon: https://github.com/shahonader-art/asi-omega-audit-pipeline" -ForegroundColor Gray
Write-Host ""
