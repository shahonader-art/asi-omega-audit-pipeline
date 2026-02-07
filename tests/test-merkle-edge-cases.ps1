$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$merkleScript = Join-Path $repoRoot 'tools\Merkle.ps1'
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "merkle-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$fail = $false

# Load shared crypto library
. (Join-Path $repoRoot 'lib\crypto.ps1')

function Pass($m){ Write-Host "OK: $m" -ForegroundColor Green }
function Fail($m){ Write-Host "FAIL: $m" -ForegroundColor Red; $script:fail=$true }

# Aliases for test readability (delegate to shared library)
function Hash-Leaf([string]$data){ return Get-MerkleLeafHash $data }
function Hash-Internal([string]$a, [string]$b){ return Get-MerkleInternalHash $a $b }

# Helper: write a CSV with given hashes
function Write-TestCsv([string]$path, [string[]]$hashes){
    $lines = @('"Rel","SHA256"')
    for($i=0; $i -lt $hashes.Count; $i++){
        $lines += "`"file$i.txt`",`"$($hashes[$i])`""
    }
    $lines | Set-Content -Encoding UTF8 -Path $path
}

# ======================================================================
# Test 1: Single leaf — root = Hash-Leaf(hash)
# With RFC 6962: root = SHA-256(0x00 || leaf)
# ======================================================================
$csv1 = Join-Path $tmpDir 'single.csv'
$h1 = "aaaa" * 16  # 64-char fake hash
Write-TestCsv $csv1 @($h1)
pwsh -NoProfile -File $merkleScript -CsvPath $csv1
$root1 = (Get-Content -Raw (Join-Path $tmpDir 'merkle_root.txt')).Trim().ToLower()
$expected1 = Hash-Leaf $h1
if($root1 -eq $expected1){ Pass "Single leaf: root == Hash-Leaf(leaf)" }
else { Fail "Single leaf: expected $expected1, got $root1" }

# ======================================================================
# Test 2: Two leaves — root = Hash-Internal(Hash-Leaf(L0), Hash-Leaf(L1))
# ======================================================================
$csv2 = Join-Path $tmpDir 'two.csv'
$h2a = "bbbb" * 16
$h2b = "cccc" * 16
Write-TestCsv $csv2 @($h2a, $h2b)
pwsh -NoProfile -File $merkleScript -CsvPath $csv2
$root2 = (Get-Content -Raw (Join-Path $tmpDir 'merkle_root.txt')).Trim().ToLower()
$leaf2a = Hash-Leaf $h2a
$leaf2b = Hash-Leaf $h2b
$expected2 = Hash-Internal $leaf2a $leaf2b
if($root2 -eq $expected2){ Pass "Two leaves: root = Hash-Internal(Leaf0, Leaf1)" }
else { Fail "Two leaves: expected $expected2, got $root2" }

# ======================================================================
# Test 3: Three leaves (odd count) — tests duplicate-last-leaf padding
# Leaves: [Hash-Leaf(L0), Hash-Leaf(L1), Hash-Leaf(L2)]
# Padded: [HL0, HL1, HL2, HL2]
# Level 1: [Hash-Internal(HL0,HL1), Hash-Internal(HL2,HL2)]
# Level 2: Hash-Internal(left, right)
# ======================================================================
$csv3 = Join-Path $tmpDir 'three.csv'
$h3a = "1111" * 16
$h3b = "2222" * 16
$h3c = "3333" * 16
Write-TestCsv $csv3 @($h3a, $h3b, $h3c)
pwsh -NoProfile -File $merkleScript -CsvPath $csv3
$root3 = (Get-Content -Raw (Join-Path $tmpDir 'merkle_root.txt')).Trim().ToLower()
$leaf3a = Hash-Leaf $h3a
$leaf3b = Hash-Leaf $h3b
$leaf3c = Hash-Leaf $h3c
$left3  = Hash-Internal $leaf3a $leaf3b
$right3 = Hash-Internal $leaf3c $leaf3c  # duplicated last
$expected3 = Hash-Internal $left3 $right3
if($root3 -eq $expected3){ Pass "Three leaves (odd): padding correct" }
else { Fail "Three leaves: expected $expected3, got $root3" }

# ======================================================================
# Test 4: Four leaves — balanced tree, no padding needed
# ======================================================================
$csv4 = Join-Path $tmpDir 'four.csv'
$h4a = "aaaa" * 16
$h4b = "bbbb" * 16
$h4c = "cccc" * 16
$h4d = "dddd" * 16
Write-TestCsv $csv4 @($h4a, $h4b, $h4c, $h4d)
pwsh -NoProfile -File $merkleScript -CsvPath $csv4
$root4 = (Get-Content -Raw (Join-Path $tmpDir 'merkle_root.txt')).Trim().ToLower()
$leaf4a = Hash-Leaf $h4a
$leaf4b = Hash-Leaf $h4b
$leaf4c = Hash-Leaf $h4c
$leaf4d = Hash-Leaf $h4d
$left4  = Hash-Internal $leaf4a $leaf4b
$right4 = Hash-Internal $leaf4c $leaf4d
$expected4 = Hash-Internal $left4 $right4
if($root4 -eq $expected4){ Pass "Four leaves: balanced tree correct" }
else { Fail "Four leaves: expected $expected4, got $root4" }

# ======================================================================
# Test 5: Five leaves (odd) — verifies multi-level padding
# ======================================================================
$csv5 = Join-Path $tmpDir 'five.csv'
$h5 = @("1111","2222","3333","4444","5555") | ForEach-Object { $_ * 16 }
Write-TestCsv $csv5 $h5
pwsh -NoProfile -File $merkleScript -CsvPath $csv5
$root5 = (Get-Content -Raw (Join-Path $tmpDir 'merkle_root.txt')).Trim().ToLower()
$leafs5 = @()
foreach($h in $h5){ $leafs5 += (Hash-Leaf $h) }
$p01 = Hash-Internal $leafs5[0] $leafs5[1]
$p23 = Hash-Internal $leafs5[2] $leafs5[3]
$p44 = Hash-Internal $leafs5[4] $leafs5[4]  # duplicated last
$q0 = Hash-Internal $p01 $p23
$q1 = Hash-Internal $p44 $p44
$expected5 = Hash-Internal $q0 $q1
if($root5 -eq $expected5){ Pass "Five leaves: multi-level padding correct" }
else { Fail "Five leaves: expected $expected5, got $root5" }

# ======================================================================
# Test 6: Domain separation — leaf hash != raw hash
# This is the key security property: a leaf node cannot be confused
# with an internal node
# ======================================================================
$rawHash = "aaaa" * 16
$leafHash = Hash-Leaf $rawHash
# Compute what an old (non-RFC 6962) implementation would produce
$oldBytes = [System.Text.Encoding]::UTF8.GetBytes($rawHash)
$oldHash = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($oldBytes)) -Algorithm SHA256).Hash.ToLower()
if($leafHash -ne $rawHash -and $leafHash -ne $oldHash){
    Pass "Domain separation: leaf hash differs from raw hash"
} else {
    Fail "Domain separation: leaf hash should NOT equal raw hash"
}

# Cleanup
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

if($fail){ Write-Host "MERKLE EDGE-CASE TESTS FAILED" -ForegroundColor Red; exit 1 }
Write-Host "MERKLE EDGE-CASE TESTS PASS" -ForegroundColor Green
exit 0
