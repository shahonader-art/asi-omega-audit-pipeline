<p align="center">
  <strong>ASI-Omega Audit Pipeline</strong><br>
  <em>Kryptografisk bevis for at filene dine er ekte og uendret.</em>
</p>

<p align="center">
  <a href="https://github.com/shahonader-art/asi-omega-audit-pipeline/actions/workflows/ci.yml">
    <img src="https://github.com/shahonader-art/asi-omega-audit-pipeline/actions/workflows/ci.yml/badge.svg" alt="CI">
  </a>
  <a href="https://github.com/shahonader-art/asi-omega-audit-pipeline/actions/workflows/verify.yml">
    <img src="https://github.com/shahonader-art/asi-omega-audit-pipeline/actions/workflows/verify.yml/badge.svg" alt="Verify">
  </a>
</p>

---

## Hva er dette?

ASI-Omega er et verktoy som **beviser at filer ikke er endret**.

Du peker det mot en mappe. Det beregner et unikt fingeravtrykk for hver fil, kombinerer dem til ett tall (en Merkle-rot), og genererer en rapport. Endres en eneste byte i en eneste fil — endres hele beviset.

```
Dine filer  →  SHA-256 per fil  →  Merkle-rot  →  Rapport
```

**Ingen kan forfalske dette. Heller ikke deg selv.**

---

## Installasjon

### Alternativ 1: En-kommando installasjon (anbefalt)

```powershell
irm https://raw.githubusercontent.com/shahonader-art/asi-omega-audit-pipeline/main/install.ps1 | iex
```

Dette laster ned prosjektet, lager en snarvei paa skrivebordet, og setter opp alt automatisk.

### Alternativ 2: Manuell installasjon

```powershell
git clone https://github.com/shahonader-art/asi-omega-audit-pipeline.git
cd asi-omega-audit-pipeline
pwsh audit.ps1 -Help
```

### Alternativ 3: Bygg som .exe

```powershell
git clone https://github.com/shahonader-art/asi-omega-audit-pipeline.git
cd asi-omega-audit-pipeline
pwsh build-exe.ps1
```

Ferdig! Filene ligger i `dist/`-mappen, klar til aa distribuere.

### Krav

