# Criterion 8: USER WORKFLOW
# Simulates real user scenarios with audit.ps1 — the actual entry point.
# Tests the complete user experience from audit to verification to tamper detection.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$auditScript = Join-Path $repoRoot 'audit.ps1'
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "C8-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$fail = $false; $gap = $false

function Pass($id,$m){ Write-Host "PASS [$id]: $m" -ForegroundColor Green }
function Fail($id,$m){ Write-Host "FAIL [$id]: $m" -ForegroundColor Red; $script:fail=$true }
function Gap($id,$m){ Write-Host "KNOWN-GAP [$id]: $m" -ForegroundColor Yellow; $script:gap=$true }

# Helper: run audit.ps1 using .NET Process + EncodedCommand.
# PS 7.5 drops switch params with -File and -Command due to quoting bugs.
# EncodedCommand Base64-encodes the entire script, bypassing all parsing.
function Run-Audit([string[]]$Args){
    $script = "& '$auditScript' $($Args -join ' ')"
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($script)
    $encoded = [Convert]::ToBase64String($bytes)
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'pwsh'
    $psi.Arguments = "-NoProfile -EncodedCommand $encoded"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return @{ ExitCode = $p.ExitCode; Output = "$stdout`n$stderr" }
}

# =====================================================================
# U1: Bruker kjoerer audit.ps1 — full pipeline fungerer
# User runs audit.ps1 — complete pipeline works
# =====================================================================
Write-Host ""
Write-Host "--- Scenario 1: Ny audit ---" -ForegroundColor Cyan
$r1 = Run-Audit @()

if($r1.ExitCode -eq 0){
    Pass "U1" "audit.ps1 completed successfully (exit 0)"
} else {
    Fail "U1" "audit.ps1 failed (exit $($r1.ExitCode))"
    if($r1.Output){ Write-Host "  OUTPUT: $($r1.Output.Substring(0, [Math]::Min(500, $r1.Output.Length)))" -ForegroundColor DarkGray }
}

# Check that all expected output files exist
$outDir = Join-Path $repoRoot 'output'
$expectedFiles = @(
    @{ Path=(Join-Path $outDir 'manifest.csv');       Name="manifest.csv" },
    @{ Path=(Join-Path $outDir 'merkle_root.txt');    Name="merkle_root.txt" },
    @{ Path=(Join-Path $outDir 'DoD\DoD.json');       Name="DoD.json" },
    @{ Path=(Join-Path $outDir 'rapport.txt');        Name="rapport.txt" }
)

$allExist = $true
foreach($f in $expectedFiles){
    if(-not (Test-Path $f.Path)){
        Fail "U1" "Missing output: $($f.Name)"
        $allExist = $false
    }
}
if($allExist){ Pass "U1" "All output artifacts created (manifest, merkle_root, DoD, rapport)" }

# =====================================================================
# U2: Bruker verifiserer — audit.ps1 -Verify bestaatt
# User verifies — should pass on fresh audit
# =====================================================================
Write-Host ""
Write-Host "--- Scenario 2: Verifisering etter audit ---" -ForegroundColor Cyan
$r2 = Run-Audit @("-Verify")

if($r2.ExitCode -eq 0 -and $r2.Output -notmatch 'FEIL|Mangler'){
    Pass "U2" "audit.ps1 -Verify passes on fresh audit"
} else {
    Fail "U2" "audit.ps1 -Verify failed on fresh audit (exit $($r2.ExitCode))"
    if($r2.Output){
        $failLines = ($r2.Output -split "`n") | Where-Object { $_ -match 'FAIL' } | Select-Object -First 5
        foreach($line in $failLines){ Write-Host "  VERIFY> $line" -ForegroundColor DarkGray }
    }
}

# =====================================================================
# U3: Bruker endrer en fil — verifisering oppdager det
# User modifies a file — verify detects tampering
# =====================================================================
Write-Host ""
Write-Host "--- Scenario 3: Tamper-deteksjon ---" -ForegroundColor Cyan

# Save original content
$sampleFile = Join-Path $repoRoot 'sample\readme_sample.txt'
$originalContent = [System.IO.File]::ReadAllBytes($sampleFile)

# Tamper with the file
"TAMPERED BY USER TEST" | Set-Content -Encoding UTF8 $sampleFile

$r3 = Run-Audit @("-Verify")

# Restore original content IMMEDIATELY (before any error can prevent it)
[System.IO.File]::WriteAllBytes($sampleFile, $originalContent)

# Check BOTH exit code AND output for failure indicators
$tamperDetected = ($r3.ExitCode -ne 0) -or ($r3.Output -match 'FEIL|FAIL|mismatch|endret|Mangler')
if($tamperDetected){
    Pass "U3" "Tamper detected! verify failed after file modification (exit $($r3.ExitCode))"
} else {
    Fail "U3" "audit.ps1 -Verify PASSED despite file modification — tamper not detected!"
    Write-Host "  EXIT=$($r3.ExitCode) OUTPUT=$(if($r3.Output){$r3.Output.Substring(0,[Math]::Min(300,$r3.Output.Length))})" -ForegroundColor DarkGray
}

