param(
  [string]$DoD = ".\output\DoD\DoD.json",
  [string]$Manifest = ".\output\manifest.csv",
  [string]$MerkleRoot = ".\output\merkle_root.txt"
)

$ErrorActionPreference='Stop'
$warnings = @()
function FAIL($m){ Write-Host "FAIL: $m" -ForegroundColor Red; exit 2 }
function OK($m){ Write-Host "OK: $m" -ForegroundColor Green }
function WARN($m){ Write-Host "WARN: $m" -ForegroundColor Yellow; $script:warnings += $m }

# 0) File existence check
foreach($p in @($DoD,$Manifest,$MerkleRoot)){ if(-not (Test-Path $p)){ FAIL "Missing: $p" } }

# 1) Read merkle root from file
$rootFile = (Get-Content -Raw -Path $MerkleRoot).Trim().ToLower()

# 2) Read DoD and check it points to same root
$dod = Get-Content -Raw -Path $DoD | ConvertFrom-Json
if(-not $dod.merkle_root){ FAIL "DoD.json missing 'merkle_root'" }
if($dod.merkle_root.ToLower() -ne $rootFile){ FAIL "DoD.merkle_root != merkle_root.txt" } else { OK "DoD.merkle_root matches merkle_root.txt" }

# 3) Check schema version
if($dod.schema_version){
    OK "DoD schema version: $($dod.schema_version)"
} else {
    WARN "DoD.json has no schema_version field (legacy format)"
}

# 4) Recompute Merkle from manifest.csv (RFC 6962 compliant)
$rows = Import-Csv -Path $Manifest
if(-not $rows -or $rows.Count -eq 0){ FAIL "manifest.csv empty" }
$hashes = @()
foreach($r in $rows){ $hashes += $r.SHA256.ToLower() }

# RFC 6962 §2.1: leaf hash = SHA-256(0x00 || data)
function Hash-Leaf([string]$data){
  $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($data)
  $prefixed = [byte[]]::new(1 + $dataBytes.Length)
  $prefixed[0] = 0x00
  [Array]::Copy($dataBytes, 0, $prefixed, 1, $dataBytes.Length)
  return (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($prefixed)) -Algorithm SHA256).Hash.ToLower()
}

# RFC 6962 §2.1: internal hash = SHA-256(0x01 || left || right)
function Combine([string]$a,[string]$b){
  $pairBytes = [System.Text.Encoding]::UTF8.GetBytes($a + $b)
  $prefixed = [byte[]]::new(1 + $pairBytes.Length)
  $prefixed[0] = 0x01
  [Array]::Copy($pairBytes, 0, $prefixed, 1, $pairBytes.Length)
  return (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($prefixed)) -Algorithm SHA256).Hash.ToLower()
}

# Build leaf level
$level=[System.Collections.Generic.List[string]]::new()
foreach($h in $hashes){ [void]$level.Add((Hash-Leaf $h)) }

# Build tree
while($level.Count -gt 1){
  if($level.Count % 2 -ne 0){ $level.Add($level[$level.Count-1]) }
  $next=[System.Collections.Generic.List[string]]::new()
  for($i=0;$i -lt $level.Count;$i+=2){ $next.Add((Combine $level[$i] $level[$i+1])) }
  $level=$next
}
$calcRoot=$level[0]

if($calcRoot -ne $rootFile){ FAIL "Merkle mismatch: calc=$calcRoot file=$rootFile" } else { OK "Merkle root (recomputed, RFC 6962) matches" }

# 5) Verify files on disk match manifest hashes
$repoRoot = $null
$manifestDir = Split-Path -Parent (Resolve-Path $Manifest)
$candidate = $manifestDir
while($candidate -and -not (Test-Path (Join-Path $candidate 'sample'))){
    $candidate = Split-Path -Parent $candidate
}
if($candidate){ $repoRoot = $candidate }

