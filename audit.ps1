param(
    [string]$Path = "",
    [switch]$Verify,
    [switch]$Sign,
    [switch]$Timestamp,
    [switch]$Full,
    [string]$GpgKey = "",
    [switch]$Help
)

# ASI-Omega Audit Pipeline — One-command interface
# Usage:
#   pwsh audit.ps1                     → Audit the sample/ folder
#   pwsh audit.ps1 -Path C:\MinMappe   → Audit any folder
#   pwsh audit.ps1 -Verify             → Verify a previous audit

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# ─────────────────────────────────────────────────────
# Help
# ─────────────────────────────────────────────────────
if($Help){
    Write-Host ""
    Write-Host "  ASI-Omega Audit Pipeline" -ForegroundColor Cyan
    Write-Host "  ========================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Lager kryptografisk bevis for at filene dine ikke er endret." -ForegroundColor White
    Write-Host ""
    Write-Host "  BRUK:" -ForegroundColor Yellow
    Write-Host "    pwsh audit.ps1                     Auditer sample/-mappen"
    Write-Host "    pwsh audit.ps1 -Path C:\MinMappe   Auditer en vilkaarlig mappe"
    Write-Host "    pwsh audit.ps1 -Verify             Verifiser forrige audit"
    Write-Host "    pwsh audit.ps1 -Sign               Auditer + GPG-signer"
    Write-Host "    pwsh audit.ps1 -Timestamp          Auditer + OpenTimestamps"
    Write-Host "    pwsh audit.ps1 -Full               Auditer + signer + tidsstempel"
    Write-Host ""
    Write-Host "  UTDATA:" -ForegroundColor Yellow
    Write-Host "    output/rapport.txt         Lesbar rapport for mennesker"
    Write-Host "    output/manifest.csv        Fil-fingeravtrykk"
    Write-Host "    output/merkle_root.txt     Kombinert rot"
    Write-Host "    output/DoD/DoD.json        Maskinlesbar rapport"
    Write-Host "    output/*.asc               GPG-signaturer (med -Sign)"
    Write-Host "    output/ots_receipt.txt     OTS-kvittering (med -Timestamp)"
    Write-Host ""
    Write-Host "  EKSEMPLER:" -ForegroundColor Yellow
    Write-Host '    pwsh audit.ps1 -Path "C:\Prosjekt\leveranse"'
    Write-Host '    pwsh audit.ps1 -Full -GpgKey AABBCCDD'
    Write-Host '    pwsh audit.ps1 -Verify'
    Write-Host ""
    exit 0
}

# ─────────────────────────────────────────────────────
# Verify mode
# ─────────────────────────────────────────────────────
if($Verify){
    Write-Host ""
    Write-Host "  VERIFISERER AUDIT" -ForegroundColor Cyan
    Write-Host "  =================" -ForegroundColor Cyan
    Write-Host ""

    $dodJson = Join-Path $root 'output\DoD\DoD.json'
    $manifest = Join-Path $root 'output\manifest.csv'
    $merkleRoot = Join-Path $root 'output\merkle_root.txt'

    $missing = @()
    if(-not (Test-Path $dodJson)){ $missing += "DoD.json" }
    if(-not (Test-Path $manifest)){ $missing += "manifest.csv" }
    if(-not (Test-Path $merkleRoot)){ $missing += "merkle_root.txt" }

    if($missing.Count -gt 0){
        Write-Host "  Mangler filer: $($missing -join ', ')" -ForegroundColor Red
        Write-Host "  Kjoer 'pwsh audit.ps1' foerst for aa lage en audit." -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }

    pwsh -NoProfile -File (Join-Path $root 'tools\verify.ps1') -DoD $dodJson -Manifest $manifest -MerkleRoot $merkleRoot

    Write-Host ""
    if($LASTEXITCODE -eq 0){
        Write-Host "  RESULTAT: Alle filer er uendret. Integriteten er bekreftet." -ForegroundColor Green
    } else {
        Write-Host "  RESULTAT: FEIL FUNNET. Filer kan ha blitt endret." -ForegroundColor Red
    }
    Write-Host ""
    exit $LASTEXITCODE
}

# ─────────────────────────────────────────────────────
# Audit mode (default)
# ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ASI-OMEGA AUDIT PIPELINE" -ForegroundColor Cyan
Write-Host "  ========================" -ForegroundColor Cyan
Write-Host ""

$outDir = Join-Path $root 'output'
$dodDir = Join-Path $outDir 'DoD'

