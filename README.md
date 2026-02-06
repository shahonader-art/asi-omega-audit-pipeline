# ASI-Omega Audit Pipeline

Bevis at filene dine ikke er endret. Ett kommando, ett svar.

![CI](https://github.com/shahonader-art/asi-omega-audit-pipeline/actions/workflows/ci.yml/badge.svg)
![Verify](https://github.com/shahonader-art/asi-omega-audit-pipeline/actions/workflows/verify.yml/badge.svg)

## Kom i gang

```powershell
# Installer PowerShell 7+ hvis du ikke har det:
# https://github.com/PowerShell/PowerShell

# Klon prosjektet
git clone https://github.com/shahonader-art/asi-omega-audit-pipeline.git
cd asi-omega-audit-pipeline

# Lag en audit
pwsh audit.ps1

# Verifiser senere
pwsh audit.ps1 -Verify
```

## Hva gjor den?

Du har filer. Denne pipelinen lager et **kryptografisk bevis** for at filene er ekte og uendret.

```
Dine filer  -->  Fingeravtrykk per fil  -->  Ett unikt tall  -->  Rapport
                 (SHA-256)                   (Merkle-rot)         (DoD.json + rapport.txt)
```

Endre en eneste byte i en eneste fil — hele beviset bryter sammen. Det er poenget.

## Hvem trenger dette?

### Advokater og jurister
> *"Klienten leverte disse dokumentene 15. januar. Kan vi bevise at de ikke er endret?"*

```powershell
pwsh audit.ps1 -Path "C:\Saker\Klient-2024\dokumenter"
# --> output\rapport.txt er beviset
```

### Revisorer
> *"Vi trenger bevis for at regnskapsfilene er identiske med de som ble levert til Skatteetaten."*

```powershell
pwsh audit.ps1 -Path "C:\Regnskap\2024\leveranse"
pwsh audit.ps1 -Verify  # Kjoer dette naar som helst for aa sjekke
```

### Utviklere og leverandorer
> *"Kunden hevder at programvaren vi leverte hadde en feil. Vi maa bevise hva vi faktisk leverte."*

```powershell
pwsh audit.ps1 -Path ".\release\v2.1.0"
# Lagre output/-mappen sammen med leveransen
```

### Forskere
> *"Fagfellevurderingen krever bevis for at datasettet ikke er manipulert etter analyse."*

```powershell
pwsh audit.ps1 -Path ".\data\experiment-results"
```

## Hva du faar

Etter `pwsh audit.ps1` finner du:

| Fil | For hvem | Innhold |
|-----|----------|---------|
| `output/rapport.txt` | Alle | Lesbar rapport med alle detaljer |
| `output/manifest.csv` | Teknisk | Liste over filer + SHA-256 hash |
| `output/merkle_root.txt` | Teknisk | Ett tall som representerer alt |
| `output/DoD/DoD.json` | Maskin | Komplett rapport i JSON-format |

## Slik fungerer det

1. **Scanner** alle filer og beregner SHA-256 fingeravtrykk (umulig aa forfalske)
2. **Kombinerer** alle fingeravtrykk i et Merkle-tre til en rot
3. **Tester** at resultatet matcher kjente verdier
4. **Genererer** en rapport med tidsstempel og systeminfo
5. **Verifiserer** at filer paa disk matcher manifestet

## Kommandoer

```powershell
pwsh audit.ps1                       # Auditer standardmappen (sample/)
pwsh audit.ps1 -Path "C:\MinMappe"   # Auditer en vilkaarlig mappe
pwsh audit.ps1 -Verify               # Verifiser en tidligere audit
pwsh audit.ps1 -Help                 # Vis hjelp
```

## Avansert bruk

```powershell
# Enkeltskript (for utviklere)
pwsh -File src\run_demo.ps1 -Out output              # Generer manifest
pwsh -File tools\Merkle.ps1 -CsvPath output\manifest.csv  # Bygg Merkle-tre
pwsh -File tools\DoD.ps1 -Out output\DoD              # Lag rapport
pwsh -File tools\verify.ps1 -DoD output\DoD\DoD.json -Manifest output\manifest.csv -MerkleRoot output\merkle_root.txt

# Signer med GPG (valgfritt, for juridisk styrke)
pwsh -File tools\Sign-DoD.ps1 -File output\DoD\DoD.json -KeyId AABBCCDD

# OpenTimestamps (valgfritt, for ekstern tidsstempling)
pwsh -File tools\OTS-Stub.ps1 -Target output\merkle_root.txt
```

## Tekniske detaljer

- **Spraak:** PowerShell 7+
- **Hashing:** SHA-256 (NIST FIPS 180-4)
- **Merkle-tre:** Binaert tre med duplisering av siste blad ved oddetall
- **NTP:** Kryss-plattform (w32tm/ntpdate/sntp/chronyc)
- **CI/CD:** GitHub Actions med automatisk testing

## Forfatter

**Shaho Nader**

## Kontakt

For henvendelser, aapne et issue:
https://github.com/shahonader-art/asi-omega-audit-pipeline/issues

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.TBA.svg)](https://doi.org/10.5281/zenodo.TBA)