# =====================================================================
# U4: Bruker kjoerer ny audit etter endring — ny rot, verifisering OK
# User re-audits after restoring file — verify passes again
# =====================================================================
Write-Host ""
Write-Host "--- Scenario 4: Re-audit etter gjenoppretting ---" -ForegroundColor Cyan
$r4a = Run-Audit @()

if($r4a.ExitCode -eq 0){
    Pass "U4" "Re-audit after restore completed successfully"
} else {
    Fail "U4" "Re-audit failed (exit $($r4a.ExitCode))"
}

$r4b = Run-Audit @("-Verify")
if($r4b.ExitCode -eq 0){
    Pass "U4" "Verify passes after re-audit"
} else {
    Fail "U4" "Verify failed after re-audit (exit $($r4b.ExitCode))"
}

# =====================================================================
# U5: Rapporten er lesbar og inneholder Merkle-rot
# Report is readable and contains the Merkle root
# =====================================================================
Write-Host ""
Write-Host "--- Scenario 5: Rapport-kvalitet ---" -ForegroundColor Cyan
$rapportPath = Join-Path $outDir 'rapport.txt'

if(Test-Path $rapportPath){
    $rapportContent = Get-Content -Raw $rapportPath
    $merkleFromFile = (Get-Content -Raw (Join-Path $outDir 'merkle_root.txt')).Trim()

    # Rapport must contain the Merkle root
    if($rapportContent -match [regex]::Escape($merkleFromFile)){
        Pass "U5" "rapport.txt contains the Merkle root"
    } else {
        Fail "U5" "rapport.txt does NOT contain the Merkle root"
    }

    # Rapport must list all files from manifest
    $rows = Import-Csv (Join-Path $outDir 'manifest.csv')
    $allListed = $true
    foreach($r in $rows){
        $rel = ($r.Rel -replace '\\','/')
        if($rapportContent -notmatch [regex]::Escape($rel)){
            Fail "U5" "rapport.txt missing file: $rel"
            $allListed = $false
        }
    }
    if($allListed){ Pass "U5" "rapport.txt lists all $($rows.Count) audited files" }

    # Rapport must contain SHA-256 hashes
    $hashCount = ([regex]::Matches($rapportContent, '[0-9a-fA-F]{64}')).Count
    if($hashCount -ge $rows.Count){
        Pass "U5" "rapport.txt contains $hashCount SHA-256 hashes"
    } else {
        Fail "U5" "rapport.txt has only $hashCount hashes (expected >= $($rows.Count))"
    }

    # Rapport must contain verification instructions
    if($rapportContent -match 'audit\.ps1.*-Verify'){
        Pass "U5" "rapport.txt includes verification command"
    } else {
        Gap "U5" "rapport.txt does not include 'audit.ps1 -Verify' instructions"
    }
} else {
    Fail "U5" "rapport.txt not found"
}

# =====================================================================
# U6: Hjelp-modus fungerer
# Help mode works
# =====================================================================
Write-Host ""
Write-Host "--- Scenario 6: Hjelp-modus ---" -ForegroundColor Cyan
$r6 = Run-Audit @("-Help")

if($r6.ExitCode -eq 0){
    Pass "U6" "audit.ps1 -Help exits 0"
} else {
    Fail "U6" "audit.ps1 -Help failed (exit $($r6.ExitCode))"
}

if($r6.Output -match 'audit\.ps1'){
    Pass "U6" "Help output contains usage examples"
} else {
    Fail "U6" "Help output missing usage examples"
}

# =====================================================================
# U7: Verify uten tidligere audit — gir tydelig feilmelding
# Verify without prior audit — gives clear error
# =====================================================================
Write-Host ""
Write-Host "--- Scenario 7: Verify uten audit ---" -ForegroundColor Cyan

# Temporarily rename output dir so verify has nothing
$outBackup = Join-Path $repoRoot "output_backup_c8_$([guid]::NewGuid().ToString('N').Substring(0,8))"
$needsRestore = $false
if(Test-Path $outDir){
    Move-Item -Path $outDir -Destination $outBackup -Force
    $needsRestore = $true
}

