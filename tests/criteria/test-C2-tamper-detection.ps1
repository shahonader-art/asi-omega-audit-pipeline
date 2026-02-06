# Criterion 2: TAMPER DETECTION
# Any modification to source files, manifest, or Merkle root MUST be detected.
$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$demoScript = Join-Path $repoRoot 'src\run_demo.ps1'
$merkleScript = Join-Path $repoRoot 'tools\Merkle.ps1'
$dodScript = Join-Path $repoRoot 'tools\DoD.ps1'
$verifyScript = Join-Path $repoRoot 'tools\verify.ps1'
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "C2-$([guid]::NewGuid().ToString('N').Substring(0,8))"
$fail = $false; $gap = $false

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

    # Generate manifest manually (since run_demo.ps1 targets ../sample relative to itself)
    $files = Get-ChildItem -Path $sampleDir -File | Sort-Object Name
    $manifest = @()
    foreach($f in $files){
        $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash
        $manifest += [pscustomobject]@{
            Path   = $f.FullName
            Rel    = "sample/$($f.Name)"
            SHA256 = $h
            Size   = $f.Length
        }
    }
    $manifest | ConvertTo-Csv -NoTypeInformation | Set-Content -Encoding UTF8 (Join-Path $outDir 'manifest.csv')

    # Compute Merkle root
    pwsh -NoProfile -File $merkleScript -CsvPath (Join-Path $outDir 'manifest.csv')

    # Create DoD.json that points to the merkle root
    $mr = (Get-Content -Raw (Join-Path $outDir 'merkle_root.txt')).Trim()
    @{ merkle_root=$mr; ntp_drift_seconds=0.001; generated=(Get-Date).ToString("o") } |
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
function Test-Verify($p){
    $errFile = Join-Path $tmpDir "verr-$([guid]::NewGuid().ToString('N').Substring(0,8)).txt"
    $proc = Start-Process -FilePath pwsh `
        -ArgumentList "-NoProfile","-File",$verifyScript,"-DoD",$p.DoDJson,"-Manifest",$p.Manifest,"-MerkleRoot",$p.MerkleRoot `
        -Wait -PassThru -RedirectStandardError $errFile -NoNewWindow
    return $proc.ExitCode
}

# =====================================================================
# T1: Modifying a source file must cause verification failure
# =====================================================================
# NOTE: verify.ps1 only checks manifest->merkle->DoD consistency.
# It does NOT re-hash files on disk. This test checks whether
# modify-then-reverify detects the change.
$p1 = New-Pipeline (Join-Path $tmpDir 't1')
$code1_before = Test-Verify $p1
if($code1_before -ne 0){ Fail "T1" "Baseline verify failed before tampering (exit $code1_before)" }

# Tamper: modify the actual source file
"TAMPERED CONTENT" | Set-Content -Encoding UTF8 (Join-Path $p1.SampleDir 'a.txt')

# Re-run verify WITHOUT regenerating manifest — does it detect the change?
$code1_after = Test-Verify $p1
if($code1_after -ne 0){
    Pass "T1" "File modification detected by verify"
} else {
    # verify.ps1 doesn't check files on disk, so this is a known gap
    Gap "T1" "verify.ps1 PASSES despite file modification — it does NOT re-hash files on disk"
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
    Pass "T3" "Removed file detected by verify"
} else {
    Gap "T3" "verify.ps1 PASSES despite deleted file — it does NOT check files on disk"
}

# =====================================================================
# T4: Reordering manifest rows must be detected
# =====================================================================
$p4 = New-Pipeline (Join-Path $tmpDir 't4')
$rows4 = Import-Csv $p4.Manifest
$reversed = $rows4[($rows4.Count-1)..0]  # reverse order
$reversed | ConvertTo-Csv -NoTypeInformation | Set-Content -Encoding UTF8 $p4.Manifest
# Recompute Merkle root from reordered manifest
pwsh -NoProfile -File $merkleScript -CsvPath $p4.Manifest
# Update DoD to match new root
$newRoot = (Get-Content -Raw $p4.MerkleRoot).Trim()
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
pwsh -NoProfile -File $merkleScript -CsvPath $p5.Manifest
$fakeRoot = (Get-Content -Raw $p5.MerkleRoot).Trim()
@{ merkle_root=$fakeRoot; ntp_drift_seconds=0.001; generated=(Get-Date).ToString("o") } |
    ConvertTo-Json | Set-Content -Encoding UTF8 $p5.DoDJson

$code5 = Test-Verify $p5
if($code5 -ne 0){
    Pass "T5" "Full replacement detected"
} else {
    Gap "T5" "verify.ps1 PASSES after full file+manifest+merkle+DoD replacement — no GPG signature to anchor trust"
}

# Cleanup
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

if($fail){ Write-Error "CRITERION 2 (TAMPER DETECTION): FAILED"; exit 1 }
if($gap){ Write-Host "CRITERION 2 (TAMPER DETECTION): KNOWN GAPS FOUND"; exit 2 }
Write-Host "CRITERION 2 (TAMPER DETECTION): PASS" -ForegroundColor Green; exit 0
