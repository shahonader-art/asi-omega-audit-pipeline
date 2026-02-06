param([Parameter(Mandatory)][string]$CsvPath)

# ASI-Omega Merkle Tree — RFC 6962 compliant
# Uses domain separation to prevent second-preimage attacks:
#   Leaf hash:     SHA-256(0x00 || data)
#   Internal hash: SHA-256(0x01 || left || right)

$ErrorActionPreference = 'Stop'
if(-not (Test-Path $CsvPath)){ Write-Error "CSV not found: $CsvPath"; exit 2 }

$rows = Import-Csv -Path $CsvPath
if(-not $rows -or $rows.Count -eq 0){ Write-Error "Empty CSV"; exit 3 }

$leaves = @()
foreach($r in $rows){
  if($r.Rel -and $r.SHA256){ $leaves += $r.SHA256.ToLower() }
}
if($leaves.Count -eq 0){ Write-Error "No leaves extracted"; exit 4 }

# RFC 6962 §2.1: leaf hash = SHA-256(0x00 || leaf_data)
function Hash-Leaf([string]$data){
  $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($data)
  $prefixed = [byte[]]::new(1 + $dataBytes.Length)
  $prefixed[0] = 0x00
  [Array]::Copy($dataBytes, 0, $prefixed, 1, $dataBytes.Length)
  return (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($prefixed)) -Algorithm SHA256).Hash.ToLower()
}

# RFC 6962 §2.1: internal hash = SHA-256(0x01 || left || right)
function Combine-Hash([string]$a, [string]$b){
  $pairBytes = [System.Text.Encoding]::UTF8.GetBytes($a + $b)
  $prefixed = [byte[]]::new(1 + $pairBytes.Length)
  $prefixed[0] = 0x01
  [Array]::Copy($pairBytes, 0, $prefixed, 1, $pairBytes.Length)
  return (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($prefixed)) -Algorithm SHA256).Hash.ToLower()
}

# Build leaf level with 0x00 prefix
$level = [System.Collections.Generic.List[string]]::new()
foreach($leaf in $leaves){
  [void]$level.Add((Hash-Leaf $leaf))
}

# Build tree with 0x01 prefix at each internal level
while($level.Count -gt 1){
  if(($level.Count % 2) -ne 0){ $level.Add($level[$level.Count-1]) }
  $next = [System.Collections.Generic.List[string]]::new()
  for($i=0; $i -lt $level.Count; $i+=2){
    $next.Add( (Combine-Hash $level[$i] $level[$i+1]) )
  }
  $level = $next
}

$root = $level[0]
$rootPath = Join-Path (Split-Path -Parent $CsvPath) 'merkle_root.txt'
$root | Set-Content -Encoding ASCII -Path $rootPath
Write-Host "MERKLE_ROOT: $root"
