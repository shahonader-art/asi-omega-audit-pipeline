# Criterion 7: CRYPTOGRAPHIC STRESS TESTING
# In-process tests that validate security properties directly using the shared
# crypto library — no subprocess overhead, no JSON serialization issues.
# This is the definitive test of the pipeline's mathematical guarantees.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$fail = $false

# Load shared crypto library (single source of truth)
. (Join-Path $repoRoot 'lib\crypto.ps1')

function Pass($id,$m){ Write-Host "PASS [$id]: $m" -ForegroundColor Green }
function Fail($id,$m){ Write-Host "FAIL [$id]: $m" -ForegroundColor Red; $script:fail=$true }

# =====================================================================
# CS1: RFC 6962 Domain Separation — leaf != internal hash
# A leaf node MUST NOT be confusable with an internal node.
# This prevents second-preimage attacks on the Merkle tree.
# =====================================================================
$testInputs = @(("a" * 64), ("b" * 64), ("0" * 64), ("f" * 64), ("deadbeef" * 8))
$cs1Pass = $true
foreach($input in $testInputs){
    $leaf = Get-MerkleLeafHash $input
    $internal = Get-MerkleInternalHash $input $input
    if($leaf -eq $internal){
        Fail "CS1" "Domain separation broken for input '$($input.Substring(0,8))...': leaf=$leaf == internal=$internal"
        $cs1Pass = $false
    }
}
if($cs1Pass){ Pass "CS1" "Domain separation holds for all test inputs (leaf hash != internal hash)" }

# =====================================================================
# CS2: Bit-flip sensitivity — changing 1 bit in 1 leaf changes the root
# Tests avalanche property: a single-bit change must propagate to root.
# =====================================================================
$baseLeaves = @(("aa" * 32), ("bb" * 32), ("cc" * 32), ("dd" * 32))
$baseRoot = Build-MerkleTree $baseLeaves

# Flip one hex char in the first leaf (a→b)
$flippedLeaves = $baseLeaves.Clone()
$flippedLeaves[0] = "ba" + ("aa" * 31)
$flippedRoot = Build-MerkleTree $flippedLeaves

if($baseRoot -ne $flippedRoot){
    Pass "CS2" "Single-character change in leaf propagates to root"
} else {
    Fail "CS2" "Root unchanged after modifying leaf — avalanche property broken"
}

# Also test flipping the LAST leaf
$flippedLast = $baseLeaves.Clone()
$flippedLast[3] = "de" + ("dd" * 31)
$flippedLastRoot = Build-MerkleTree $flippedLast

if($baseRoot -ne $flippedLastRoot){
    Pass "CS2" "Single-character change in last leaf also propagates to root"
} else {
    Fail "CS2" "Root unchanged after modifying last leaf"
}

# =====================================================================
# CS3: Order sensitivity — swapping leaves must change the root
# The Merkle tree MUST be order-dependent for forensic integrity.
# =====================================================================
$ordered = @(("aa" * 32), ("bb" * 32), ("cc" * 32))
$swapped = @(("bb" * 32), ("aa" * 32), ("cc" * 32))

$orderedRoot = Build-MerkleTree $ordered
$swappedRoot = Build-MerkleTree $swapped

if($orderedRoot -ne $swappedRoot){
    Pass "CS3" "Swapping leaf order changes root (order-sensitive)"
} else {
    Fail "CS3" "Swapping leaves produced same root — tree is order-insensitive!"
}

# Test with more permutations
$perm1 = @(("aa" * 32), ("cc" * 32), ("bb" * 32))
$perm1Root = Build-MerkleTree $perm1
if($orderedRoot -ne $perm1Root -and $swappedRoot -ne $perm1Root){
    Pass "CS3" "Third permutation also produces unique root"
} else {
    Fail "CS3" "Permutation collision detected"
}

# =====================================================================
# CS4: Determinism — same inputs always produce same root
# Run Build-MerkleTree 10 times with identical input.
# =====================================================================
$detLeaves = @(("1111" * 16), ("2222" * 16), ("3333" * 16), ("4444" * 16), ("5555" * 16))
$roots = @()
for($i = 0; $i -lt 10; $i++){
    $roots += Build-MerkleTree $detLeaves
}
$uniqueRoots = ($roots | Select-Object -Unique).Count
if($uniqueRoots -eq 1){
    Pass "CS4" "Build-MerkleTree deterministic: 10 runs, 1 unique root"
} else {
    Fail "CS4" "Build-MerkleTree non-deterministic: $uniqueRoots unique roots from 10 runs"
}