try {
    $r7 = Run-Audit @("-Verify")

    # Check BOTH exit code AND output for failure indicators
    $verifyFailed = ($r7.ExitCode -ne 0) -or ($r7.Output -match 'Mangler|missing|feil|FEIL|error|Error')
    if($verifyFailed){
        Pass "U7" "audit.ps1 -Verify correctly fails when no audit exists (exit $($r7.ExitCode))"
    } else {
        Fail "U7" "audit.ps1 -Verify PASSED despite no audit output existing"
        Write-Host "  EXIT=$($r7.ExitCode) OUTPUT=$(if($r7.Output){$r7.Output.Substring(0,[Math]::Min(300,$r7.Output.Length))})" -ForegroundColor DarkGray
    }

    # Check for helpful error message
    if($r7.Output -match 'Mangler|missing|feil|FEIL'){
        Pass "U7" "Error message is user-friendly"
    } else {
        Gap "U7" "Error message could be more user-friendly"
    }
} finally {
    # Always restore output dir
    if($needsRestore -and (Test-Path $outBackup)){
        if(Test-Path $outDir){ Remove-Item -Recurse -Force $outDir -ErrorAction SilentlyContinue }
        Move-Item -Path $outBackup -Destination $outDir -Force
    }
}

# =====================================================================
# U8: DoD.json er gyldig og inneholder alle noedvendige felt
# DoD.json is valid and contains all required fields
# =====================================================================
Write-Host ""
Write-Host "--- Scenario 8: DoD-rapport kvalitet ---" -ForegroundColor Cyan
$dodPath = Join-Path $outDir 'DoD\DoD.json'

if(Test-Path $dodPath){
    $dodRaw = Get-Content -Raw $dodPath
    $requiredFields = @('schema_version', 'merkle_root', 'generated', 'ntp_drift_seconds')
    $allPresent = $true

    foreach($field in $requiredFields){
        if($dodRaw -match "`"$field`""){
            Pass "U8" "DoD.json has '$field' field"
        } else {
            Fail "U8" "DoD.json missing required field: $field"
            $allPresent = $false
        }
    }

    # Check that merkle_root in DoD matches merkle_root.txt
    $mrMatch = [regex]::Match($dodRaw, '"merkle_root"\s*:\s*"([^"]+)"')
    if($mrMatch.Success){
        $dodMr = $mrMatch.Groups[1].Value.ToLower()
        $fileMr = (Get-Content -Raw (Join-Path $outDir 'merkle_root.txt')).Trim().ToLower()
        if($dodMr -eq $fileMr){
            Pass "U8" "DoD.json merkle_root matches merkle_root.txt"
        } else {
            Fail "U8" "DoD.json merkle_root ($dodMr) != merkle_root.txt ($fileMr)"
        }
    }

    # Check script_hashes present (schema v2)
    if($dodRaw -match '"script_hashes"'){
        Pass "U8" "DoD.json includes script_hashes (self-integrity)"
    } else {
        Gap "U8" "DoD.json missing script_hashes field"
    }
} else {
    Fail "U8" "DoD.json not found"
}

# =====================================================================
# U9: Manifest har korrekte kolonner og data
# Manifest has correct columns and data
# =====================================================================
Write-Host ""
Write-Host "--- Scenario 9: Manifest-kvalitet ---" -ForegroundColor Cyan
$manifestPath = Join-Path $outDir 'manifest.csv'

if(Test-Path $manifestPath){
    $rows = Import-Csv $manifestPath

    if($rows.Count -gt 0){
        Pass "U9" "manifest.csv has $($rows.Count) entries"
    } else {
        Fail "U9" "manifest.csv is empty"
    }

    # Check required columns
    $firstRow = $rows[0]
    $requiredCols = @('Path', 'Rel', 'SHA256', 'Size')
    foreach($col in $requiredCols){
        if($firstRow.PSObject.Properties.Name -contains $col){
            Pass "U9" "manifest.csv has '$col' column"
        } else {
            Fail "U9" "manifest.csv missing '$col' column"
        }
    }

    # All SHA256 values should be valid 64-char hex
    $invalidHashes = $rows | Where-Object { $_.SHA256 -notmatch '^[0-9a-fA-F]{64}$' }
    if($invalidHashes.Count -eq 0){
        Pass "U9" "All SHA256 hashes are valid 64-char hex"
    } else {
        Fail "U9" "$($invalidHashes.Count) rows have invalid SHA256 values"
    }

    # All Rel paths should be non-empty
    $emptyRels = $rows | Where-Object { -not $_.Rel -or $_.Rel.Trim() -eq '' }
    if($emptyRels.Count -eq 0){
        Pass "U9" "All entries have non-empty Rel paths"
    } else {
        Fail "U9" "$($emptyRels.Count) rows have empty Rel paths"
    }
} else {
    Fail "U9" "manifest.csv not found"
}

# Cleanup
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

# Summary
Write-Host ""
if($fail){ Write-Host "CRITERION 8 (USER WORKFLOW): FAILED" -ForegroundColor Red; exit 1 }
if($gap){ Write-Host "CRITERION 8 (USER WORKFLOW): KNOWN GAPS FOUND"; exit 2 }
Write-Host "CRITERION 8 (USER WORKFLOW): PASS" -ForegroundColor Green; exit 0
