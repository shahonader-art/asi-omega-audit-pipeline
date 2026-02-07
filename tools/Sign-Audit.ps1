param(
    [string]$AuditDir = "output",
    [string]$KeyId = "",
    [switch]$Auto
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

# ─────────────────────────────────────────────────────
# Check if GPG is available
# ─────────────────────────────────────────────────────
$gpgCmd = Get-Command gpg -ErrorAction SilentlyContinue
if(-not $gpgCmd){
    $gpgCmd = Get-Command gpg2 -ErrorAction SilentlyContinue
}
if(-not $gpgCmd){
    # Check common Windows install paths
    $gpgPaths = @(
        "$env:ProgramFiles\GnuPG\bin\gpg.exe",
        "${env:ProgramFiles(x86)}\GnuPG\bin\gpg.exe",
        "$env:LOCALAPPDATA\Programs\GnuPG\bin\gpg.exe"
    )
    foreach($p in $gpgPaths){
        if(Test-Path $p){ $gpgCmd = $p; break }
    }
}

if(-not $gpgCmd){
    Write-Host ""
    Write-Host "  GPG er ikke installert." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  For aa signere auditen trenger du GPG (Gpg4win paa Windows):" -ForegroundColor White
    Write-Host "    https://gpg4win.org/download.html" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Etter installasjon, lag en noekkel:" -ForegroundColor White
    Write-Host "    gpg --full-generate-key" -ForegroundColor Gray
    Write-Host ""
    exit 10
}

$gpgExe = if($gpgCmd -is [string]){ $gpgCmd } else { $gpgCmd.Source }

# ─────────────────────────────────────────────────────
# Find or select GPG key
# ─────────────────────────────────────────────────────
if(-not $KeyId){
    # List available secret keys
    $keys = & $gpgExe --list-secret-keys --keyid-format short 2>&1
    $keyIds = @()
    foreach($line in $keys){
        if($line -match 'sec\s+\w+/([0-9A-Fa-f]{8,16})'){
            $keyIds += $Matches[1]
        }
    }

    if($keyIds.Count -eq 0){
        Write-Host ""
        Write-Host "  Ingen GPG-noekler funnet." -ForegroundColor Yellow
        Write-Host "  Lag en noekkel foerst:" -ForegroundColor White
        Write-Host "    gpg --full-generate-key" -ForegroundColor Gray
        Write-Host ""
        exit 11
    }

    if($keyIds.Count -eq 1 -or $Auto){
        $KeyId = $keyIds[0]
        Write-Host "  Bruker GPG-noekkel: $KeyId" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "  Tilgjengelige GPG-noekler:" -ForegroundColor Cyan
        for($i=0; $i -lt $keyIds.Count; $i++){
            Write-Host "    [$i] $($keyIds[$i])" -ForegroundColor White
        }
        Write-Host ""
        Write-Host "  Kjoer med -KeyId <id> for aa velge, f.eks:" -ForegroundColor White
        Write-Host "    pwsh tools\Sign-Audit.ps1 -KeyId $($keyIds[0])" -ForegroundColor Gray
        exit 12
    }
}

# ─────────────────────────────────────────────────────
# Sign all critical files
# ─────────────────────────────────────────────────────
$filesToSign = @(
    (Join-Path $AuditDir 'manifest.csv'),
    (Join-Path $AuditDir 'merkle_root.txt'),
    (Join-Path $AuditDir 'DoD\DoD.json')
)

$signed = @()
$failed = @()

foreach($f in $filesToSign){
    if(-not (Test-Path $f)){
        Write-Host "  Hopper over (finnes ikke): $f" -ForegroundColor Yellow
        continue
    }

    $asc = "$f.asc"
    Write-Host "  Signerer: $f" -ForegroundColor White

    & $gpgExe --yes --local-user $KeyId --output $asc --armor --detach-sign $f 2>&1
    if($LASTEXITCODE -eq 0){
        Write-Host "    -> $asc" -ForegroundColor Green
        $signed += $f
    } else {
        Write-Host "    FEILET" -ForegroundColor Red
        $failed += $f
    }
}

# ─────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────
Write-Host ""
if($signed.Count -gt 0){
    Write-Host "  ========================================" -ForegroundColor Green
    Write-Host "  SIGNERING FULLFORT" -ForegroundColor Green
    Write-Host "  ========================================" -ForegroundColor Green
    Write-Host "  Signert $($signed.Count) filer med noekkel $KeyId" -ForegroundColor White
    Write-Host ""
    Write-Host "  Verifiser signaturer med:" -ForegroundColor Yellow
    foreach($f in $signed){
        Write-Host "    gpg --verify $f.asc $f" -ForegroundColor Gray
    }
    Write-Host ""
}

if($failed.Count -gt 0){
    Write-Host "  $($failed.Count) filer feilet signering" -ForegroundColor Red
    exit 1
}

exit 0
