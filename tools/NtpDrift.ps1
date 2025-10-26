param([string]$Server='time.windows.com',[int]$Samples=5)
$ErrorActionPreference = 'SilentlyContinue'
try{
  $cmd = "w32tm /stripchart /computer:$Server /dataonly /samples:$Samples"
  $out = & cmd /c $cmd
  if(-not $out){ throw "no output" }
  $vals = @()
  foreach($line in $out){
    if($line -match 'o=(-?\d+(\.\d+)?)s'){
      $vals += [double]$Matches[1]
    }
  }
  if($vals.Count -gt 0){
    [math]::Round( ($vals | Measure-Object -Average).Average, 3 )
  } else { 9999 }
}catch{ 9999 }
