# Criterion 1: DETERMINISM
# Same inputs MUST produce byte-identical outputs, every time.
$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$demoScript = Join-Path $repoRoot 'src\run_demo.ps1'
$merkleScript = Join-Path $repoRoot 'tools\Merkle.ps1'
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "C1-$([guid]::NewGuid().ToString('N').Substring(0,8))"
$fail = $false; $gap = $false

function Pass($id,$m){ Write-Host "PASS [$id]: $m" -ForegroundColor Green }
function Fail($id,$m){ Write-Host "FAIL [$id]: $m" -ForegroundColor Red; $script:fail=$true }
function Gap($id,$m){ Write-Host "KNOWN-GAP [$id]: $m" -ForegroundColor Yellow; $script:gap=$true }

# Run the pipeline 3 times into separate directories
$runs = @()
for($i=1; $i -le 3; $i++){
    $outDir = Join-Path $tmpDir "run$i"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    pwsh -NoProfile -File $demoScript -Out $outDir
    pwsh -NoProfile -File $merkleScript -CsvPath (Join-Path $outDir 'manifest.csv')
    $runs += $outDir
}

# =====================================================================
# D1: Manifest row order must be stable across runs
# =====================================================================
$csvs = $runs | ForEach-Object { Get-Content -Raw (Join-Path $_ 'manifest.csv') }
$allIdentical = ($csvs | Select-Object -Unique).Count -eq 1
if($allIdentical){
    Pass "D1" "manifest.csv byte-identical across 3 runs"
} else {
    # Check if content is same but order differs
    $rows = $runs | ForEach-Object {
        $r = Import-Csv (Join-Path $_ 'manifest.csv')
        ($r | ForEach-Object { $_.SHA256 }) -join ','
    }
    $hashSetsEqual = ($rows | ForEach-Object { ($_ -split ',' | Sort-Object) -join ',' } | Select-Object -Unique).Count -eq 1
    if($hashSetsEqual){
        Gap "D1" "manifest.csv has same hashes but DIFFERENT ROW ORDER across runs (non-deterministic)"
    } else {
        Fail "D1" "manifest.csv has different content across runs"
    }
}

# =====================================================================
# D2: Merkle root must be identical for identical manifests
# =====================================================================
$roots = $runs | ForEach-Object { (Get-Content -Raw (Join-Path $_ 'merkle_root.txt')).Trim() }
$rootsIdentical = ($roots | Select-Object -Unique).Count -eq 1
if($rootsIdentical){
    Pass "D2" "merkle_root.txt identical across 3 runs"
} else {
    if($allIdentical){
        Fail "D2" "Merkle roots differ despite identical manifests: $($roots -join ' vs ')"
    } else {
        Gap "D2" "Merkle roots differ because manifest order is non-deterministic"
    }
}

# =====================================================================
# D3: File ordering must use explicit sort (not filesystem order)
# =====================================================================
# Read the source code and check for Sort-Object
$demoSrc = Get-Content -Raw $demoScript
if($demoSrc -match 'Sort-Object|Sort\b|\| sort\b'){
    Pass "D3" "run_demo.ps1 explicitly sorts files"
} else {
    Gap "D3" "run_demo.ps1 does NOT sort files — relies on filesystem order (Get-ChildItem)"
}

# Cleanup
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

if($fail){ Write-Error "CRITERION 1 (DETERMINISM): FAILED"; exit 1 }
if($gap){ Write-Host "CRITERION 1 (DETERMINISM): KNOWN GAPS FOUND"; exit 2 }
Write-Host "CRITERION 1 (DETERMINISM): PASS" -ForegroundColor Green; exit 0
