# Criterion 6: END-TO-END CHAIN OF CUSTODY
# The full pipeline must produce a verifiable, complete evidence chain.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "C6-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$fail = $false; $gap = $false

function Pass($id,$m){ Write-Host "PASS [$id]: $m" -ForegroundColor Green }
function Fail($id,$m){ Write-Host "FAIL [$id]: $m" -ForegroundColor Red; $script:fail=$true }
function Gap($id,$m){ Write-Host "KNOWN-GAP [$id]: $m" -ForegroundColor Yellow; $script:gap=$true }

$outDir    = Join-Path $tmpDir 'output'
$dodDir    = Join-Path $outDir 'DoD'
$demoScript   = Join-Path $repoRoot 'src\run_demo.ps1'
$merkleScript = Join-Path $repoRoot 'tools\Merkle.ps1'
$dodScript    = Join-Path $repoRoot 'tools\DoD.ps1'
$verifyScript = Join-Path $repoRoot 'tools\verify.ps1'

# =====================================================================
# E1: Full pipeline runs all steps without error
# =====================================================================
$manifestCsv = Join-Path $outDir 'manifest.csv'
$steps = @(
    @{ Name="run_demo"; Script=$demoScript; Args=@("-Out",$outDir) },
    @{ Name="Merkle";   Script=$merkleScript; Args=@("-CsvPath",$manifestCsv) },
    @{ Name="DoD";      Script=$dodScript; Args=@("-Out",$dodDir,"-Manifest",$manifestCsv) }
)

