# Criterion 3: MERKLE TREE CORRECTNESS
# The Merkle tree must be cryptographically sound.
$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$merkleScript = Join-Path $repoRoot 'tools\Merkle.ps1'
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "C3-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$fail = $false

function Pass($id,$m){ Write-Host "PASS [$id]: $m" -ForegroundColor Green }
function Fail($id,$m){ Write-Host "FAIL [$id]: $m" -ForegroundColor Red; $script:fail=$true }

function Hash-Pair([string]$a,[string]$b){
    $pair = [System.Text.Encoding]::UTF8.GetBytes($a + $b)
    (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($pair)) -Algorithm SHA256).Hash.ToLower()
}

function Write-TestCsv([string]$path, [string[]]$hashes){
    $lines = @('"Rel","SHA256"')
    for($i=0; $i -lt $hashes.Count; $i++){
        $lines += "`"file$i.txt`",`"$($hashes[$i])`""
    }
    $lines | Set-Content -Encoding UTF8 -Path $path
}

function Get-MerkleRoot([string]$csvPath){
    $dir = Split-Path -Parent $csvPath
    pwsh -NoProfile -File $merkleScript -CsvPath $csvPath
    return (Get-Content -Raw (Join-Path $dir 'merkle_root.txt')).Trim().ToLower()
}

# Fixed test hashes (64-char lowercase hex)
$hA = "a" * 64
$hB = "b" * 64
$hC = "c" * 64
$hD = "d" * 64

# =====================================================================
# M1: Single leaf — root == leaf hash
# =====================================================================
$csv1 = Join-Path $tmpDir 'm1.csv'
Write-TestCsv $csv1 @($hA)
$root1 = Get-MerkleRoot $csv1
if($root1 -eq $hA){ Pass "M1" "Single leaf: root equals leaf hash" }
else { Fail "M1" "Single leaf: expected $hA, got $root1" }

# =====================================================================
# M2: Two leaves — root == Hash(L0 + L1)
# =====================================================================
$csv2 = Join-Path $tmpDir 'm2.csv'
Write-TestCsv $csv2 @($hA, $hB)
$root2 = Get-MerkleRoot $csv2
$expected2 = Hash-Pair $hA $hB
if($root2 -eq $expected2){ Pass "M2" "Two leaves: root = Hash(L0+L1)" }
else { Fail "M2" "Two leaves: expected $expected2, got $root2" }

# =====================================================================
# M3: Odd leaves — padding must be deterministic
# Three leaves: [A, B, C] -> padded to [A, B, C, C]
# Level 1: [Hash(A+B), Hash(C+C)]
# Level 2: Hash(Hash(A+B) + Hash(C+C))
# =====================================================================
$csv3 = Join-Path $tmpDir 'm3.csv'
Write-TestCsv $csv3 @($hA, $hB, $hC)
$root3 = Get-MerkleRoot $csv3
$left3 = Hash-Pair $hA $hB
$right3 = Hash-Pair $hC $hC
$expected3 = Hash-Pair $left3 $right3
if($root3 -eq $expected3){ Pass "M3" "Odd leaves: padding is deterministic and correct" }
else { Fail "M3" "Odd leaves: expected $expected3, got $root3" }

# Run M3 again to confirm determinism
$csv3b = Join-Path $tmpDir 'm3b.csv'
Write-TestCsv $csv3b @($hA, $hB, $hC)
$root3b = Get-MerkleRoot $csv3b
if($root3 -eq $root3b){ Pass "M3" "Odd leaves: padding is deterministic across runs" }
else { Fail "M3" "Odd leaves: padding differs across runs: $root3 vs $root3b" }

# =====================================================================
# M4: Changing one leaf must change the root
# =====================================================================
$csv4a = Join-Path $tmpDir 'm4a.csv'
$csv4b = Join-Path $tmpDir 'm4b.csv'
Write-TestCsv $csv4a @($hA, $hB, $hC)
Write-TestCsv $csv4b @($hA, $hB, $hD)  # Changed C -> D
$root4a = Get-MerkleRoot $csv4a
$root4b = Get-MerkleRoot $csv4b
if($root4a -ne $root4b){ Pass "M4" "Changing one leaf changes the root" }
else { Fail "M4" "Changing leaf C->D did NOT change root (collision!)" }

# =====================================================================
# M5: Swapping two leaves must change the root (order matters)
# =====================================================================
$csv5a = Join-Path $tmpDir 'm5a.csv'
$csv5b = Join-Path $tmpDir 'm5b.csv'
Write-TestCsv $csv5a @($hA, $hB)
Write-TestCsv $csv5b @($hB, $hA)  # Swapped
$root5a = Get-MerkleRoot $csv5a
$root5b = Get-MerkleRoot $csv5b
if($root5a -ne $root5b){ Pass "M5" "Swapping two leaves changes the root (order-sensitive)" }
else { Fail "M5" "Swapping leaves A<->B did NOT change root — tree is order-insensitive!" }

# Cleanup
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

if($fail){ Write-Error "CRITERION 3 (MERKLE CORRECTNESS): FAILED"; exit 1 }
Write-Host "CRITERION 3 (MERKLE CORRECTNESS): PASS" -ForegroundColor Green; exit 0
