# ASI-Omega Audit Pipeline — Grafisk brukergrensesnitt
# Kjoer: pwsh audit-gui.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ─────────────────────────────────────────────────────
# Theme
# ─────────────────────────────────────────────────────
$bgColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$fgColor = [System.Drawing.Color]::White
$accentColor = [System.Drawing.Color]::FromArgb(0, 150, 136)
$btnColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
$successColor = [System.Drawing.Color]::FromArgb(76, 175, 80)
$errorColor = [System.Drawing.Color]::FromArgb(244, 67, 54)
$font = New-Object System.Drawing.Font("Segoe UI", 10)
$fontBold = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$fontTitle = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$fontMono = New-Object System.Drawing.Font("Consolas", 9)

# ─────────────────────────────────────────────────────
# Main Form
# ─────────────────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text = "ASI-Omega Audit Pipeline"
$form.Size = New-Object System.Drawing.Size(700, 620)
$form.StartPosition = "CenterScreen"
$form.BackColor = $bgColor
$form.ForeColor = $fgColor
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

# Title
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "ASI-Omega Audit Pipeline"
$lblTitle.Font = $fontTitle
$lblTitle.ForeColor = $accentColor
$lblTitle.Location = New-Object System.Drawing.Point(20, 15)
$lblTitle.AutoSize = $true
$form.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "Bevis at filene dine er ekte og uendret"
$lblSub.Font = $font
$lblSub.ForeColor = [System.Drawing.Color]::Gray
$lblSub.Location = New-Object System.Drawing.Point(20, 50)
$lblSub.AutoSize = $true
$form.Controls.Add($lblSub)

# ─── Folder selection ───
$lblFolder = New-Object System.Windows.Forms.Label
$lblFolder.Text = "Velg mappe:"
$lblFolder.Font = $fontBold
$lblFolder.Location = New-Object System.Drawing.Point(20, 90)
$lblFolder.AutoSize = $true
$form.Controls.Add($lblFolder)

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Location = New-Object System.Drawing.Point(20, 115)
$txtPath.Size = New-Object System.Drawing.Size(540, 30)
$txtPath.Font = $font
$txtPath.BackColor = $btnColor
$txtPath.ForeColor = $fgColor
$txtPath.Text = Join-Path $root "sample"
$form.Controls.Add($txtPath)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "Bla..."
$btnBrowse.Location = New-Object System.Drawing.Point(570, 113)
$btnBrowse.Size = New-Object System.Drawing.Size(90, 30)
$btnBrowse.Font = $font
$btnBrowse.BackColor = $btnColor
$btnBrowse.ForeColor = $fgColor
$btnBrowse.FlatStyle = "Flat"
$btnBrowse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Velg mappe aa auditere"
    if($dialog.ShowDialog() -eq "OK"){
        $txtPath.Text = $dialog.SelectedPath
    }
})
$form.Controls.Add($btnBrowse)

# ─── Options ───
$chkSign = New-Object System.Windows.Forms.CheckBox
$chkSign.Text = "Digital signering (GPG)"
$chkSign.Font = $font
$chkSign.ForeColor = $fgColor
$chkSign.Location = New-Object System.Drawing.Point(20, 155)
$chkSign.AutoSize = $true
$form.Controls.Add($chkSign)

$chkOTS = New-Object System.Windows.Forms.CheckBox
$chkOTS.Text = "Uavhengig tidsstempling"
$chkOTS.Font = $font
$chkOTS.ForeColor = $fgColor
$chkOTS.Location = New-Object System.Drawing.Point(300, 155)
$chkOTS.AutoSize = $true
$form.Controls.Add($chkOTS)

# ─── Action buttons ───
$btnAudit = New-Object System.Windows.Forms.Button
$btnAudit.Text = "Start Audit"
$btnAudit.Location = New-Object System.Drawing.Point(20, 190)
$btnAudit.Size = New-Object System.Drawing.Size(200, 45)
$btnAudit.Font = $fontBold
$btnAudit.BackColor = $accentColor
$btnAudit.ForeColor = $fgColor
$btnAudit.FlatStyle = "Flat"
$form.Controls.Add($btnAudit)

$btnVerify = New-Object System.Windows.Forms.Button
$btnVerify.Text = "Verifiser"
$btnVerify.Location = New-Object System.Drawing.Point(240, 190)
$btnVerify.Size = New-Object System.Drawing.Size(200, 45)
$btnVerify.Font = $fontBold
$btnVerify.BackColor = $btnColor
$btnVerify.ForeColor = $fgColor
$btnVerify.FlatStyle = "Flat"
$form.Controls.Add($btnVerify)