$pipelineFailed = $false
foreach($step in $steps){
    $errFile = Join-Path $tmpDir "e1-err-$($step.Name).txt"
    $stepArgString = ($step.Args | ForEach-Object { "`"$_`"" }) -join ' '
    $proc = Start-Process -FilePath pwsh -ArgumentList "-NoProfile -File `"$($step.Script)`" $stepArgString" `
            -Wait -PassThru -RedirectStandardError $errFile -NoNewWindow
    if($proc.ExitCode -ne 0){
        $stderr = if(Test-Path $errFile){ Get-Content -Raw $errFile } else { "" }
        Fail "E1" "Step '$($step.Name)' failed (exit $($proc.ExitCode)): $stderr"
        $pipelineFailed = $true
    } else {
        Pass "E1" "Step '$($step.Name)' completed successfully"
    }
}

if($pipelineFailed){
    Write-Host "CRITERION 6: Pipeline failed, cannot continue with remaining tests" -ForegroundColor Red
    exit 1
}

# =====================================================================
# E2: All output artifacts exist after pipeline run
# =====================================================================
$requiredArtifacts = @(
    @{ Path=(Join-Path $outDir 'manifest.csv'); Name="manifest.csv" },
    @{ Path=(Join-Path $outDir 'merkle_root.txt'); Name="merkle_root.txt" },
    @{ Path=(Join-Path $dodDir 'DoD.json'); Name="DoD.json" }
)

foreach($a in $requiredArtifacts){
    if(Test-Path $a.Path){
        $size = (Get-Item $a.Path).Length
        if($size -gt 0){ Pass "E2" "$($a.Name) exists ($size bytes)" }
        else { Fail "E2" "$($a.Name) exists but is empty (0 bytes)" }
    } else {
        Fail "E2" "$($a.Name) missing"
    }
}

# =====================================================================
# E3: verify.ps1 passes on fresh pipeline output
# =====================================================================
$dodJson = Join-Path $dodDir 'DoD.json'
$manifest = Join-Path $outDir 'manifest.csv'
$merkleRoot = Join-Path $outDir 'merkle_root.txt'

# Use wrapper script with *>&1 to capture all output streams (including Write-Host)
$wrapperPath = Join-Path $tmpDir "e3-wrapper.ps1"
$outVerify = Join-Path $tmpDir "e3-out.txt"
$errFile = Join-Path $tmpDir "e3-err.txt"
@"
`$PSNativeCommandUseErrorActionPreference = `$false
& '$verifyScript' -DoD '$dodJson' -Manifest '$manifest' -MerkleRoot '$merkleRoot' *>&1
exit `$LASTEXITCODE
"@ | Set-Content -Encoding UTF8 $wrapperPath
$proc = Start-Process -FilePath pwsh `
    -ArgumentList "-NoProfile -File `"$wrapperPath`"" `
    -Wait -PassThru -RedirectStandardOutput $outVerify -RedirectStandardError $errFile -NoNewWindow

if($proc.ExitCode -eq 0){ Pass "E3" "verify.ps1 passes on fresh pipeline output" }
else {
    # Show diagnostic output from verify.ps1
    if(Test-Path $outVerify){
        Write-Host "  --- verify.ps1 output (exit $($proc.ExitCode)) ---" -ForegroundColor DarkGray
        Get-Content $outVerify -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host "  VERIFY> $_" -ForegroundColor DarkGray
        }
    }
    Fail "E3" "verify.ps1 failed on fresh output (exit $($proc.ExitCode))"
}

# =====================================================================
# E4: DoD.json references correct Merkle root
# =====================================================================
$dod = Get-Content -Raw $dodJson | ConvertFrom-Json
$rootFromFile = (Get-Content -Raw $merkleRoot).Trim().ToLower()

if($dod.merkle_root){
    if($dod.merkle_root.ToLower() -eq $rootFromFile){
        Pass "E4" "DoD.json merkle_root matches merkle_root.txt"
    } else {
        Fail "E4" "DoD.json merkle_root ($($dod.merkle_root)) != merkle_root.txt ($rootFromFile)"
    }
} else {
    Fail "E4" "DoD.json has no merkle_root field"
}

# =====================================================================
# E5: Manifest hashes match actual files on disk
# =====================================================================
$rows = Import-Csv $manifest
$sampleRoot = Join-Path $repoRoot 'sample'
$hashMismatches = 0

foreach($r in $rows){
    $rel = $r.Rel -replace '\\','/'
    # Reconstruct the absolute path from the relative path
    $absPath = Join-Path $repoRoot $rel
    if(Test-Path $absPath){
        $diskHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $absPath).Hash.ToLower()
        $manifestHash = $r.SHA256.ToLower()
        if($diskHash -eq $manifestHash){
            Pass "E5" "File '$rel' hash matches manifest"
        } else {
            Fail "E5" "File '$rel' hash MISMATCH: disk=$diskHash manifest=$manifestHash"
            $hashMismatches++
        }
    } else {
        Fail "E5" "File '$rel' listed in manifest but NOT found on disk at $absPath"
        $hashMismatches++
    }
}

# Check reverse: files on disk not in manifest
$diskFiles = Get-ChildItem -Path $sampleRoot -Recurse -File
$manifestRels = @{}
foreach($r in $rows){ $manifestRels[($r.Rel -replace '\\','/')] = $true }

foreach($f in $diskFiles){
    $rel = $f.FullName.Replace((Resolve-Path $repoRoot).Path,'').TrimStart('\','/').Replace('\','/')
    if(-not $manifestRels.ContainsKey($rel)){
        Gap "E5" "File '$rel' exists on disk but NOT in manifest (untracked)"
    }
}

if($hashMismatches -eq 0 -and $rows.Count -gt 0){
    Pass "E5" "All $($rows.Count) manifest entries verified against disk"
}

# Cleanup
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

if($fail){ Write-Host "CRITERION 6 (END-TO-END): FAILED" -ForegroundColor Red; exit 1 }
if($gap){ Write-Host "CRITERION 6 (END-TO-END): KNOWN GAPS FOUND"; exit 2 }
Write-Host "CRITERION 6 (END-TO-END): PASS" -ForegroundColor Green; exit 0
