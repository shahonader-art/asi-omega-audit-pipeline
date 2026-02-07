# Criterion 2: TAMPER DETECTION
# Any modification to source files, manifest, or Merkle root MUST be detected.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$verifyScript = Join-Path $repoRoot 'tools\verify.ps1'
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "C2-$([guid]::NewGuid().ToString('N').Substring(0,8))"
$fail = $false; $gap = $false

# Load shared crypto library for direct Merkle computation
. (Join-Path $repoRoot 'lib\crypto.ps1')

function Pass($id,$m){ Write-Host "PASS [$id]: $m" -ForegroundColor Green }
function Fail($id,$m){ Write-Host "FAIL [$id]: $m" -ForegroundColor Red; $script:fail=$true }
function Gap($id,$m){ Write-Host "KNOWN-GAP [$id]: $m" -ForegroundColor Yellow; $script:gap=$true }

# Helper: generate a full pipeline run in a self-contained directory
function New-Pipeline([string]$dir){
    $sampleDir = Join-Path $dir 'sample'
    $outDir = Join-Path $dir 'output'
    $dodDir = Join-Path $outDir 'DoD'
    New-Item -ItemType Directory -Force -Path $sampleDir | Out-Null
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    New-Item -ItemType Directory -Force -Path $dodDir | Out-Null

    # Create known sample files
    "FileA content here" | Set-Content -Encoding UTF8 (Join-Path $sampleDir 'a.txt')
    "FileB content here" | Set-Content -Encoding UTF8 (Join-Path $sampleDir 'b.txt')

    # Generate manifest
    $files = Get-ChildItem -Path $sampleDir -File | Sort-Object Name
    $csvRows = @()
    $leaves = @()
    foreach($f in $files){
        $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash
        $csvRows += [pscustomobject]@{
            Path   = $f.FullName
            Rel    = "sample/$($f.Name)"
            SHA256 = $h
            Size   = $f.Length
        }
        $leaves += $h.ToLower()
    }
    $csvRows | ConvertTo-Csv -NoTypeInformation | Set-Content -Encoding UTF8 (Join-Path $outDir 'manifest.csv')

    # Compute Merkle root using shared library (avoids subprocess issues)
    $mr = Build-MerkleTree $leaves
    $mr | Set-Content -Encoding ASCII -Path (Join-Path $outDir 'merkle_root.txt')

    # Create DoD.json
    [pscustomobject]@{ schema_version=2; merkle_root=$mr; ntp_drift_seconds=0.001; generated=(Get-Date).ToString("o") } |
        ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $dodDir 'DoD.json')

    return @{
        SampleDir = $sampleDir
        OutDir    = $outDir
        DoDJson   = Join-Path $dodDir 'DoD.json'
        Manifest  = Join-Path $outDir 'manifest.csv'
        MerkleRoot= Join-Path $outDir 'merkle_root.txt'
    }
}

# Helper: run verify and return exit code
# Uses a wrapper script with *>&1 to capture ALL output streams (including Write-Host)
function Test-Verify($p){
    $uid = [guid]::NewGuid().ToString('N').Substring(0,8)
    $wrapperPath = Join-Path $tmpDir "vwrap-$uid.ps1"
    $outFile = Join-Path $tmpDir "vout-$uid.txt"
    $errFile = Join-Path $tmpDir "verr-$uid.txt"
    # Wrapper merges all PS streams (including info/Write-Host stream 6) into stdout
    @"
`$PSNativeCommandUseErrorActionPreference = `$false
& '$verifyScript' -DoD '$($p.DoDJson)' -Manifest '$($p.Manifest)' -MerkleRoot '$($p.MerkleRoot)' *>&1
exit `$LASTEXITCODE
"@ | Set-Content -Encoding UTF8 $wrapperPath
    $proc = Start-Process -FilePath pwsh `
        -ArgumentList "-NoProfile -File `"$wrapperPath`"" `
        -Wait -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile -NoNewWindow
    if($proc.ExitCode -ne 0 -and (Test-Path $outFile)){
        Write-Host "  --- verify.ps1 output (exit $($proc.ExitCode)) ---" -ForegroundColor DarkGray
        Get-Content $outFile -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host "  VERIFY> $_" -ForegroundColor DarkGray
        }
    }
    return $proc.ExitCode
}

# =====================================================================
# T1: Modifying a source file must cause verification failure
# =====================================================================
# verify.ps1 now checks files on disk against manifest hashes.
# This test verifies that modifying a file is detected.
$p1 = New-Pipeline (Join-Path $tmpDir 't1')
$code1_before = Test-Verify $p1
if($code1_before -ne 0){ Fail "T1" "Baseline verify failed before tampering (exit $code1_before)" }

# Tamper: modify the actual source file
"TAMPERED CONTENT" | Set-Content -Encoding UTF8 (Join-Path $p1.SampleDir 'a.txt')

# Re-run verify WITHOUT regenerating manifest — does it detect the change?
$code1_after = Test-Verify $p1
if($code1_after -ne 0){
    Pass "T1" "File modification detected by verify (file-on-disk check works)"
} else {
    Fail "T1" "verify.ps1 PASSED despite file modification — disk check not working"
}