# =====================================================================
# CS5: Scale test — tree with 100 leaves
# Verifies no stack overflow, memory issues, or incorrect padding at scale.
# =====================================================================
$largeLeaves = @()
for($i = 0; $i -lt 100; $i++){
    $hex = $i.ToString("x2")
    $largeLeaves += ($hex * 32)
}
try {
    $largeRoot = Build-MerkleTree $largeLeaves
    if($largeRoot -and $largeRoot.Length -eq 64){
        Pass "CS5" "100-leaf tree: root=$($largeRoot.Substring(0,16))... (64 hex chars)"
    } else {
        Fail "CS5" "100-leaf tree: invalid root (length=$($largeRoot.Length))"
    }

    # Verify determinism at scale
    $largeRoot2 = Build-MerkleTree $largeLeaves
    if($largeRoot -eq $largeRoot2){
        Pass "CS5" "100-leaf tree: deterministic across 2 runs"
    } else {
        Fail "CS5" "100-leaf tree: non-deterministic"
    }
} catch {
    Fail "CS5" "100-leaf tree threw exception: $_"
}

# =====================================================================
# CS6: Single leaf — root must equal leaf hash (with domain separation)
# =====================================================================
$singleInput = "abcdef01" * 8
$singleRoot = Build-MerkleTree @($singleInput)
$expectedLeafHash = Get-MerkleLeafHash $singleInput

if($singleRoot -eq $expectedLeafHash){
    Pass "CS6" "Single-leaf tree: root == Get-MerkleLeafHash(leaf)"
} else {
    Fail "CS6" "Single-leaf tree: root=$singleRoot expected=$expectedLeafHash"
}

# Root must NOT be the raw input (domain separation)
if($singleRoot -ne $singleInput){
    Pass "CS6" "Single-leaf root differs from raw input (domain separation applied)"
} else {
    Fail "CS6" "Single-leaf root equals raw input — 0x00 prefix not applied"
}

# =====================================================================
# CS7: Two-leaf manual verification
# Root = Hash-Internal(Hash-Leaf(L0), Hash-Leaf(L1))
# =====================================================================
$l0 = "aa" * 32
$l1 = "bb" * 32
$twoRoot = Build-MerkleTree @($l0, $l1)
$expectedTwo = Get-MerkleInternalHash (Get-MerkleLeafHash $l0) (Get-MerkleLeafHash $l1)

if($twoRoot -eq $expectedTwo){
    Pass "CS7" "Two-leaf tree matches manual computation"
} else {
    Fail "CS7" "Two-leaf tree: root=$twoRoot expected=$expectedTwo"
}

# =====================================================================
# CS8: Odd-leaf padding — 3 leaves must duplicate last leaf for padding
# Tree: [H(L0,L1), H(L2,L2)] -> root
# =====================================================================
$l2 = "cc" * 32
$threeRoot = Build-MerkleTree @($l0, $l1, $l2)
$hl0 = Get-MerkleLeafHash $l0
$hl1 = Get-MerkleLeafHash $l1
$hl2 = Get-MerkleLeafHash $l2
$left = Get-MerkleInternalHash $hl0 $hl1
$right = Get-MerkleInternalHash $hl2 $hl2  # Duplicated last
$expectedThree = Get-MerkleInternalHash $left $right

if($threeRoot -eq $expectedThree){
    Pass "CS8" "3-leaf tree: padding correctly duplicates last leaf"
} else {
    Fail "CS8" "3-leaf tree: root=$threeRoot expected=$expectedThree"
}

# =====================================================================
# CS9: Empty tree must throw an error
# =====================================================================
$cs9Pass = $false
try {
    Build-MerkleTree @()
    Fail "CS9" "Empty tree did not throw — should reject empty leaf set"
} catch {
    if("$_" -match "empty"){
        Pass "CS9" "Empty tree throws descriptive error: $_"
        $cs9Pass = $true
    } else {
        Pass "CS9" "Empty tree throws error (non-descriptive): $_"
        $cs9Pass = $true
    }
}

# =====================================================================
# CS10: Hash function output properties
# All hash functions must return lowercase 64-char hex strings.
# =====================================================================
$testStr = "test input for hash validation"
$testFile = Join-Path ([System.IO.Path]::GetTempPath()) "cs10-test-$([guid]::NewGuid().ToString('N').Substring(0,8)).txt"
$testStr | Set-Content -Encoding UTF8 $testFile

$hashes = @{
    "Get-Sha256Hash"       = (Get-Sha256Hash $testStr)
    "Get-Sha256FileHash"   = (Get-Sha256FileHash $testFile)
    "Get-MerkleLeafHash"   = (Get-MerkleLeafHash $testStr)
    "Get-MerkleInternalHash" = (Get-MerkleInternalHash ("a"*64) ("b"*64))
}

Remove-Item $testFile -ErrorAction SilentlyContinue

$cs10Pass = $true
foreach($fn in $hashes.Keys){
    $h = $hashes[$fn]
    if($h.Length -ne 64){
        Fail "CS10" "$fn returned $($h.Length)-char string (expected 64)"
        $cs10Pass = $false
    } elseif($h -cne $h.ToLower()){
        Fail "CS10" "$fn returned uppercase characters (must be lowercase)"
        $cs10Pass = $false
    } elseif($h -notmatch '^[0-9a-f]{64}$'){
        Fail "CS10" "$fn returned non-hex characters"
        $cs10Pass = $false
    }
}
if($cs10Pass){ Pass "CS10" "All hash functions return lowercase 64-char hex" }

