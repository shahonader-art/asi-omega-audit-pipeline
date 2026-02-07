# Run all criterion tests and produce a summary report
$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$tests = @(
    @{ Id="C1"; Name="DETERMINISM";          Script="test-C1-determinism.ps1" },
    @{ Id="C2"; Name="TAMPER DETECTION";      Script="test-C2-tamper-detection.ps1" },
    @{ Id="C3"; Name="MERKLE CORRECTNESS";    Script="test-C3-merkle-correctness.ps1" },
    @{ Id="C4"; Name="NO SILENT FAILURES";    Script="test-C4-silent-failures.ps1" },
    @{ Id="C5"; Name="TIMESTAMP TRUST";       Script="test-C5-timestamp.ps1" },
    @{ Id="C6"; Name="END-TO-END CHAIN";      Script="test-C6-end-to-end.ps1" },
    @{ Id="C7"; Name="CRYPTO STRESS";        Script="test-C7-crypto-stress.ps1" }
)

$results = @()
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " FORENSIC PIPELINE ACCEPTANCE TESTS" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

foreach($t in $tests){
    Write-Host "--- $($t.Id): $($t.Name) ---" -ForegroundColor Cyan
    $script = Join-Path $scriptDir $t.Script
    $proc = Start-Process -FilePath pwsh -ArgumentList "-NoProfile","-File",$script `
            -Wait -PassThru -NoNewWindow
    $status = switch($proc.ExitCode){
        0 { "PASS" }
        1 { "FAIL" }
        2 { "KNOWN-GAP" }
        default { "ERROR ($($proc.ExitCode))" }
    }
    $results += @{ Id=$t.Id; Name=$t.Name; Status=$status; Exit=$proc.ExitCode }
    Write-Host ""
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$passCount = ($results | Where-Object { $_.Status -eq "PASS" }).Count
$failCount = ($results | Where-Object { $_.Status -eq "FAIL" }).Count
$gapCount  = ($results | Where-Object { $_.Status -eq "KNOWN-GAP" }).Count

foreach($r in $results){
    $color = switch($r.Status){
        "PASS"      { "Green" }
        "FAIL"      { "Red" }
        "KNOWN-GAP" { "Yellow" }
        default     { "Red" }
    }
    Write-Host "  $($r.Id) $($r.Name): $($r.Status)" -ForegroundColor $color
}

Write-Host "`n  PASS: $passCount  |  FAIL: $failCount  |  KNOWN-GAP: $gapCount" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if($failCount -gt 0){ exit 1 }
if($gapCount -gt 0){ exit 2 }
exit 0
