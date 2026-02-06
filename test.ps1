# ASI-Omega Audit Pipeline — Test Runner
# Kjoer med:  pwsh test.ps1
#
# Alternativt kjoer bare en del:
#   pwsh test.ps1 -Only merkle
#   pwsh test.ps1 -Only quick
#   pwsh test.ps1 -Only all

param(
    [ValidateSet('all','quick','merkle','determinism','errors','criteria')]
    [string]$Only = 'all'
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
if(-not $repoRoot){ $repoRoot = (Get-Location).Path }

# Sjekk at vi er i riktig mappe
if(-not (Test-Path (Join-Path $repoRoot 'lib\crypto.ps1'))){
    Write-Host ""
    Write-Host "  FEIL: Finner ikke lib\crypto.ps1" -ForegroundColor Red
    Write-Host "  Du maa staa i prosjektmappen foerst." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Eksempel:" -ForegroundColor White
    Write-Host "    cd C:\Users\Bruker\asi-omega-audit-pipeline" -ForegroundColor Gray
    Write-Host "    pwsh test.ps1" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

$totalPass = 0
$totalFail = 0
$totalSkip = 0
$results = @()

function Run-TestFile([string]$Name, [string]$RelPath){
    $script = Join-Path $repoRoot $RelPath
    if(-not (Test-Path $script)){
        Write-Host "  SKIP  $Name (filen finnes ikke)" -ForegroundColor Yellow
        $script:totalSkip++
        $script:results += @{ Name=$Name; Status='SKIP' }
        return
    }

    Write-Host "  ...   $Name" -ForegroundColor Gray -NoNewline

    $errFile = Join-Path ([System.IO.Path]::GetTempPath()) "test-err-$([guid]::NewGuid().ToString('N').Substring(0,8)).txt"
    $outFile = Join-Path ([System.IO.Path]::GetTempPath()) "test-out-$([guid]::NewGuid().ToString('N').Substring(0,8)).txt"

    $proc = Start-Process -FilePath 'pwsh' `
        -ArgumentList @('-NoProfile','-NoLogo','-File',$script) `
        -Wait -PassThru -NoNewWindow `
        -RedirectStandardError $errFile `
        -RedirectStandardOutput $outFile

    # Overwrite the "..." line
    Write-Host "`r" -NoNewline

    if($proc.ExitCode -eq 0){
        Write-Host "  PASS  $Name" -ForegroundColor Green
        $script:totalPass++
        $script:results += @{ Name=$Name; Status='PASS' }
    } else {
        Write-Host "  FAIL  $Name (exit $($proc.ExitCode))" -ForegroundColor Red
        $script:totalFail++
        $script:results += @{ Name=$Name; Status='FAIL' }

        # Vis feilmelding
        if(Test-Path $outFile){
            $output = Get-Content $outFile -ErrorAction SilentlyContinue | Where-Object { $_ -match 'FAIL' } | Select-Object -First 5
            foreach($line in $output){
                Write-Host "         $line" -ForegroundColor DarkRed
            }
        }
    }

    # Rydd opp temp-filer
    Remove-Item -Path $errFile -ErrorAction SilentlyContinue
    Remove-Item -Path $outFile -ErrorAction SilentlyContinue
}

# ─────────────────────────────────────────────────────
# Header
# ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "  ASI-OMEGA AUDIT PIPELINE — TESTKJORING" -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "  Mappe: $repoRoot" -ForegroundColor Gray
Write-Host "  PowerShell: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
Write-Host "  Dato: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

# ─────────────────────────────────────────────────────
# Quick test (selftest + golden hashes)
# ─────────────────────────────────────────────────────
if($Only -eq 'all' -or $Only -eq 'quick'){
    Write-Host "  --- Hurtigtest ---" -ForegroundColor Cyan
    Run-TestFile "Golden hash-sjekk" "tests\selftest.ps1"
    Write-Host ""
}

# ─────────────────────────────────────────────────────
# Merkle tree tests
# ─────────────────────────────────────────────────────
if($Only -eq 'all' -or $Only -eq 'merkle'){
    Write-Host "  --- Merkle-tre (RFC 6962) ---" -ForegroundColor Cyan
    Run-TestFile "Merkle edge-cases (6 tester)" "tests\test-merkle-edge-cases.ps1"
    Write-Host ""
}

# ─────────────────────────────────────────────────────
# Determinism tests
# ─────────────────────────────────────────────────────
if($Only -eq 'all' -or $Only -eq 'determinism'){
    Write-Host "  --- Determinisme ---" -ForegroundColor Cyan
    Run-TestFile "Determinisme (5 tester)" "tests\test-determinism.ps1"
    Write-Host ""
}

# ─────────────────────────────────────────────────────
# Error path tests
# ─────────────────────────────────────────────────────
if($Only -eq 'all' -or $Only -eq 'errors'){
    Write-Host "  --- Feilhaandtering ---" -ForegroundColor Cyan
    Run-TestFile "Feilstier (6 tester)" "tests\test-error-paths.ps1"
    Write-Host ""
}

# ─────────────────────────────────────────────────────
# Acceptance criteria (C1-C6)
# ─────────────────────────────────────────────────────
if($Only -eq 'all' -or $Only -eq 'criteria'){
    Write-Host "  --- Akseptansekriterier ---" -ForegroundColor Cyan
    Run-TestFile "C1: Determinisme"       "tests\criteria\test-C1-determinism.ps1"
    Run-TestFile "C2: Tamper-deteksjon"   "tests\criteria\test-C2-tamper-detection.ps1"
    Run-TestFile "C3: Merkle-korrekthet"  "tests\criteria\test-C3-merkle-correctness.ps1"
    Run-TestFile "C4: Ingen stille feil"  "tests\criteria\test-C4-silent-failures.ps1"
    Run-TestFile "C5: Tidsstempel"        "tests\criteria\test-C5-timestamp.ps1"
    Run-TestFile "C6: Ende-til-ende"      "tests\criteria\test-C6-end-to-end.ps1"
    Write-Host ""
}

# ─────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "  RESULTAT" -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""

foreach($r in $results){
    $icon = switch($r.Status){
        'PASS' { '[OK]' }
        'FAIL' { '[!!]' }
        'SKIP' { '[--]' }
    }
    $color = switch($r.Status){
        'PASS' { 'Green' }
        'FAIL' { 'Red' }
        'SKIP' { 'Yellow' }
    }
    Write-Host "    $icon $($r.Name)" -ForegroundColor $color
}

Write-Host ""
$summary = "    BESTATT: $totalPass"
if($totalFail -gt 0){ $summary += "  |  FEILET: $totalFail" }
if($totalSkip -gt 0){ $summary += "  |  HOPPET OVER: $totalSkip" }

if($totalFail -eq 0){
    Write-Host $summary -ForegroundColor Green
    Write-Host ""
    Write-Host "    Alle tester bestatt!" -ForegroundColor Green
} else {
    Write-Host $summary -ForegroundColor Red
    Write-Host ""
    Write-Host "    $totalFail test(er) feilet. Se feilmeldingene over." -ForegroundColor Red
}

Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""

if($totalFail -gt 0){ exit 1 }
exit 0