# Step 1: Generate manifest
Write-Host "  Steg 1/4: Scanner filer og beregner fingeravtrykk..." -ForegroundColor White
if($Path -and $Path -ne ""){
    # Custom path: copy files to sample/ temporarily, or use directly
    if(-not (Test-Path $Path)){
        Write-Host "  FEIL: Mappen '$Path' finnes ikke." -ForegroundColor Red
        exit 2
    }
    $sampleDir = Join-Path $root 'sample'
    # Back up existing sample if needed
    $backupDir = $null
    if(Test-Path $sampleDir){
        $backupDir = Join-Path $root "sample_backup_$([guid]::NewGuid().ToString('N').Substring(0,8))"
        Rename-Item $sampleDir $backupDir
    }
    # Copy user files to sample/
    Copy-Item -Recurse -Force $Path $sampleDir
    Write-Host "    Kopierte filer fra: $Path" -ForegroundColor Gray
}

pwsh -NoProfile -File (Join-Path $root 'src\run_demo.ps1') -Out $outDir
$rowCount = (Import-Csv (Join-Path $outDir 'manifest.csv')).Count
Write-Host "    $rowCount filer registrert" -ForegroundColor Green

# Step 2: Merkle tree
Write-Host "  Steg 2/4: Bygger Merkle-tre..." -ForegroundColor White
pwsh -NoProfile -File (Join-Path $root 'tools\Merkle.ps1') -CsvPath (Join-Path $outDir 'manifest.csv')
$merkle = (Get-Content -Raw (Join-Path $outDir 'merkle_root.txt')).Trim()
Write-Host "    Merkle-rot: $($merkle.Substring(0,16))..." -ForegroundColor Green

# Step 3: Self-test
Write-Host "  Steg 3/4: Selvtest mot kjente verdier..." -ForegroundColor White
$testResult = pwsh -NoProfile -File (Join-Path $root 'tests\selftest.ps1') 2>&1
if($LASTEXITCODE -eq 0){
    Write-Host "    Selvtest bestatt" -ForegroundColor Green
} else {
    Write-Host "    Selvtest feilet: $testResult" -ForegroundColor Yellow
}

# Step 4: DoD report
Write-Host "  Steg 4/4: Genererer rapport..." -ForegroundColor White
pwsh -NoProfile -File (Join-Path $root 'tools\DoD.ps1') -Out $dodDir

# Generate human-readable report
$dod = Get-Content -Raw (Join-Path $dodDir 'DoD.json') | ConvertFrom-Json
$rows = Import-Csv (Join-Path $outDir 'manifest.csv')
$reportPath = Join-Path $outDir 'rapport.txt'

$report = @"
============================================================
  INTEGRITETSRAPPORT
  ASI-Omega Audit Pipeline
============================================================

  Dato:        $($dod.generated)
  Tidssone:    $($dod.timezone)
  Plattform:   $($dod.platform)

------------------------------------------------------------
  MERKLE-ROT (unikt fingeravtrykk for alle filer):
  $($dod.merkle_root)
------------------------------------------------------------

  FILER SOM ER REGISTRERT:

"@

foreach($r in $rows){
    $rel = ($r.Rel -replace '\\','/')
    $size = if($r.Size){ "$($r.Size) bytes" } else { "ukjent" }
    $hash = $r.SHA256.ToLower().Substring(0,16)
    $report += "    $rel`n"
    $report += "      SHA-256: $($r.SHA256.ToLower())`n"
    $report += "      Storrelse: $size`n`n"
}

$ntpStatus = if($dod.ntp_drift_seconds -eq 9999 -or $null -eq $dod.ntp_drift_seconds){
    "Ikke tilgjengelig"
} else {
    "$($dod.ntp_drift_seconds) sekunder"
}

$report += @"
------------------------------------------------------------
  TIDSVALIDERING:
    NTP-drift: $ntpStatus

------------------------------------------------------------
  HVORDAN VERIFISERE:

  1. Kjoer:  pwsh audit.ps1 -Verify
  2. Hvis ALLE filer er uendret, faar du:
     "RESULTAT: Alle filer er uendret. Integriteten er bekreftet."
  3. Hvis NOE er endret, faar du:
     "RESULTAT: FEIL FUNNET. Filer kan ha blitt endret."

------------------------------------------------------------
  TEKNISK FORKLARING:

  Hver fil faar et unikt SHA-256 fingeravtrykk (64 tegn).
  Alle fingeravtrykk kombineres i et Merkle-tre til EN rot.
  Endrer du en eneste byte i en eneste fil, endres roten.

  Denne rapporten + manifest.csv + merkle_root.txt + DoD.json
  utgjor til sammen en beviskjede som kan verifiseres uavhengig.
============================================================
"@

$report | Set-Content -Encoding UTF8 -Path $reportPath