- [PowerShell 7+](https://github.com/PowerShell/PowerShell/releases) (gratis, Windows/Mac/Linux)
- [Gpg4win](https://gpg4win.org) (valgfritt, for digital signering)

---

## Bruk

### Grafisk (GUI)

Dobbeltklikk **ASI-Omega Audit** paa skrivebordet, eller:

```powershell
pwsh audit-gui.ps1
```

### Terminal

```powershell
# Auditer en mappe
pwsh audit.ps1 -Path "C:\Mine\Dokumenter"

# Verifiser at filer er uendret
pwsh audit.ps1 -Verify

# Full audit med signering og tidsstempel
pwsh audit.ps1 -Full

# Vis alle kommandoer
pwsh audit.ps1 -Help
```

### Kommandooversikt

| Kommando | Beskrivelse |
|----------|-------------|
| `pwsh audit.ps1` | Auditer standardmappen |
| `pwsh audit.ps1 -Path <mappe>` | Auditer en vilkaarlig mappe |
| `pwsh audit.ps1 -Verify` | Kontroller at filer er uendret |
| `pwsh audit.ps1 -Sign` | Auditer + GPG-signering |
| `pwsh audit.ps1 -Timestamp` | Auditer + uavhengig tidsstempel |
| `pwsh audit.ps1 -Full` | Alt: audit + signering + tidsstempel |

---

## Hva faar du?

Etter en audit finner du disse filene i `output/`:

| Fil | Beskrivelse |
|-----|-------------|
| `rapport.txt` | Lesbar rapport med alle detaljer |
| `manifest.csv` | SHA-256 fingeravtrykk per fil |
| `merkle_root.txt` | Ett kombinert fingeravtrykk for alt |
| `DoD/DoD.json` | Maskinlesbar rapport (JSON) |
| `*.asc` | GPG-signaturer (med `-Sign`) |
| `ots_receipt.txt` | Tidsstempel-kvittering (med `-Timestamp`) |

---

## Hvem er dette for?

### Advokater og jurister
> *"Klienten leverte dokumenter 15. januar. Vi trenger bevis for at de ikke er endret."*

Kjoer `audit.ps1 -Full` paa dokumentene. Rapporten er et kryptografisk bevis som kan legges ved saken.

### Revisorer og oekonomer
> *"Regnskapet maa vaere identisk med det som ble levert til Skatteetaten."*

Auditer ved levering. Verifiser naar som helst etterpaa med `audit.ps1 -Verify`.

### IT og utviklere
> *"Kunden hevder programvaren vi leverte hadde en feil. Vi maa bevise hva vi faktisk leverte."*

Auditer `release/`-mappen foer levering. Lagre `output/` sammen med leveransen.

### Forskere
> *"Fagfellen krever bevis for at datasettet ikke er manipulert etter analyse."*

Auditer datasettet etter analyse. Legg ved rapporten til publikasjonen.

---

## Slik fungerer det

```
┌─────────────┐     ┌──────────────┐     ┌────────────┐     ┌───────────┐
│  Dine filer  │ ──→ │  SHA-256 per  │ ──→ │ Merkle-tre │ ──→ │  Rapport  │
│              │     │  fil          │     │            │     │           │
└─────────────┘     └──────────────┘     └────────────┘     └───────────┘
```

1. **Scanner** alle filer og beregner SHA-256 fingeravtrykk (NIST FIPS 180-4)
2. **Kombinerer** fingeravtrykkene i et Merkle-tre til en rot
3. **Tester** at alle beregninger er korrekte (selvtest)
4. **Genererer** rapport med tidsstempel og systeminfo
5. **Signerer** (valgfritt) med GPG for personlig garanti
6. **Tidsstempler** (valgfritt) via uavhengig tjeneste

### Verifisering

Naar du kjoerer `audit.ps1 -Verify`, skjer foelgende:

1. Alle filer paa disk re-hashes og sammenlignes med manifestet
2. Merkle-roten reberegnes fra manifestet
3. DoD-rapporten kontrolleres mot Merkle-roten
4. NTP-drift sjekkes for aa validere tidspunkt

Hvis en eneste fil er endret — faar du beskjed.

---

## Teknisk

| Egenskap | Verdi |
|----------|-------|
| Spraak | PowerShell 7+ |
| Hashing | SHA-256 (NIST FIPS 180-4) |
| Merkle-tre | Binaert tre med duplisering av siste blad |
| Signering | GPG detached signatures (.asc) |
| Tidsstempling | OpenTimestamps (valgfritt) |
| NTP | Kryss-plattform (w32tm / ntpdate / sntp / chronyc) |
| Plattform | Windows, macOS, Linux |
| CI/CD | GitHub Actions |
| Tester | 19 testfiler, 6 akseptansekriterier |

---

## Prosjektstruktur

```
asi-omega-audit-pipeline/
├── audit.ps1            Hovedkommando (CLI)
├── audit-gui.ps1        Grafisk brukergrensesnitt
├── install.ps1          Installasjonsskript
├── build-exe.ps1        Bygg .exe-filer
├── src/
│   └── run_demo.ps1     Generer filmanifest
├── tools/
│   ├── Merkle.ps1       Bygg Merkle-tre
│   ├── verify.ps1       Verifisering
│   ├── DoD.ps1          Generer DoD-rapport
│   ├── NtpDrift.ps1     NTP-tidssjekk
│   ├── Sign-Audit.ps1   GPG-signering
│   └── OTS-Stamp.ps1    Uavhengig tidsstempling
├── tests/               Testfiler
├── docs/                Dokumentasjon og metadata
└── sample/              Eksempelfiler for testing
```

---

## Lisens

MIT

## Forfatter

**Shaho Nader** — [GitHub](https://github.com/shahonader-art)

## Kontakt

For spoersmaal eller feilmeldinger:
[github.com/shahonader-art/asi-omega-audit-pipeline/issues](https://github.com/shahonader-art/asi-omega-audit-pipeline/issues)