$btnReport = New-Object System.Windows.Forms.Button
$btnReport.Text = "Vis Rapport"
$btnReport.Location = New-Object System.Drawing.Point(460, 190)
$btnReport.Size = New-Object System.Drawing.Size(200, 45)
$btnReport.Font = $fontBold
$btnReport.BackColor = $btnColor
$btnReport.ForeColor = $fgColor
$btnReport.FlatStyle = "Flat"
$btnReport.Enabled = $false
$form.Controls.Add($btnReport)

# ─── Status ───
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Klar."
$lblStatus.Font = $fontBold
$lblStatus.ForeColor = $accentColor
$lblStatus.Location = New-Object System.Drawing.Point(20, 248)
$lblStatus.AutoSize = $true
$form.Controls.Add($lblStatus)

# ─── Log output ───
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(20, 275)
$txtLog.Size = New-Object System.Drawing.Size(640, 290)
$txtLog.Font = $fontMono
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$txtLog.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
$txtLog.Multiline = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.ReadOnly = $true
$txtLog.WordWrap = $false
$form.Controls.Add($txtLog)

# ─────────────────────────────────────────────────────
# Functions
# ─────────────────────────────────────────────────────
function Log($msg){
    $txtLog.AppendText("$msg`r`n")
    $txtLog.SelectionStart = $txtLog.Text.Length
    $txtLog.ScrollToCaret()
    $form.Refresh()
}

function Run-Audit {
    $txtLog.Clear()
    $lblStatus.Text = "Analyserer filer..."
    $lblStatus.ForeColor = $accentColor
    $btnAudit.Enabled = $false
    $btnVerify.Enabled = $false
    $form.Refresh()

    try {
        $auditScript = Join-Path $root 'audit.ps1'
        $targetPath = $txtPath.Text
        $args = @()

        $defaultSample = Join-Path $root "sample"
        if($targetPath -ne $defaultSample -and $targetPath -ne ""){
            $args += @("-Path", $targetPath)
        }
        if($chkSign.Checked){ $args += "-Sign" }
        if($chkOTS.Checked){ $args += "-Timestamp" }

        Log "Starter audit av: $targetPath"
        Log "─────────────────────────────────────"

        $output = pwsh -NoProfile -File $auditScript @args 2>&1
        foreach($line in $output){
            Log $line
        }

        if($LASTEXITCODE -eq 0){
            $lblStatus.Text = "AUDIT FULLFORT"
            $lblStatus.ForeColor = $successColor
            $btnReport.Enabled = $true
        } else {
            $lblStatus.Text = "AUDIT FEILET (exit $LASTEXITCODE)"
            $lblStatus.ForeColor = $errorColor
        }
    } catch {
        Log "FEIL: $_"
        $lblStatus.Text = "FEIL"
        $lblStatus.ForeColor = $errorColor
    }

    $btnAudit.Enabled = $true
    $btnVerify.Enabled = $true
}

function Run-Verify {
    $txtLog.Clear()
    $lblStatus.Text = "Kontrollerer integritet..."
    $lblStatus.ForeColor = $accentColor
    $btnAudit.Enabled = $false
    $btnVerify.Enabled = $false
    $form.Refresh()

    try {
        $auditScript = Join-Path $root 'audit.ps1'
        $output = pwsh -NoProfile -File $auditScript -Verify 2>&1
        foreach($line in $output){
            Log $line
        }

        if($LASTEXITCODE -eq 0){
            $lblStatus.Text = "VERIFISERING BESTATT — alle filer er uendret"
            $lblStatus.ForeColor = $successColor
        } else {
            $lblStatus.Text = "VERIFISERING FEILET — filer kan ha blitt endret!"
            $lblStatus.ForeColor = $errorColor
        }
    } catch {
        Log "FEIL: $_"
        $lblStatus.Text = "FEIL"
        $lblStatus.ForeColor = $errorColor
    }

    $btnAudit.Enabled = $true
    $btnVerify.Enabled = $true
}

# ─── Event handlers ───
$btnAudit.Add_Click({ Run-Audit })
$btnVerify.Add_Click({ Run-Verify })
$btnReport.Add_Click({
    $reportPath = Join-Path $root 'output\rapport.txt'
    if(Test-Path $reportPath){
        Start-Process notepad.exe -ArgumentList $reportPath
    } else {
        [System.Windows.Forms.MessageBox]::Show("Rapport ikke funnet. Kjoer audit foerst.", "Feil")
    }
})

# ─── Show form ───
[void]$form.ShowDialog()
