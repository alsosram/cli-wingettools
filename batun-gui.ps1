#Requires -Version 5.0

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------------------------------------------------------------------------
#  Reuse existing logic from batun.ps1
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

function Get-InstalledSoftware {
    $results = [System.Collections.Generic.List[PSObject]]::new()
    $paths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($path in $paths) {
        $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
        if (-not $items) { continue }
        foreach ($item in $items) {
            $name = $item.DisplayName
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if ($item.SystemComponent -eq 1)  { continue }
            if ($name -match '^Update for|^Security Update|^Hotfix |^KB\d{6,}') { continue }
            $results.Add([PSCustomObject]@{
                DisplayName = $name
                Publisher   = ($item.Publisher -or '')
                Version     = ($item.DisplayVersion -or '')
                SizeMB      = 0
                Type        = 'WIN32'
            })
        }
    }
    return $results | Sort-Object DisplayName
}

function Invoke-WingetUninstall {
    param([string]$Name)
    $out = winget uninstall "`"$Name`"" --accept-source-agreements 2>&1
    return $LASTEXITCODE -eq 0
}

function Get-Upgradable {
    $raw = winget upgrade --accept-source-agreements 2>&1
    $lines = $raw -split "`r`n|`n"
    $headerIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^Name\s{2,}Id') { $headerIdx = $i; break }
    }
    $result = @()
    if ($headerIdx -ge 0) {
        for ($i = $headerIdx + 2; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split '\s{2,}', 6
            if ($parts.Count -ge 4) {
                $result += [PSCustomObject]@{
                    Name      = $parts[0].Trim()
                    Id        = $parts[1].Trim()
                    Version   = $parts[2].Trim()
                    Available = $parts[3].Trim()
                }
            }
        }
    }
    return $result
}

function Get-Printers { Get-Printer -ErrorAction SilentlyContinue }
function Get-PrinterPorts { Get-PrinterPort -ErrorAction SilentlyContinue }

# ---------------------------------------------------------------------------
#  GUI Builder
# ---------------------------------------------------------------------------

$font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Regular)
$fontBold = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$fontTitle = New-Object System.Drawing.Font('Consolas', 14, [System.Drawing.FontStyle]::Bold)
$bgColor = [System.Drawing.Color]::FromArgb(12, 12, 12)
$fgColor = [System.Drawing.Color]::FromArgb(0, 255, 0)
$accent = [System.Drawing.Color]::FromArgb(0, 180, 0)
$darkBorder = [System.Drawing.Color]::FromArgb(0, 80, 0)

function New-Button {
    param([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H, [scriptblock]$Action)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.Size = New-Object System.Drawing.Size($W, $H)
    $btn.Font = $fontBold
    $btn.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
    $btn.ForeColor = $fgColor
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderColor = $darkBorder
    $btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0, 40, 0)
    $btn.Add_Click($Action)
    return $btn
}

# Build form
$form = New-Object System.Windows.Forms.Form
$form.Text = '  VAULT-TEC PACKAGE TERMINAL  —  winget tools'
$form.Size = New-Object System.Drawing.Size(860, 640)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $bgColor
$form.ForeColor = $fgColor
$form.Font = $font
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

# Title
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = '╔══════════════════════════════════════╗'
$lblTitle.Font = $fontTitle
$lblTitle.ForeColor = $fgColor
$lblTitle.BackColor = $bgColor
$lblTitle.Location = New-Object System.Drawing.Point(20, 12)
$lblTitle.Size = New-Object System.Drawing.Size(800, 22)
$form.Controls.Add($lblTitle)

$lblTitle2 = New-Object System.Windows.Forms.Label
$lblTitle2.Text = '║   CLI-WINGETTOOLS — PACKAGE MANAGER  ║'
$lblTitle2.Font = $fontTitle
$lblTitle2.ForeColor = $fgColor
$lblTitle2.BackColor = $bgColor
$lblTitle2.Location = New-Object System.Drawing.Point(20, 36)
$lblTitle2.Size = New-Object System.Drawing.Size(800, 22)
$form.Controls.Add($lblTitle2)

$lblTitle3 = New-Object System.Windows.Forms.Label
$lblTitle3.Text = '╚══════════════════════════════════════╝'
$lblTitle3.Font = $fontTitle
$lblTitle3.ForeColor = $fgColor
$lblTitle3.BackColor = $bgColor
$lblTitle3.Location = New-Object System.Drawing.Point(20, 60)
$lblTitle3.Size = New-Object System.Drawing.Size(800, 22)
$form.Controls.Add($lblTitle3)

# Buttons
$btnY = 100
$btnH = 36
$btnGap = 8

