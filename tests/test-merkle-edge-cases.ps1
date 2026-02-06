$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$merkleScript = Join-Path $repoRoot 'tools\Merkle.ps1'
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "merkle-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$fail = $false

function Pass($m){ Write-Host "OK: $m" -ForegroundColor Green }
function Fail($m){ Write-Host "FAIL: $m" -ForegroundColor Red; $script:fail=$true }

# Helper: compute SHA-256 of a string (same logic as Merkle.ps1's Combine-Hash)
function Hash-String([string]$s){
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($s)
    return (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($bytes)) -Algorithm SHA256).Hash.ToLower()
}

# Helper: write a CSV with given hashes
function Write-TestCsv([string]$path, [string[]]$hashes){
    $lines = @('"Rel","SHA256"')
    for($i=0; $i -lt $hashes.Count; $i++){
        $lines += "`"file$i.txt`",`"$($hashes[$i])`""
    }
    $lines | Set-Content -Encoding UTF8 -Path $path
}

# ======================================================================
# Test 1: Single leaf — root should equal the leaf hash itself
# ======================================================================
$csv1 = Join-Path $tmpDir 'single.csv'
$h1 = "aaaa" * 16  # 64-char fake hash
Write-TestCsv $csv1 @($h1)
pwsh -NoProfile -File $merkleScript -CsvPath $csv1
$root1 = (Get-Content -Raw (Join-Path $tmpDir 'merkle_root.txt')).Trim().ToLower()
if($root1 -eq $h1){ Pass "Single leaf: root == leaf" }
else { Fail "Single leaf: expected $h1, got $root1" }

# ======================================================================
# Test 2: Two leaves — root = Hash(leaf0 + leaf1)
# ======================================================================
$csv2 = Join-Path $tmpDir 'two.csv'
$h2a = "bbbb" * 16
$h2b = "cccc" * 16
Write-TestCsv $csv2 @($h2a, $h2b)
pwsh -NoProfile -File $merkleScript -CsvPath $csv2
$root2 = (Get-Content -Raw (Join-Path $tmpDir 'merkle_root.txt')).Trim().ToLower()
$expected2 = Hash-String ($h2a + $h2b)
if($root2 -eq $expected2){ Pass "Two leaves: root = Hash(L0+L1)" }
else { Fail "Two leaves: expected $expected2, got $root2" }

# ======================================================================
# Test 3: Three leaves (odd count) — tests duplicate-last-leaf padding
# Per algorithm: [L0, L1, L2] -> pad -> [L0, L1, L2, L2]
# Level 1: [Hash(L0+L1), Hash(L2+L2)]
# Level 2: Hash( Hash(L0+L1) + Hash(L2+L2) )
# ======================================================================
$csv3 = Join-Path $tmpDir 'three.csv'
$h3a = "1111" * 16
$h3b = "2222" * 16
$h3c = "3333" * 16
Write-TestCsv $csv3 @($h3a, $h3b, $h3c)
pwsh -NoProfile -File $merkleScript -CsvPath $csv3
$root3 = (Get-Content -Raw (Join-Path $tmpDir 'merkle_root.txt')).Trim().ToLower()
$left  = Hash-String ($h3a + $h3b)
$right = Hash-String ($h3c + $h3c)  # duplicated last leaf
$expected3 = Hash-String ($left + $right)
if($root3 -eq $expected3){ Pass "Three leaves (odd): padding correct" }
else { Fail "Three leaves: expected $expected3, got $root3" }

# ======================================================================
# Test 4: Four leaves — balanced tree, no padding needed
# Level 1: [Hash(L0+L1), Hash(L2+L3)]
# Level 2: Hash( Hash(L0+L1) + Hash(L2+L3) )
# ======================================================================
$csv4 = Join-Path $tmpDir 'four.csv'
$h4a = "aaaa" * 16
$h4b = "bbbb" * 16
$h4c = "cccc" * 16
$h4d = "dddd" * 16
Write-TestCsv $csv4 @($h4a, $h4b, $h4c, $h4d)
pwsh -NoProfile -File $merkleScript -CsvPath $csv4
$root4 = (Get-Content -Raw (Join-Path $tmpDir 'merkle_root.txt')).Trim().ToLower()
$left4  = Hash-String ($h4a + $h4b)
$right4 = Hash-String ($h4c + $h4d)
$expected4 = Hash-String ($left4 + $right4)
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
# Manually compute: 5 leaves -> pad to 6 -> [L0,L1,L2,L3,L4,L4(dup)]
$p01 = Hash-String ($h5[0] + $h5[1])
$p23 = Hash-String ($h5[2] + $h5[3])
$p44 = Hash-String ($h5[4] + $h5[4])  # duplicated last
# Level 2: 3 nodes -> pad to 4 -> [p01, p23, p44, p44(dup)]
$q0 = Hash-String ($p01 + $p23)
$q1 = Hash-String ($p44 + $p44)
$expected5 = Hash-String ($q0 + $q1)
if($root5 -eq $expected5){ Pass "Five leaves: multi-level padding correct" }
else { Fail "Five leaves: expected $expected5, got $root5" }

# Cleanup
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

if($fail){ Write-Error "MERKLE EDGE-CASE TESTS FAILED"; exit 1 }
Write-Host "MERKLE EDGE-CASE TESTS PASS" -ForegroundColor Green
exit 0
