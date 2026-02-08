# Criterion 3: MERKLE TREE CORRECTNESS (RFC 6962)
# The Merkle tree must be cryptographically sound with domain separation.
# Uses in-process Build-MerkleTree directly (no subprocess overhead).
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$fail = $false

# Load shared crypto library
. (Join-Path $repoRoot 'lib\crypto.ps1')

function Pass($id,$m){ Write-Host "PASS [$id]: $m" -ForegroundColor Green }
function Fail($id,$m){ Write-Host "FAIL [$id]: $m" -ForegroundColor Red; $script:fail=$true }

# Fixed test hashes (64-char lowercase hex)
$hA = "a" * 64
$hB = "b" * 64
$hC = "c" * 64
$hD = "d" * 64

# =====================================================================
# M1: Single leaf — root == Get-MerkleLeafHash(leaf)
# With RFC 6962, root is NOT the raw leaf — it includes 0x00 prefix
# =====================================================================
$root1 = Build-MerkleTree @($hA)
$expected1 = Get-MerkleLeafHash $hA
if($root1 -eq $expected1){ Pass "M1" "Single leaf: root = Get-MerkleLeafHash(leaf) with domain separation" }
else { Fail "M1" "Single leaf: expected $expected1, got $root1" }

# =====================================================================
# M2: Two leaves — root = Hash-Internal(Hash-Leaf(L0), Hash-Leaf(L1))
# =====================================================================
$root2 = Build-MerkleTree @($hA, $hB)
$leafA = Get-MerkleLeafHash $hA
$leafB = Get-MerkleLeafHash $hB
$expected2 = Get-MerkleInternalHash $leafA $leafB
if($root2 -eq $expected2){ Pass "M2" "Two leaves: correct with domain separation" }
else { Fail "M2" "Two leaves: expected $expected2, got $root2" }

# =====================================================================
# M3: Odd leaves — padding must be deterministic
# =====================================================================
$root3 = Build-MerkleTree @($hA, $hB, $hC)
$lA = Get-MerkleLeafHash $hA
$lB = Get-MerkleLeafHash $hB
$lC = Get-MerkleLeafHash $hC
$left3 = Get-MerkleInternalHash $lA $lB
$right3 = Get-MerkleInternalHash $lC $lC
$expected3 = Get-MerkleInternalHash $left3 $right3
if($root3 -eq $expected3){ Pass "M3" "Odd leaves: padding is deterministic and correct" }
else { Fail "M3" "Odd leaves: expected $expected3, got $root3" }

# Run M3 again to confirm determinism
$root3b = Build-MerkleTree @($hA, $hB, $hC)
if($root3 -eq $root3b){ Pass "M3" "Odd leaves: padding is deterministic across runs" }
else { Fail "M3" "Odd leaves: padding differs across runs: $root3 vs $root3b" }

# =====================================================================
# M4: Changing one leaf must change the root
# =====================================================================
$root4a = Build-MerkleTree @($hA, $hB, $hC)
$root4b = Build-MerkleTree @($hA, $hB, $hD)  # Changed C -> D
if($root4a -ne $root4b){ Pass "M4" "Changing one leaf changes the root" }
else { Fail "M4" "Changing leaf C->D did NOT change root (collision!)" }

# =====================================================================
# M5: Swapping two leaves must change the root (order matters)
# =====================================================================
$root5a = Build-MerkleTree @($hA, $hB)
$root5b = Build-MerkleTree @($hB, $hA)  # Swapped
if($root5a -ne $root5b){ Pass "M5" "Swapping two leaves changes the root (order-sensitive)" }
else { Fail "M5" "Swapping leaves A<->B did NOT change root — tree is order-insensitive!" }

# =====================================================================
# M6: Domain separation — leaf != internal node hash
# This is the key RFC 6962 security property
# =====================================================================
$testData = "a" * 64
$leafResult = Get-MerkleLeafHash $testData
$internalResult = Get-MerkleInternalHash $testData $testData
if($leafResult -ne $internalResult){ Pass "M6" "Domain separation: leaf hash != internal hash (RFC 6962)" }
else { Fail "M6" "Domain separation FAILED: leaf hash == internal hash" }

# =====================================================================
# M7: Merkle.ps1 subprocess agrees with in-process Build-MerkleTree
# Cross-validates that the script and library produce identical results.
# =====================================================================
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "C3-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

$crossCsv = Join-Path $tmpDir 'cross.csv'
$crossLeaves = @($hA, $hB, $hC, $hD)
$lines = @('"Rel","SHA256"')
for($i=0; $i -lt $crossLeaves.Count; $i++){
    $lines += "`"file$i.txt`",`"$($crossLeaves[$i])`""
}
$lines | Set-Content -Encoding UTF8 -Path $crossCsv

$merkleScript = Join-Path $repoRoot 'tools\Merkle.ps1'
pwsh -NoProfile -File $merkleScript -CsvPath $crossCsv | Out-Null
$scriptRoot = (Get-Content -Raw (Join-Path $tmpDir 'merkle_root.txt')).Trim().ToLower()
$libRoot = Build-MerkleTree $crossLeaves

if($scriptRoot -eq $libRoot){
    Pass "M7" "Merkle.ps1 output matches Build-MerkleTree: $($libRoot.Substring(0,16))..."
} else {
    Fail "M7" "Merkle.ps1 ($scriptRoot) != Build-MerkleTree ($libRoot)"
}

Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

if($fail){ Write-Host "CRITERION 3 (MERKLE CORRECTNESS): FAILED" -ForegroundColor Red; exit 1 }
Write-Host "CRITERION 3 (MERKLE CORRECTNESS): PASS" -ForegroundColor Green; exit 0