$btnUninstall = New-Button -Text '  [U] Uninstall Programs' -X 30 -Y $btnY -W 240 -H $btnH -Action {
    $outputBox.Clear()
    $outputBox.AppendText("Scanning Programs and Features...`n")
    $all = Get-InstalledSoftware
    $outputBox.AppendText("  $($all.Count) programs found.`n`n")
    $form.Refresh()
    Show-ProgramPicker -AllItems $all
}
$form.Controls.Add($btnUninstall)

$btnUpgrade = New-Button -Text '  [G] Upgrade All Software' -X 30 -Y ($btnY + $btnH + $btnGap) -W 240 -H $btnH -Action {
    $outputBox.Clear()
    $outputBox.AppendText("Checking for available upgrades...`n")
    $form.Refresh()
    $list = Get-Upgradable
    if ($list.Count -eq 0) {
        $outputBox.AppendText("  All packages are up to date.`n")
        return
    }
    $outputBox.AppendText("  $($list.Count) upgrade(s) available.`n")
    foreach ($p in $list) {
        $outputBox.AppendText("    $($p.Name) — $($p.Version) → $($p.Available)`n")
    }
    $outputBox.AppendText("`nStarting upgrades...`n")
    $ok = 0; $fail = 0
    foreach ($p in $list) {
        $outputBox.AppendText("  $($p.Name) ... ")
        $form.Refresh()
        $out = winget upgrade $p.Id --accept-source-agreements 2>&1
        if ($LASTEXITCODE -eq 0) {
            $outputBox.AppendText("OK`n"); $ok++
        } else {
            $outputBox.AppendText("FAILED`n"); $fail++
        }
    }
    $outputBox.AppendText("`nDone — $ok succeeded, $fail failed.`n")
}
$form.Controls.Add($btnUpgrade)

$btnExport = New-Button -Text '  [E] Export Packages' -X 30 -Y ($btnY + 2*($btnH + $btnGap)) -W 240 -H $btnH -Action {
    $outputBox.Clear()
    $desktop = [Environment]::GetFolderPath('Desktop')
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = Join-Path $desktop "winget-packages-$ts.json"

    $outputBox.AppendText("Exporting to: $path`n")
    $form.Refresh()
    $out = winget export -o $path --accept-source-agreements 2>&1

    if ($LASTEXITCODE -eq 0) {
        $outputBox.AppendText("  Export complete.`n")
    } else {
        $outputBox.AppendText("  Export failed.`n")
    }
}
$form.Controls.Add($btnExport)

$btnImport = New-Button -Text '  [I] Import Packages' -X 30 -Y ($btnY + 3*($btnH + $btnGap)) -W 240 -H $btnH -Action {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
    $dlg.Title = 'Select a winget export file'
    if ($dlg.ShowDialog() -eq 'OK') {
        $outputBox.Clear()
        $outputBox.AppendText("Importing from: $($dlg.FileName)`n")
        $form.Refresh()
        $out = winget import -i $dlg.FileName --accept-source-agreements --accept-package-agreements 2>&1
        if ($LASTEXITCODE -eq 0) {
            $outputBox.AppendText("  Import complete.`n")
        } else {
            $outputBox.AppendText("  Import finished with issues.`n")
        }
    }
}
$form.Controls.Add($btnImport)

