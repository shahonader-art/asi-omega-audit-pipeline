param([Parameter(Mandatory)][string]$CsvPath)

$ErrorActionPreference = 'Stop'
if(-not (Test-Path $CsvPath)){ Write-Error "CSV not found: $CsvPath"; exit 2 }

$rows = Import-Csv -Path $CsvPath
if(-not $rows -or $rows.Count -eq 0){ Write-Error "Empty CSV"; exit 3 }

$leaves = @()
foreach($r in $rows){
  if($r.Rel -and $r.SHA256){ $leaves += $r.SHA256.ToLower() }
}
if($leaves.Count -eq 0){ Write-Error "No leaves extracted"; exit 4 }

function Combine-Hash([string]$a, [string]$b){
  $pair = [System.Text.Encoding]::UTF8.GetBytes($a + $b)
  return (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($pair)) -Algorithm SHA256).Hash.ToLower()
}

$level = [System.Collections.Generic.List[string]]::new()
$leaves | ForEach-Object { [void]$level.Add($_) }

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