# =====================================================================
# T2: Adding an extra file must be detected
# =====================================================================
$p2 = New-Pipeline (Join-Path $tmpDir 't2')
"Extra file" | Set-Content -Encoding UTF8 (Join-Path $p2.SampleDir 'extra.txt')
# verify without regenerating manifest
$code2 = Test-Verify $p2
if($code2 -ne 0){
    Pass "T2" "Extra file detected by verify"
} else {
    Gap "T2" "verify.ps1 PASSES despite extra file in sample/ — it does NOT scan the directory"
}

# =====================================================================
# T3: Removing a file must be detected
# =====================================================================
$p3 = New-Pipeline (Join-Path $tmpDir 't3')
Remove-Item -Force (Join-Path $p3.SampleDir 'b.txt')
$code3 = Test-Verify $p3
if($code3 -ne 0){
    Pass "T3" "Removed file detected by verify (file-on-disk check works)"
} else {
    Fail "T3" "verify.ps1 PASSED despite deleted file — disk check not working"
}

# =====================================================================
# T4: Reordering manifest rows must be detected
# =====================================================================
$p4 = New-Pipeline (Join-Path $tmpDir 't4')
$rows4 = Import-Csv $p4.Manifest
$reversed = $rows4[($rows4.Count-1)..0]  # reverse order
$reversed | ConvertTo-Csv -NoTypeInformation | Set-Content -Encoding UTF8 $p4.Manifest
# Recompute Merkle root from reordered manifest using shared library
$reorderedLeaves = @(); foreach($r in $reversed){ $reorderedLeaves += $r.SHA256.ToLower() }
$newRoot = Build-MerkleTree $reorderedLeaves
$newRoot | Set-Content -Encoding ASCII -Path $p4.MerkleRoot
# Update DoD to match new root
$dod4 = Get-Content -Raw $p4.DoDJson | ConvertFrom-Json
$dod4.merkle_root = $newRoot
$dod4 | ConvertTo-Json | Set-Content -Encoding UTF8 $p4.DoDJson

$code4 = Test-Verify $p4
if($code4 -ne 0){
    Pass "T4" "Manifest reorder detected"
} else {
    # If root changed due to reorder, verify would have caught it via original root.
    # But we updated DoD too, so it passes. Check if root actually changed:
    $origP4 = New-Pipeline (Join-Path $tmpDir 't4_orig')
    $origRoot = (Get-Content -Raw $origP4.MerkleRoot).Trim()
    if($newRoot -ne $origRoot){
        Gap "T4" "Manifest reorder changes Merkle root (good), but attacker can update DoD+root to match (no signature)"
    } else {
        Gap "T4" "Manifest reorder produces SAME Merkle root — order not reflected in hash"
    }
}

# =====================================================================
# T5: Replacing manifest+merkle together (without GPG signature)
# =====================================================================
$p5 = New-Pipeline (Join-Path $tmpDir 't5')
# Attacker creates entirely new content
"Completely fake content" | Set-Content -Encoding UTF8 (Join-Path $p5.SampleDir 'a.txt')
"Also fake content" | Set-Content -Encoding UTF8 (Join-Path $p5.SampleDir 'b.txt')
# Regenerate everything from attacker's files
$fakeFiles = Get-ChildItem -Path $p5.SampleDir -File | Sort-Object Name
$fakeManifest = @()
foreach($f in $fakeFiles){
    $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash
    $fakeManifest += [pscustomobject]@{ Path=$f.FullName; Rel="sample/$($f.Name)"; SHA256=$h; Size=$f.Length }
}
$fakeManifest | ConvertTo-Csv -NoTypeInformation | Set-Content -Encoding UTF8 $p5.Manifest
$fakeLeaves = @(); foreach($f2 in $fakeManifest){ $fakeLeaves += $f2.SHA256.ToLower() }
$fakeRoot = Build-MerkleTree $fakeLeaves
$fakeRoot | Set-Content -Encoding ASCII -Path $p5.MerkleRoot
[pscustomobject]@{ merkle_root=$fakeRoot; ntp_drift_seconds=0.001; generated=(Get-Date).ToString("o") } |
    ConvertTo-Json | Set-Content -Encoding UTF8 $p5.DoDJson

$code5 = Test-Verify $p5
if($code5 -ne 0){
    Pass "T5" "Full replacement detected"
} else {
    Gap "T5" "verify.ps1 PASSES after full file+manifest+merkle+DoD replacement — no GPG signature to anchor trust"
}

# Cleanup
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

if($fail){ Write-Host "CRITERION 2 (TAMPER DETECTION): FAILED" -ForegroundColor Red; exit 1 }
if($gap){ Write-Host "CRITERION 2 (TAMPER DETECTION): KNOWN GAPS FOUND"; exit 2 }
Write-Host "CRITERION 2 (TAMPER DETECTION): PASS" -ForegroundColor Green; exit 0