$btnPrinter = New-Button -Text '  [P] Printer Cleanup' -X 30 -Y ($btnY + 4*($btnH + $btnGap)) -W 240 -H $btnH -Action {
    $result = [System.Windows.Forms.MessageBox]::Show(
        'Remove ALL printers and printer ports?',
        'Printer Cleanup',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($result -eq 'No') { return }

    $outputBox.Clear()
    $ok = 0; $fail = 0
    $printers = Get-Printer -ErrorAction SilentlyContinue
    $ports = Get-PrinterPort -ErrorAction SilentlyContinue

    if ($printers) {
        $outputBox.AppendText("Removing printers...`n")
        foreach ($p in $printers) {
            try {
                Set-Printer -Name $p.Name -Shared $false -ErrorAction SilentlyContinue
                Remove-Printer -Name $p.Name -ErrorAction SilentlyContinue
                $outputBox.AppendText("  $($p.Name) ... OK`n"); $ok++
            } catch {
                $outputBox.AppendText("  $($p.Name) ... FAILED`n"); $fail++
            }
        }
    }
    if ($ports) {
        $outputBox.AppendText("Removing ports...`n")
        foreach ($p in $ports) {
            try {
                Remove-PrinterPort -Name $p.Name -ErrorAction SilentlyContinue
                $outputBox.AppendText("  $($p.Name) ... OK`n"); $ok++
            } catch {
                $outputBox.AppendText("  $($p.Name) ... FAILED`n"); $fail++
            }
        }
    }
    if (-not $printers -and -not $ports) {
        $outputBox.AppendText("  No printers or ports found.`n")
    } else {
        $outputBox.AppendText("`nDone — $ok removed, $fail failed.`n")
    }
}
$form.Controls.Add($btnPrinter)

# Output area
$grp = New-Object System.Windows.Forms.GroupBox
$grp.Text = '  OUTPUT'
$grp.Font = $fontBold
$grp.ForeColor = $fgColor
$grp.BackColor = $bgColor
$grp.Location = New-Object System.Drawing.Point(290, 90)
$grp.Size = New-Object System.Drawing.Size(540, 440)
$grp.FlatStyle = 'Flat'

$outputBox = New-Object System.Windows.Forms.RichTextBox
$outputBox.Location = New-Object System.Drawing.Point(10, 28)
$outputBox.Size = New-Object System.Drawing.Size(520, 400)
$outputBox.BackColor = [System.Drawing.Color]::FromArgb(8, 8, 8)
$outputBox.ForeColor = $fgColor
$outputBox.Font = $font
$outputBox.ReadOnly = $true
$outputBox.BorderStyle = 'None'
$outputBox.WordWrap = $true
$grp.Controls.Add($outputBox)
$form.Controls.Add($grp)

# Status bar
$status = New-Object System.Windows.Forms.Label
$status.Text = '  Ready  |  sosramalex/cli-wingettools'
$status.Font = $font
$status.ForeColor = $accent
$status.BackColor = [System.Drawing.Color]::FromArgb(8, 8, 8)
$status.Location = New-Object System.Drawing.Point(0, 560)
$status.Size = New-Object System.Drawing.Size(850, 24)
$status.BorderStyle = 'FixedSingle'
$form.Controls.Add($status)

# ---------------------------------------------------------------------------
#  Program picker sub-form
# ---------------------------------------------------------------------------

function Show-ProgramPicker {
    param([object[]]$AllItems)

    $picker = New-Object System.Windows.Forms.Form
    $picker.Text = 'Select Programs to Uninstall'
    $picker.Size = New-Object System.Drawing.Size(700, 550)
    $picker.StartPosition = 'CenterParent'
    $picker.BackColor = $bgColor
    $picker.ForeColor = $fgColor
    $picker.Font = $font
    $picker.FormBorderStyle = 'FixedSingle'
    $picker.MaximizeBox = $false
    $picker.MinimizeBox = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = '  Check the programs to uninstall:'
    $lbl.Location = New-Object System.Drawing.Point(10, 10)
    $lbl.Size = New-Object System.Drawing.Size(660, 20)
    $lbl.ForeColor = $fgColor
    $lbl.BackColor = $bgColor
    $picker.Controls.Add($lbl)

    $listBox = New-Object System.Windows.Forms.CheckedListBox
    $listBox.Location = New-Object System.Drawing.Point(10, 36)
    $listBox.Size = New-Object System.Drawing.Size(660, 420)
    $listBox.BackColor = [System.Drawing.Color]::FromArgb(12, 12, 12)
    $listBox.ForeColor = $fgColor
    $listBox.Font = $font
    $listBox.BorderStyle = 'None'
    $listBox.CheckOnClick = $true

    foreach ($item in $AllItems) {
        $display = "$($item.DisplayName)"
        if ($item.Version) { $display += "  v$($item.Version)" }
        [void]$listBox.Items.Add($display)
    }
    $picker.Controls.Add($listBox)

    $btnOk = New-Button -Text 'Uninstall Selected' -X 10 -Y 470 -W 200 -H 36 -Action {
        $selected = @()
        for ($i = 0; $i -lt $listBox.CheckedItems.Count; $i++) {
            $idx = $listBox.Items.IndexOf($listBox.CheckedItems[$i])
            $selected += $AllItems[$idx]
        }
        if ($selected.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('No programs selected.', 'Notice', 'OK', 'Information') | Out-Null
            return
        }
        $picker.Close()
        $form.Activate()

        $outputBox.Clear()
        $outputBox.AppendText("Uninstalling $($selected.Count) program(s)...`n")
        $ok = 0; $fail = 0
        foreach ($item in $selected) {
            $outputBox.AppendText("  $($item.DisplayName) ... ")
            $form.Refresh()
            $success = Invoke-WingetUninstall -Name $item.DisplayName
            if ($success) {
                $outputBox.AppendText("OK`n"); $ok++
            } else {
                $outputBox.AppendText("FAILED`n"); $fail++
            }
        }
        $outputBox.AppendText("`nDone — $ok uninstalled, $fail failed.`n")
    }
    $picker.Controls.Add($btnOk)

    $btnCancel = New-Button -Text 'Cancel' -X 220 -Y 470 -W 120 -H 36 -Action {
        $picker.Close()
    }
    $picker.Controls.Add($btnCancel)

    $picker.ShowDialog($form) | Out-Null
    $picker.Dispose()
}

# ---------------------------------------------------------------------------
#  Run
# ---------------------------------------------------------------------------

[void]$form.ShowDialog()
$form.Dispose()