# =====================================================================
# CS11: File hash matches string hash of file contents
# Get-Sha256FileHash(file) must equal Get-Sha256Hash(content) for UTF-8 text.
# =====================================================================
$cs11File = Join-Path ([System.IO.Path]::GetTempPath()) "cs11-$([guid]::NewGuid().ToString('N').Substring(0,8)).txt"
$cs11Content = "known content for cross-check"
[System.IO.File]::WriteAllBytes($cs11File, [System.Text.Encoding]::UTF8.GetBytes($cs11Content))

$fileHash = Get-Sha256FileHash $cs11File
$strHash  = Get-Sha256Hash $cs11Content

Remove-Item $cs11File -ErrorAction SilentlyContinue

if($fileHash -eq $strHash){
    Pass "CS11" "File hash matches string hash for same UTF-8 content"
} else {
    Fail "CS11" "File hash ($fileHash) != string hash ($strHash) — encoding mismatch"
}

# =====================================================================
# CS12: End-to-end in-process pipeline verification
# Simulates the full manifest → Merkle → verify chain using only the
# shared library, with no subprocesses.
# =====================================================================
$sampleDir = Join-Path $repoRoot 'sample'
if(Test-Path $sampleDir){
    # Step 1: Build manifest in-process (same logic as run_demo.ps1)
    $files = Get-ChildItem -Path $sampleDir -Recurse -File | Sort-Object { $_.FullName.Replace('\','/') }
    $manifestHashes = @()
    $manifestEntries = @()
    foreach($f in $files){
        $h = Get-Sha256FileHash $f.FullName
        $rel = $f.FullName.Replace((Resolve-Path $repoRoot).Path,'').TrimStart('\','/').Replace('\','/')
        $manifestHashes += $h
        $manifestEntries += @{ Rel=$rel; SHA256=$h }
    }

    # Step 2: Build Merkle tree in-process
    $root = Build-MerkleTree $manifestHashes

    if($root -and $root.Length -eq 64){
        Pass "CS12" "In-process pipeline: $($files.Count) files -> Merkle root $($root.Substring(0,16))..."
    } else {
        Fail "CS12" "In-process pipeline: invalid root"
    }

    # Step 3: Verify — recompute and compare
    $verifyRoot = Build-MerkleTree $manifestHashes
    if($verifyRoot -eq $root){
        Pass "CS12" "In-process verify: recomputed root matches"
    } else {
        Fail "CS12" "In-process verify: recomputed root MISMATCH"
    }

    # Step 4: Verify each file hash matches disk
    $diskVerifyPass = $true
    foreach($entry in $manifestEntries){
        $absPath = Join-Path $repoRoot $entry.Rel
        if(Test-Path $absPath){
            $diskHash = Get-Sha256FileHash $absPath
            if($diskHash -ne $entry.SHA256){
                Fail "CS12" "Disk verify: $($entry.Rel) hash mismatch"
                $diskVerifyPass = $false
            }
        } else {
            Fail "CS12" "Disk verify: $($entry.Rel) missing"
            $diskVerifyPass = $false
        }
    }
    if($diskVerifyPass){
        Pass "CS12" "In-process disk verify: all $($manifestEntries.Count) files match"
    }

    # Step 5: Tamper detection — modify a hash and verify root changes
    $tamperedHashes = $manifestHashes.Clone()
    if($tamperedHashes.Count -gt 0){
        $orig = $tamperedHashes[0]
        $tamperedHashes[0] = "0000000000000000000000000000000000000000000000000000000000000000"
        $tamperedRoot = Build-MerkleTree $tamperedHashes
        if($tamperedRoot -ne $root){
            Pass "CS12" "Tamper detected: modified hash changes root"
        } else {
            Fail "CS12" "Tamper NOT detected: modified hash produced same root"
        }
    }
} else {
    Fail "CS12" "sample/ directory not found — cannot run end-to-end test"
}

# =====================================================================
# CS13: Uniqueness — all leaf hashes for different inputs must differ
# =====================================================================
$uniqueInputs = @()
for($i = 0; $i -lt 50; $i++){
    $uniqueInputs += $i.ToString("x2") * 32
}
$leafHashes = @()
foreach($inp in $uniqueInputs){
    $leafHashes += Get-MerkleLeafHash $inp
}
$uniqueLeafHashes = ($leafHashes | Select-Object -Unique).Count
if($uniqueLeafHashes -eq 50){
    Pass "CS13" "50 distinct inputs -> 50 distinct leaf hashes (no collisions)"
} else {
    Fail "CS13" "50 inputs produced only $uniqueLeafHashes unique leaf hashes — collision detected!"
}

# Summary
Write-Host ""
if($fail){
    Write-Host "CRITERION 7 (CRYPTO STRESS): FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "CRITERION 7 (CRYPTO STRESS): PASS" -ForegroundColor Green
exit 0
