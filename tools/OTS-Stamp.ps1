param(
    [string]$Target = "output\merkle_root.txt",
    [string]$Server = "https://a.pool.opentimestamps.org"
)

$ErrorActionPreference = 'Stop'
if(-not (Test-Path $Target)){ Write-Error "Missing target: $Target"; exit 2 }

$merkleContent = (Get-Content -Raw -Path $Target).Trim().ToLower()

# Convert hex string to raw bytes for the OTS API
$digestBytes = [byte[]]::new(32)
for($i = 0; $i -lt 32; $i++){
    $digestBytes[$i] = [Convert]::ToByte($merkleContent.Substring($i * 2, 2), 16)
}

$dir = Split-Path -Parent $Target
$otsProofPath = Join-Path $dir 'merkle_root.txt.ots'
$otsReportPath = Join-Path $dir 'ots_receipt.txt'

# ─────────────────────────────────────────────────────
# Submit to OpenTimestamps calendar server
# ─────────────────────────────────────────────────────
$submitted = $false
$servers = @(
    "https://a.pool.opentimestamps.org",
    "https://b.pool.opentimestamps.org",
    "https://alice.btc.calendar.opentimestamps.org",
    "https://bob.btc.calendar.opentimestamps.org"
)

# Try primary server first, then fallbacks
$tryServers = @($Server) + ($servers | Where-Object { $_ -ne $Server })

foreach($srv in $tryServers){
    try {
        Write-Host "  Sender til $srv ..." -ForegroundColor Gray
        $response = Invoke-WebRequest -Uri "$srv/digest" `
            -Method Post `
            -Body $digestBytes `
            -ContentType "application/x-www-form-urlencoded" `
            -TimeoutSec 15 `
            -ErrorAction Stop

        if($response.StatusCode -eq 200){
            # Save the OTS proof binary
            [System.IO.File]::WriteAllBytes($otsProofPath, $response.Content)
            Write-Host "  OTS-bevis mottatt fra $srv" -ForegroundColor Green
            $submitted = $true

            # Create human-readable receipt
            $receipt = @"
============================================================
  OPENTIMESTAMPS KVITTERING
============================================================

  Merkle-rot:     $merkleContent
  Server:         $srv
  Tidspunkt:      $((Get-Date).ToString("o"))
  Bevis-fil:      $otsProofPath
  Status:         SENDT (venter paa Bitcoin-bekreftelse)

------------------------------------------------------------
  VERIFISERING:

  For aa verifisere at tidsstempelet er ankret i Bitcoin:

  1. Installer OTS-klienten:
     pip install opentimestamps-client

  2. Vent minst 4-24 timer (for Bitcoin-blokk)

  3. Oppgrader beviset:
     ots upgrade merkle_root.txt.ots

  4. Verifiser:
     ots verify merkle_root.txt.ots

  Eller bruk nettleseren:
     https://opentimestamps.org (last opp .ots-filen)

------------------------------------------------------------
  TEKNISK:

  OpenTimestamps forankrer SHA-256-hashen din i en
  Bitcoin-transaksjon. Dette gir et uavhengig,
  manipulasjonssikkert bevis paa at dataene eksisterte
  foer et bestemt tidspunkt.

  Ingen kan forfalske dette — heller ikke deg selv.
============================================================
"@
            $receipt | Set-Content -Encoding UTF8 -Path $otsReportPath
            break
        }
    } catch {
        Write-Host "  Feil fra $srv : $_" -ForegroundColor Yellow
    }
}

if(-not $submitted){
    Write-Host "  Kunne ikke naa noen OTS-servere. Lager lokal stub i stedet." -ForegroundColor Yellow

    # Fall back to local stub
    $fileHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Target).Hash.ToLower()
    $stub = @"
============================================================
  OPENTIMESTAMPS — LOKAL STUB (ikke sendt)
============================================================

  Merkle-rot:     $merkleContent
  Fil-hash:       $fileHash
  Tidspunkt:      $((Get-Date).ToString("o"))

  Kunne ikke kontakte OTS-servere. Send manuelt:
    ots stamp merkle_root.txt
    Eller: https://opentimestamps.org
============================================================
"@
    $stub | Set-Content -Encoding UTF8 -Path $otsReportPath
    exit 3
}

exit 0
