$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$metaScript = Join-Path $repoRoot 'docs\meta_gen.ps1'
$metaOutput = Join-Path $repoRoot 'docs\meta.json'
$fail = $false

function Pass($m){ Write-Host "OK: $m" -ForegroundColor Green }
function Fail($m){ Write-Host "FAIL: $m" -ForegroundColor Red; $script:fail=$true }

# Remove any previous meta.json to test fresh generation
if(Test-Path $metaOutput){ Remove-Item -Force $metaOutput }

# --- Test 1: Script runs without error ---
try {
    pwsh -NoProfile -File $metaScript
    Pass "meta_gen.ps1 runs without error"
} catch {
    Fail "meta_gen.ps1 threw: $_"
}

# --- Test 2: meta.json is created ---
if(Test-Path $metaOutput){ Pass "meta.json created" }
else { Fail "meta.json not created"; if($fail){ Write-Error "META-GEN TESTS FAILED"; exit 1 } }

# --- Test 3: Output is valid JSON ---
$meta = $null
try {
    $meta = Get-Content -Raw -Path $metaOutput | ConvertFrom-Json
    Pass "meta.json is valid JSON"
} catch {
    Fail "meta.json is not valid JSON: $_"
}

if($meta){
    # --- Test 4: Required keys exist ---
    $requiredKeys = @('name','created','platform','author')
    foreach($key in $requiredKeys){
        if($null -ne $meta.$key -and $meta.$key -ne ''){
            Pass "Key '$key' present: $($meta.$key)"
        } else {
            Fail "Key '$key' missing or empty"
        }
    }

    # --- Test 5: 'created' is valid ISO 8601 timestamp ---
    try {
        [datetime]::Parse($meta.created) | Out-Null
        Pass "'created' is valid ISO 8601 timestamp"
    } catch {
        Fail "'created' is not a valid timestamp: $($meta.created)"
    }

    # --- Test 6: 'name' matches project name ---
    if($meta.name -eq 'asi-omega-audit-pipeline'){ Pass "'name' is correct" }
    else { Fail "Expected name 'asi-omega-audit-pipeline', got '$($meta.name)'" }
}

# Cleanup generated file
if(Test-Path $metaOutput){ Remove-Item -Force $metaOutput }

if($fail){ Write-Error "META-GEN TESTS FAILED"; exit 1 }
Write-Host "META-GEN TESTS PASS" -ForegroundColor Green
exit 0
