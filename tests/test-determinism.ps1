$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "det-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
$fail = $false

function Pass($m){ Write-Host "OK: $m" -ForegroundColor Green }
function Fail($m){ Write-Host "FAIL: $m" -ForegroundColor Red; $script:fail=$true }

# =====================================================================
# Test 1: run_demo.ps1 produces identical manifest.csv across two runs
# =====================================================================
$outA = Join-Path $tmpDir 'run_a'
$outB = Join-Path $tmpDir 'run_b'
New-Item -ItemType Directory -Force -Path $outA | Out-Null
New-Item -ItemType Directory -Force -Path $outB | Out-Null

$demoScript = Join-Path $repoRoot 'src\run_demo.ps1'
pwsh -NoProfile -File $demoScript -Out $outA
pwsh -NoProfile -File $demoScript -Out $outB

$csvA = Get-Content -Raw (Join-Path $outA 'manifest.csv')
$csvB = Get-Content -Raw (Join-Path $outB 'manifest.csv')

if($csvA -eq $csvB){ Pass "run_demo: identical manifest.csv across two runs" }
else { Fail "run_demo: manifest.csv differs between runs" }

# =====================================================================
# Test 2: Merkle.ps1 produces identical merkle_root.txt across two runs
# =====================================================================
$merkleScript = Join-Path $repoRoot 'tools\Merkle.ps1'

# Copy manifests to separate dirs for independent Merkle runs
$merkleA = Join-Path $tmpDir 'merkle_a'
$merkleB = Join-Path $tmpDir 'merkle_b'
New-Item -ItemType Directory -Force -Path $merkleA | Out-Null
New-Item -ItemType Directory -Force -Path $merkleB | Out-Null
Copy-Item (Join-Path $outA 'manifest.csv') (Join-Path $merkleA 'manifest.csv')
Copy-Item (Join-Path $outB 'manifest.csv') (Join-Path $merkleB 'manifest.csv')

pwsh -NoProfile -File $merkleScript -CsvPath (Join-Path $merkleA 'manifest.csv')
pwsh -NoProfile -File $merkleScript -CsvPath (Join-Path $merkleB 'manifest.csv')

$rootA = (Get-Content -Raw (Join-Path $merkleA 'merkle_root.txt')).Trim()
$rootB = (Get-Content -Raw (Join-Path $merkleB 'merkle_root.txt')).Trim()

if($rootA -eq $rootB){ Pass "Merkle: identical root across two runs" }
else { Fail "Merkle: root differs between runs: $rootA vs $rootB" }

# =====================================================================
# Test 3: File ordering in manifest is stable (sorted consistently)
# =====================================================================
$rowsA = Import-Csv -Path (Join-Path $outA 'manifest.csv')
$rowsB = Import-Csv -Path (Join-Path $outB 'manifest.csv')

$orderA = ($rowsA | ForEach-Object { $_.Rel }) -join ','
$orderB = ($rowsB | ForEach-Object { $_.Rel }) -join ','

if($orderA -eq $orderB){ Pass "Manifest: file order is stable across runs" }
else { Fail "Manifest: file order differs: '$orderA' vs '$orderB'" }

# =====================================================================
# Test 4: SHA-256 hashes match known golden values
# =====================================================================
$goldenPath = Join-Path $repoRoot 'docs\golden-hashes.json'
if(Test-Path $goldenPath){
    $golden = Get-Content -Raw $goldenPath | ConvertFrom-Json
    foreach($r in $rowsA){
        $rel = ($r.Rel -replace '\\','/')
        $goldenHash = $golden.files.$rel
        if($goldenHash){
            $got = $r.SHA256.ToLower()
            $need = $goldenHash.ToLower()
            if($got -eq $need){ Pass "Golden match: $rel" }
            else { Fail "Golden mismatch: $rel expected=$need got=$got" }
        }
    }
} else {
    Write-Host "SKIP: golden-hashes.json not found" -ForegroundColor Yellow
}

# =====================================================================
# Test 5: Merkle root is deterministic from known hashes
# =====================================================================
if($rowsA.Count -ge 2){
    # Recompute merkle root manually with RFC 6962 domain separation
    function Hash-Leaf([string]$data){
        $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($data)
        $prefixed = [byte[]]::new(1 + $dataBytes.Length)
        $prefixed[0] = 0x00
        [Array]::Copy($dataBytes, 0, $prefixed, 1, $dataBytes.Length)
        return (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($prefixed)) -Algorithm SHA256).Hash.ToLower()
    }
    function Combine([string]$a,[string]$b){
        $pairBytes=[System.Text.Encoding]::UTF8.GetBytes($a+$b)
        $prefixed = [byte[]]::new(1 + $pairBytes.Length)
        $prefixed[0] = 0x01
        [Array]::Copy($pairBytes, 0, $prefixed, 1, $pairBytes.Length)
        return (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($prefixed)) -Algorithm SHA256).Hash.ToLower()
    }
    $level=[System.Collections.Generic.List[string]]::new()
    foreach($r in $rowsA){ [void]$level.Add((Hash-Leaf $r.SHA256.ToLower())) }
    while($level.Count -gt 1){
        if($level.Count % 2 -ne 0){ $level.Add($level[$level.Count-1]) }
        $next=[System.Collections.Generic.List[string]]::new()
        for($i=0;$i -lt $level.Count;$i+=2){ $next.Add((Combine $level[$i] $level[$i+1])) }
        $level=$next
    }
    if($level[0] -eq $rootA){ Pass "Merkle root matches manual recomputation (RFC 6962)" }
    else { Fail "Merkle root mismatch: script=$rootA manual=$($level[0])" }
}

# Cleanup
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

if($fail){ Write-Error "DETERMINISM TESTS FAILED"; exit 1 }
Write-Host "DETERMINISM TESTS PASS" -ForegroundColor Green
exit 0
