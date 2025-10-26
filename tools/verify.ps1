param(
  [string]$DoD = ".\output\DoD\DoD.json",
  [string]$Manifest = ".\output\manifest.csv",
  [string]$MerkleRoot = ".\output\merkle_root.txt"
)

$ErrorActionPreference='Stop'
function FAIL($m){ Write-Host "❌ $m" -ForegroundColor Red; exit 2 }
function OK($m){ Write-Host "✅ $m" -ForegroundColor Green }

# 0) Eksistenskontroll
foreach($p in @($DoD,$Manifest,$MerkleRoot)){ if(-not (Test-Path $p)){ FAIL "Missing: $p" } }

# 1) Les merkle-root fra fil
$rootFile = (Get-Content -Raw -Path $MerkleRoot).Trim().ToLower()

# 2) Les DoD og sjekk at den peker til samme root
$dod = Get-Content -Raw -Path $DoD | ConvertFrom-Json
if(-not $dod.merkle_root){ FAIL "DoD.json missing 'merkle_root'" }
if($dod.merkle_root.ToLower() -ne $rootFile){ FAIL "DoD.merkle_root != merkle_root.txt" } else { OK "DoD.merkle_root matches merkle_root.txt" }

# 3) Reberegn Merkle fra manifest.csv
$rows = Import-Csv -Path $Manifest
if(-not $rows -or $rows.Count -eq 0){ FAIL "manifest.csv empty" }
$hashes = @()
foreach($r in $rows){ $hashes += $r.SHA256.ToLower() }

function Combine([string]$a,[string]$b){
  $pair=[System.Text.Encoding]::UTF8.GetBytes($a+$b)
  (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($pair)) -Algorithm SHA256).Hash.ToLower()
}

$level=[System.Collections.Generic.List[string]]::new(); $hashes | % { [void]$level.Add($_) }
while($level.Count -gt 1){
  if($level.Count % 2 -ne 0){ $level.Add($level[$level.Count-1]) }
  $next=[System.Collections.Generic.List[string]]::new()
  for($i=0;$i -lt $level.Count;$i+=2){ $next.Add((Combine $level[$i] $level[$i+1])) }
  $level=$next
}
$calcRoot=$level[0]

if($calcRoot -ne $rootFile){ FAIL "Merkle mismatch: calc=$calcRoot file=$rootFile" } else { OK "Merkle root (recomputed) matches" }

# 4) (valgfritt) enkel sanity på NTP-drift
try{
  if($dod.ntp_drift_seconds -ne $null){
    if([math]::Abs([double]$dod.ntp_drift_seconds) -gt 5){ Write-Host "⚠ NTP drift: $($dod.ntp_drift_seconds)s" -ForegroundColor Yellow }
    else { OK "NTP drift within 5s" }
  }
}catch{}

OK "VERIFY PASS"
exit 0
