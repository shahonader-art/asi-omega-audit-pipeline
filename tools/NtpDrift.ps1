param([string]$Server='time.windows.com',[int]$Samples=3)
$ErrorActionPreference = 'Stop'

# Cross-platform NTP drift measurement
# Returns average drift in seconds, or writes a warning and returns $null

function Measure-NtpDrift-Windows([string]$srv, [int]$n){
    $cmd = "w32tm /stripchart /computer:$srv /dataonly /samples:$n"
    $out = & cmd /c $cmd 2>&1
    if(-not $out){ throw "w32tm produced no output" }
    $vals = @()
    foreach($line in $out){
        if($line -match 'o=(-?\d+(\.\d+)?)s'){
            $vals += [double]$Matches[1]
        }
    }
    if($vals.Count -eq 0){ throw "w32tm output contained no drift measurements" }
    return [math]::Round( ($vals | Measure-Object -Average).Average, 3 )
}

function Measure-NtpDrift-Unix([string]$srv){
    # Try ntpdate (dry-run) first, then sntp, then chronyd
    $tools = @(
        @{ Cmd="ntpdate"; Args=@("-q",$srv); Pattern='offset\s+(-?\d+\.\d+)' },
        @{ Cmd="sntp";    Args=@($srv);      Pattern='([+-]?\d+\.\d+)' },
        @{ Cmd="chronyc"; Args=@("tracking"); Pattern='System time\s+:\s+(\d+\.\d+)' }
    )
    foreach($t in $tools){
        $exe = Get-Command $t.Cmd -ErrorAction SilentlyContinue
        if($exe){
            $out = & $t.Cmd @($t.Args) 2>&1
            foreach($line in $out){
                if($line -match $t.Pattern){
                    return [math]::Round([double]$Matches[1], 3)
                }
            }
        }
    }
    throw "No NTP tool available (tried ntpdate, sntp, chronyc). Install one for drift measurement."
}

# Detect platform and measure
try {
    if($IsWindows -or $env:OS -match 'Windows'){
        $drift = Measure-NtpDrift-Windows $Server $Samples
    } else {
        $drift = Measure-NtpDrift-Unix $Server
    }
    Write-Host "NTP drift: ${drift}s (server: $Server)" -ForegroundColor Green
    $drift
} catch {
    Write-Host "WARNING: NTP measurement failed: $_" -ForegroundColor Yellow
    Write-Host "WARNING: Timestamp in DoD will not have external time validation" -ForegroundColor Yellow
    9999
}
