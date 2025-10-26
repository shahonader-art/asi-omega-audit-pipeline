param(
  [string]$DoD = ".\output\DoD\DoD.json",
  [string]$Manifest = ".\output\manifest.csv",
  [string]$MerkleRoot = ".\output\merkle_root.txt",
  [string]$Golden = ".\docs\golden-hashes.json"
)
$ErrorActionPreference='Stop'
function FAIL($m){ Write-Host "❌ $m" -ForegroundColor Red; exit 2 }
function OK($m){ Write-Host "✅ $m" -ForegroundColor Green }
foreach($p in @($DoD,$Manifest,$MerkleRoot,$Golden)){ if(-not (Test-Path $p)){ FAIL "Missing: $p" } }
$rows=Import-Csv $Manifest; if(-not $rows){ FAIL "manifest.csv empty" }
$hashes=@(); $rel2sha=@{}; foreach($r in $rows){ $hashes+=$r.SHA256.ToLower(); $rel2sha[$r.Rel]=$r.SHA256.ToLower() }
function Combine([string]$a,[string]$b){ $pair=[System.Text.Encoding]::UTF8.GetBytes($a+$b); (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($pair)) -Algorithm SHA256).Hash.ToLower() }
$level=[System.Collections.Generic.List[string]]::new(); $hashes|%{[void]$level.Add($_)}; while($level.Count -gt 1){ if($level.Count%2 -ne 0){$level.Add($level[-1])};$next=[System.Collections.Generic.List[string]]::new();for($i=0;$i -lt $level.Count;$i+=2){$next.Add((Combine $level[$i] $level[$i+1]))};$level=$next};$calcRoot=$level[0]
$rootFile=(Get-Content -Raw $MerkleRoot).Trim().ToLower(); if($calcRoot -ne $rootFile){ FAIL "Merkle mismatch"; } else { OK "Merkle root matches" }
$doc=Get-Content -Raw $DoD|ConvertFrom-Json; if($doc.merkle_root.ToLower() -ne $rootFile){ FAIL "DoD mismatch" } else { OK "VERIFY PASS" }