# ─────────────────────────────────────────────────────
# Optional: GPG signing
# ─────────────────────────────────────────────────────
$signStatus = "Ikke aktivert (kjoer med -Sign eller -Full)"
if($Sign -or $Full){
    Write-Host ""
    Write-Host "  Steg 5: GPG-signering..." -ForegroundColor White
    $signArgs = @("-AuditDir", $outDir)
    if($GpgKey){ $signArgs += @("-KeyId", $GpgKey) }
    else { $signArgs += "-Auto" }

    $signResult = pwsh -NoProfile -File (Join-Path $root 'tools\Sign-Audit.ps1') @signArgs 2>&1
    if($LASTEXITCODE -eq 0){
        Write-Host "    Signering fullfoert" -ForegroundColor Green
        $signStatus = "Signert med GPG-noekkel $GpgKey"
    } elseif($LASTEXITCODE -eq 10){
        Write-Host "    GPG ikke installert — hopper over signering" -ForegroundColor Yellow
        Write-Host "    Installer Gpg4win: https://gpg4win.org" -ForegroundColor Gray
        $signStatus = "Ikke tilgjengelig (GPG ikke installert)"
    } else {
        Write-Host "    Signering feilet (exit $LASTEXITCODE)" -ForegroundColor Yellow
        $signStatus = "Feilet"
    }
}

# ─────────────────────────────────────────────────────
# Optional: OpenTimestamps
# ─────────────────────────────────────────────────────
$otsStatus = "Ikke aktivert (kjoer med -Timestamp eller -Full)"
if($Timestamp -or $Full){
    Write-Host ""
    Write-Host "  Steg 6: OpenTimestamps..." -ForegroundColor White
    $merkleRootFile = Join-Path $outDir 'merkle_root.txt'
    $otsResult = pwsh -NoProfile -File (Join-Path $root 'tools\OTS-Stamp.ps1') -Target $merkleRootFile 2>&1
    if($LASTEXITCODE -eq 0){
        Write-Host "    Uavhengig tidsstempel registrert" -ForegroundColor Green
        $otsStatus = "Sendt til OpenTimestamps (venter paa blokkjede-bekreftelse)"
    } elseif($LASTEXITCODE -eq 3){
        Write-Host "    Kunne ikke naa OTS-servere — lokal stub lagret" -ForegroundColor Yellow
        $otsStatus = "Feilet (ingen nettverkstilgang) — lokal stub lagret"
    } else {
        Write-Host "    OTS feilet (exit $LASTEXITCODE)" -ForegroundColor Yellow
        $otsStatus = "Feilet"
    }
}

# Restore backup if we moved files
if($backupDir -and (Test-Path $backupDir)){
    $sampleDir = Join-Path $root 'sample'
    Remove-Item -Recurse -Force $sampleDir -ErrorAction SilentlyContinue
    Rename-Item $backupDir $sampleDir
}

# Summary
Write-Host ""
Write-Host "  ========================================" -ForegroundColor Green
Write-Host "  AUDIT FULLFORT" -ForegroundColor Green
Write-Host "  ========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Filer registrert:   $rowCount" -ForegroundColor White
Write-Host "  Merkle-rot:         $($merkle.Substring(0,16))..." -ForegroundColor White
Write-Host "  Tidsstempel:        $($dod.generated)" -ForegroundColor White
Write-Host "  GPG-signering:      $signStatus" -ForegroundColor White
Write-Host "  OpenTimestamps:     $otsStatus" -ForegroundColor White
Write-Host ""
Write-Host "  Utdata:" -ForegroundColor Yellow
Write-Host "    output\rapport.txt       <-- Les denne!" -ForegroundColor White
Write-Host "    output\manifest.csv      Fil-fingeravtrykk" -ForegroundColor Gray
Write-Host "    output\merkle_root.txt   Kombinert rot" -ForegroundColor Gray
Write-Host "    output\DoD\DoD.json      Maskinlesbar rapport" -ForegroundColor Gray
if($Sign -or $Full){
Write-Host "    output\*.asc             GPG-signaturer" -ForegroundColor Gray
}
if($Timestamp -or $Full){
Write-Host "    output\ots_receipt.txt   OTS-kvittering" -ForegroundColor Gray
}
Write-Host ""
Write-Host "  For aa verifisere senere:" -ForegroundColor Yellow
Write-Host "    pwsh audit.ps1 -Verify" -ForegroundColor White
if(-not ($Sign -or $Full)){
Write-Host ""
Write-Host "  For full juridisk styrke:" -ForegroundColor Yellow
Write-Host "    pwsh audit.ps1 -Full" -ForegroundColor White
}
Write-Host ""