if($repoRoot){
    $diskFail = $false
    $manifestRels = @{}

    foreach($r in $rows){
        $rel = ($r.Rel -replace '\\','/')
        $manifestRels[$rel] = $true
        $absPath = Join-Path $repoRoot $rel
        if(-not (Test-Path $absPath)){
            Write-Host "FAIL: FILE MISSING on disk: $rel" -ForegroundColor Red
            $diskFail = $true
            continue
        }
        $diskHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $absPath).Hash.ToLower()
        $manifestHash = $r.SHA256.ToLower()
        if($diskHash -ne $manifestHash){
            Write-Host "FAIL: FILE TAMPERED: $rel (disk=$diskHash manifest=$manifestHash)" -ForegroundColor Red
            $diskFail = $true
        } else {
            OK "File verified: $rel"
        }
    }
    if($diskFail){ FAIL "One or more files on disk do not match manifest" }
    OK "All files on disk match manifest"

    # 6) Scan for unauthorized files (files on disk NOT in manifest)
    $sampleDir = Join-Path $repoRoot 'sample'
    if(Test-Path $sampleDir){
        $diskFiles = Get-ChildItem -Path $sampleDir -Recurse -File | Sort-Object { $_.FullName.Replace('\','/') }
        $extraFiles = @()
        foreach($f in $diskFiles){
            $rel = $f.FullName.Replace((Resolve-Path $repoRoot).Path, '').TrimStart('\','/').Replace('\','/')
            if(-not $manifestRels.ContainsKey($rel)){
                $extraFiles += $rel
            }
        }
        if($extraFiles.Count -gt 0){
            Write-Host ""
            Write-Host "FAIL: UNAUTHORIZED FILES detected on disk (not in manifest):" -ForegroundColor Red
            foreach($ef in $extraFiles){
                Write-Host "  - $ef" -ForegroundColor Red
            }
            FAIL "Found $($extraFiles.Count) unauthorized file(s) on disk not in manifest"
        }
        OK "No unauthorized files on disk"
    }
} else {
    WARN "Could not resolve repo root — skipping file-on-disk check"
}

# 7) GPG signature verification
$auditDir = Split-Path -Parent (Resolve-Path $Manifest)
$sigFiles = @(
    (Join-Path $auditDir 'manifest.csv.asc'),
    (Join-Path $auditDir 'merkle_root.txt.asc'),
    (Join-Path $auditDir 'DoD\DoD.json.asc')
)

$gpgCmd = Get-Command gpg -ErrorAction SilentlyContinue
if(-not $gpgCmd){ $gpgCmd = Get-Command gpg2 -ErrorAction SilentlyContinue }

$signaturesExist = $false
$signaturesValid = $true

foreach($sig in $sigFiles){
    if(Test-Path $sig){
        $signaturesExist = $true
        $dataFile = $sig -replace '\.asc$',''
        if(Test-Path $dataFile){
            if($gpgCmd){
                $gpgExe = if($gpgCmd -is [string]){ $gpgCmd } else { $gpgCmd.Source }
                $verifyResult = & $gpgExe --verify $sig $dataFile 2>&1
                if($LASTEXITCODE -eq 0){
                    OK "GPG signature valid: $(Split-Path -Leaf $sig)"
                } else {
                    Write-Host "FAIL: GPG signature INVALID: $(Split-Path -Leaf $sig)" -ForegroundColor Red
                    $signaturesValid = $false
                }
            } else {
                WARN "GPG not installed — cannot verify signature: $(Split-Path -Leaf $sig)"
            }
        }
    }
}

if($signaturesExist){
    if(-not $signaturesValid){ FAIL "One or more GPG signatures are invalid" }
    if($gpgCmd){ OK "All GPG signatures verified" }
} else {
    WARN "No GPG signatures found — audit is NOT cryptographically signed"
    WARN "For tamper-proof audits, run: pwsh audit.ps1 -Sign"
}

# 8) Script integrity check (if DoD includes script hashes)
if($dod.script_hashes){
    $scriptFail = $false
    $repoRootForScripts = if($repoRoot){ $repoRoot } else { Split-Path -Parent (Split-Path -Parent (Resolve-Path $DoD)) }
    foreach($prop in $dod.script_hashes.PSObject.Properties){
        $scriptPath = Join-Path $repoRootForScripts $prop.Name
        if(-not (Test-Path $scriptPath)){
            Write-Host "FAIL: Pipeline script missing: $($prop.Name)" -ForegroundColor Red
            $scriptFail = $true
            continue
        }
        $diskHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $scriptPath).Hash.ToLower()
        $recordedHash = $prop.Value.ToLower()
        if($diskHash -ne $recordedHash){
            Write-Host "FAIL: Pipeline script TAMPERED: $($prop.Name)" -ForegroundColor Red
            Write-Host "  Recorded: $recordedHash" -ForegroundColor Gray
            Write-Host "  On disk:  $diskHash" -ForegroundColor Gray
            $scriptFail = $true
        } else {
            OK "Script intact: $($prop.Name)"
        }
    }
    if($scriptFail){ FAIL "Pipeline scripts have been modified since audit" }
    OK "All pipeline scripts match recorded hashes"
} else {
    WARN "DoD.json has no script_hashes — pipeline integrity not verified"
}

# 9) NTP drift sanity check
if($dod.ntp_drift_seconds -ne $null){
    $ntpVal = [double]$dod.ntp_drift_seconds
    if($ntpVal -eq 9999){
        WARN "NTP drift is 9999 (measurement failed)"
    } elseif([math]::Abs($ntpVal) -gt 5){
        WARN "NTP drift: $($ntpVal)s (exceeds 5s threshold)"
    } else {
        OK "NTP drift within 5s ($($ntpVal)s)"
    }
}

# Summary
Write-Host ""
if($warnings.Count -gt 0){
    Write-Host "VERIFY PASS with $($warnings.Count) warning(s)" -ForegroundColor Yellow
} else {
    OK "VERIFY PASS — all checks passed"
}
exit 0
