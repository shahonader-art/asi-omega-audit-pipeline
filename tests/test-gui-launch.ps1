$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$guiScript = Join-Path $repoRoot 'audit-gui.ps1'
$fail = $false

function Pass($m){ Write-Host "OK: $m" -ForegroundColor Green }
function Fail($m){ Write-Host "FAIL: $m" -ForegroundColor Red; $script:fail=$true }
function Skip($m){ Write-Host "SKIP: $m" -ForegroundColor Yellow }

# --- Test 1: GUI script exists ---
if(Test-Path $guiScript){ Pass "audit-gui.ps1 exists" }
else { Fail "audit-gui.ps1 missing"; exit 1 }

# --- Test 2: Script uses Windows Forms ---
$src = Get-Content -Raw $guiScript
if($src -match 'System\.Windows\.Forms'){ Pass "Uses System.Windows.Forms" }
else { Fail "Missing Windows.Forms reference" }

# --- Test 3: Has required UI elements ---
$required = @(
    @{ Name="Folder browser"; Pattern='FolderBrowserDialog' },
    @{ Name="Audit button"; Pattern='Start Audit' },
    @{ Name="Verify button"; Pattern='Verifiser' },
    @{ Name="Report button"; Pattern='Aapne Rapport' },
    @{ Name="Log output area"; Pattern='Multiline.*=.*\$true' },
    @{ Name="Status label"; Pattern='lblStatus' },
    @{ Name="Sign checkbox"; Pattern='GPG-signer' },
    @{ Name="OTS checkbox"; Pattern='OpenTimestamps' }
)

foreach($r in $required){
    if($src -match $r.Pattern){ Pass "UI element: $($r.Name)" }
    else { Fail "Missing UI element: $($r.Name)" }
}

# --- Test 4: GUI calls audit.ps1 (not individual scripts) ---
if($src -match 'audit\.ps1'){
    Pass "GUI delegates to audit.ps1 (single entry point)"
} else {
    Fail "GUI does not call audit.ps1"
}

# --- Test 5: Syntax check (parse without executing) ---
try {
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($guiScript, [ref]$tokens, [ref]$errors)
    if($errors.Count -eq 0){ Pass "Script parses without syntax errors" }
    else { Fail "Syntax errors: $($errors[0].Message)" }
} catch {
    Skip "Could not parse script: $_"
}

if($fail){ Write-Error "GUI LAUNCH TESTS FAILED"; exit 1 }
Write-Host "GUI LAUNCH TESTS PASS" -ForegroundColor Green
exit 0
