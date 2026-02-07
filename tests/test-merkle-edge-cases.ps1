$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$fail = $false

# Load shared crypto library — all tests use in-process calls (no subprocess)
. (Join-Path $repoRoot 'lib\crypto.ps1')

function Pass($m){ Write-Host "OK: $m" -ForegroundColor Green }
function Fail($m){ Write-Host "FAIL: $m" -ForegroundColor Red; $script:fail=$true }

# ======================================================================
# Test 1: Single leaf — root = Get-MerkleLeafHash(hash)
# With RFC 6962: root = SHA-256(0x00 || leaf)
# ======================================================================
$h1 = "aaaa" * 16  # 64-char fake hash
$root1 = Build-MerkleTree @($h1)
$expected1 = Get-MerkleLeafHash $h1
if($root1 -eq $expected1){ Pass "Single leaf: root == Get-MerkleLeafHash(leaf)" }
else { Fail "Single leaf: expected $expected1, got $root1" }

# ======================================================================
# Test 2: Two leaves — root = Get-MerkleInternalHash(Leaf0, Leaf1)
# ======================================================================
$h2a = "bbbb" * 16
$h2b = "cccc" * 16
$root2 = Build-MerkleTree @($h2a, $h2b)
$leaf2a = Get-MerkleLeafHash $h2a
$leaf2b = Get-MerkleLeafHash $h2b
$expected2 = Get-MerkleInternalHash $leaf2a $leaf2b
if($root2 -eq $expected2){ Pass "Two leaves: root = Get-MerkleInternalHash(Leaf0, Leaf1)" }
else { Fail "Two leaves: expected $expected2, got $root2" }

# ======================================================================
# Test 3: Three leaves (odd count) — tests duplicate-last-leaf padding
# Leaves: [Get-MerkleLeafHash(L0), Get-MerkleLeafHash(L1), Get-MerkleLeafHash(L2)]
# Padded: [HL0, HL1, HL2, HL2]
# Level 1: [Get-MerkleInternalHash(HL0,HL1), Get-MerkleInternalHash(HL2,HL2)]
# Level 2: Get-MerkleInternalHash(left, right)
# ======================================================================
$h3a = "1111" * 16
$h3b = "2222" * 16
$h3c = "3333" * 16
$root3 = Build-MerkleTree @($h3a, $h3b, $h3c)
$leaf3a = Get-MerkleLeafHash $h3a
$leaf3b = Get-MerkleLeafHash $h3b
$leaf3c = Get-MerkleLeafHash $h3c
$left3  = Get-MerkleInternalHash $leaf3a $leaf3b
$right3 = Get-MerkleInternalHash $leaf3c $leaf3c  # duplicated last
$expected3 = Get-MerkleInternalHash $left3 $right3
if($root3 -eq $expected3){ Pass "Three leaves (odd): padding correct" }
else { Fail "Three leaves: expected $expected3, got $root3" }

# ======================================================================
# Test 4: Four leaves — balanced tree, no padding needed
# ======================================================================
$h4a = "aaaa" * 16
$h4b = "bbbb" * 16
$h4c = "cccc" * 16
$h4d = "dddd" * 16
$root4 = Build-MerkleTree @($h4a, $h4b, $h4c, $h4d)
$leaf4a = Get-MerkleLeafHash $h4a
$leaf4b = Get-MerkleLeafHash $h4b
$leaf4c = Get-MerkleLeafHash $h4c
$leaf4d = Get-MerkleLeafHash $h4d
$left4  = Get-MerkleInternalHash $leaf4a $leaf4b
$right4 = Get-MerkleInternalHash $leaf4c $leaf4d
$expected4 = Get-MerkleInternalHash $left4 $right4
if($root4 -eq $expected4){ Pass "Four leaves: balanced tree correct" }
else { Fail "Four leaves: expected $expected4, got $root4" }

# ======================================================================
# Test 5: Five leaves (odd) — verifies multi-level padding
# ======================================================================
$h5 = @("1111","2222","3333","4444","5555") | ForEach-Object { $_ * 16 }
$root5 = Build-MerkleTree $h5
$leafs5 = @()
foreach($h in $h5){ $leafs5 += (Get-MerkleLeafHash $h) }
$p01 = Get-MerkleInternalHash $leafs5[0] $leafs5[1]
$p23 = Get-MerkleInternalHash $leafs5[2] $leafs5[3]
$p44 = Get-MerkleInternalHash $leafs5[4] $leafs5[4]  # duplicated last
$q0 = Get-MerkleInternalHash $p01 $p23
$q1 = Get-MerkleInternalHash $p44 $p44
$expected5 = Get-MerkleInternalHash $q0 $q1
if($root5 -eq $expected5){ Pass "Five leaves: multi-level padding correct" }
else { Fail "Five leaves: expected $expected5, got $root5" }

# ======================================================================
# Test 6: Domain separation — leaf hash != raw hash
# This is the key security property: a leaf node cannot be confused
# with an internal node
# ======================================================================
$rawHash = "aaaa" * 16
$leafHash = Get-MerkleLeafHash $rawHash
# Compute what an old (non-RFC 6962) implementation would produce
$oldBytes = [System.Text.Encoding]::UTF8.GetBytes($rawHash)
$oldHash = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($oldBytes)) -Algorithm SHA256).Hash.ToLower()
if($leafHash -ne $rawHash -and $leafHash -ne $oldHash){
    Pass "Domain separation: leaf hash differs from raw hash"
} else {
    Fail "Domain separation: leaf hash should NOT equal raw hash"
}

if($fail){ Write-Host "MERKLE EDGE-CASE TESTS FAILED" -ForegroundColor Red; exit 1 }
Write-Host "MERKLE EDGE-CASE TESTS PASS" -ForegroundColor Green
exit 0
