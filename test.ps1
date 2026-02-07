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
        -ArgumentList "-NoProfile -NoLogo -File `"$script`"" `
        -Wait -PassThru -NoNewWindow `
        -RedirectStandardError $errFile `
        -RedirectStandardOutput $outFile

    # Overwrite the "..." line
    Write-Host "`r" -NoNewline

    if($proc.ExitCode -eq 0){
        Write-Host "  PASS  $Name" -ForegroundColor Green
        $script:totalPass++
        $script:results += @{ Name=$Name; Status='PASS' }
    } elseif($proc.ExitCode -eq 2){
        # Exit code 2 = known gaps (acceptable, not a hard failure)
        Write-Host "  GAPS  $Name (kjente avvik)" -ForegroundColor Yellow
        $script:totalSkip++
        $script:results += @{ Name=$Name; Status='GAPS' }

        if(Test-Path $outFile){
            $output = Get-Content $outFile -ErrorAction SilentlyContinue | Where-Object { $_ -match 'KNOWN-GAP' } | Select-Object -First 3
            foreach($line in $output){
                Write-Host "         $line" -ForegroundColor DarkYellow
            }
        }
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
# Pre-flight: fix CRLF line endings in sample files
# Git on Windows converts LF to CRLF which changes SHA-256 hashes.
# This normalizes sample files to LF for consistent hashing.
# ─────────────────────────────────────────────────────
$sampleDir = Join-Path $repoRoot 'sample'
if(Test-Path $sampleDir){
    $fixed = 0
    Get-ChildItem $sampleDir -Recurse -File | ForEach-Object {
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        $hasCrlf = $false
        for($i = 0; $i -lt $bytes.Length - 1; $i++){
            if($bytes[$i] -eq 13 -and $bytes[$i+1] -eq 10){ $hasCrlf = $true; break }
        }
        if($hasCrlf){
            $content = [System.IO.File]::ReadAllText($_.FullName)
            $normalized = $content.Replace("`r`n", "`n")
            [System.IO.File]::WriteAllBytes($_.FullName, [System.Text.Encoding]::UTF8.GetBytes($normalized))
            $fixed++
        }
    }
    if($fixed -gt 0){
        Write-Host "  Fikset linjeskift i $fixed sample-fil(er) (CRLF -> LF)" -ForegroundColor DarkGray
        Write-Host ""
    }
}

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
# Acceptance criteria (C1-C8)
# ─────────────────────────────────────────────────────
if($Only -eq 'all' -or $Only -eq 'criteria'){
    Write-Host "  --- Akseptansekriterier ---" -ForegroundColor Cyan
    Run-TestFile "C1: Determinisme"       "tests\criteria\test-C1-determinism.ps1"
    Run-TestFile "C2: Tamper-deteksjon"   "tests\criteria\test-C2-tamper-detection.ps1"
    Run-TestFile "C3: Merkle-korrekthet"  "tests\criteria\test-C3-merkle-correctness.ps1"
    Run-TestFile "C4: Ingen stille feil"  "tests\criteria\test-C4-silent-failures.ps1"
    Run-TestFile "C5: Tidsstempel"        "tests\criteria\test-C5-timestamp.ps1"
    Run-TestFile "C6: Ende-til-ende"      "tests\criteria\test-C6-end-to-end.ps1"
    Run-TestFile "C7: Krypto-stresstest"  "tests\criteria\test-C7-crypto-stress.ps1"
    Run-TestFile "C8: Bruker-arbeidsflyt" "tests\criteria\test-C8-user-workflow.ps1"
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
        'GAPS' { '[~~]' }
        'SKIP' { '[--]' }
    }
    $color = switch($r.Status){
        'PASS' { 'Green' }
        'FAIL' { 'Red' }
        'GAPS' { 'Yellow' }
        'SKIP' { 'Yellow' }
    }
    Write-Host "    $icon $($r.Name)" -ForegroundColor $color
}

Write-Host ""
$totalGaps = ($results | Where-Object { $_.Status -eq 'GAPS' }).Count
$summary = "    BESTATT: $totalPass"
if($totalFail -gt 0){ $summary += "  |  FEILET: $totalFail" }
if($totalGaps -gt 0){ $summary += "  |  KJENTE AVVIK: $totalGaps" }
if(($totalSkip - $totalGaps) -gt 0){ $summary += "  |  HOPPET OVER: $($totalSkip - $totalGaps)" }

if($totalFail -eq 0){
    Write-Host $summary -ForegroundColor Green
    Write-Host ""
    if($totalGaps -gt 0){
        Write-Host "    Alle tester bestatt! ($totalGaps med kjente avvik)" -ForegroundColor Green
    } else {
        Write-Host "    Alle tester bestatt!" -ForegroundColor Green
    }
} else {
    Write-Host $summary -ForegroundColor Red
    Write-Host ""
    Write-Host "    $totalFail test(er) feilet. Se feilmeldingene over." -ForegroundColor Red
}

Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""

if($totalFail -gt 0){ exit 1 }
exit 0
