#Requires -Version 5.0

param(
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

function Show-Banner {
    $banner = @'
░█████╗░██╗░░░░░██╗░░░░░░██████╗░░█████╗░████████╗██╗░░░██╗███╗░░██╗
██╔══██╗██║░░░░░██║░░░░░░██╔══██╗██╔══██╗╚══██╔══╝██║░░░██║████╗░██║
██║░░╚═╝██║░░░░░██║█████╗██████╦╝███████║░░░██║░░░██║░░░██║██╔██╗██║
██║░░██╗██║░░░░░██║╚════╝██╔══██╗██╔══██║░░░██║░░░██║░░░██║██║╚████║
╚█████╔╝███████╗██║░░░░░░██████╦╝██║░░██║░░░██║░░░╚██████╔╝██║░╚███║
░╚════╝░╚══════╝╚═╝░░░░░░╚═════╝░╚═╝░░╚═╝░░░╚═╝░░░░╚═════╝░╚═╝░░╚══╝

                         alsosar-cli-wingettools
                      Winget tools for Windows management
'@
    Write-Host $banner -ForegroundColor Cyan
}

function WaitForKey {
    $null = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

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

            $uninstStr = ($item.UninstallString -or '')
            $sizeMB    = 0
            if ($item.EstimatedSize) { $sizeMB = [math]::Round($item.EstimatedSize / 1MB, 1) }

            $results.Add([PSCustomObject]@{
                DisplayName     = $name
                Publisher       = ($item.Publisher -or '')
                Version         = ($item.DisplayVersion -or '')
                SizeMB          = $sizeMB
                Type            = 'WIN32'
            })
        }
    }

    return $results | Sort-Object DisplayName
}

function Invoke-WingetUninstall {
    param([object]$Item)

    try {
        if ($WhatIf) {
            Write-Host "  [WHATIF] Would uninstall: $($Item.DisplayName)" -ForegroundColor DarkYellow
            return [PSCustomObject]@{ Name = $Item.DisplayName; Success = $true; ExitCode = 0; Error = '' }
        }

        Write-Host "  winget uninstall `"$($Item.DisplayName)`" ... " -NoNewline
        $output = winget uninstall "$($Item.DisplayName)" --accept-source-agreements 2>&1
        $exitCode = $LASTEXITCODE

        $ok = ($exitCode -eq 0)
        if ($ok) {
            Write-Host 'OK' -ForegroundColor Green
        } else {
            Write-Host 'FAILED' -ForegroundColor Red
            if ($output) { Write-Host "         $($output[-1])" -ForegroundColor DarkRed }
        }
        return [PSCustomObject]@{ Name = $Item.DisplayName; Success = $ok; ExitCode = $exitCode; Error = if (-not $ok) { "Exit code: $exitCode" } else { '' } }
    } catch {
        Write-Host 'FAILED' -ForegroundColor Red
        return [PSCustomObject]@{ Name = $Item.DisplayName; Success = $false; ExitCode = -1; Error = $_.Exception.Message }
    }
}

function Show-InteractiveMenu {
    param([object[]]$AllItems)

    $filterText  = ''
    $cursor      = 0
    $scrollPos   = 0
    $selected    = @{}
    $inFilter    = $false
    $quit        = $false
    $result      = $null

    $oldCursor = $host.UI.RawUI.CursorSize
    $host.UI.RawUI.CursorSize = 0

    function Get-Filtered {
        param([string]$F)
        if ([string]::IsNullOrWhiteSpace($F)) { return $AllItems }
        $f = $F.ToUpperInvariant()
        return $AllItems | Where-Object {
            $_.DisplayName.ToUpperInvariant().Contains($f) -or $_.Publisher.ToUpperInvariant().Contains($f)
        }
    }

    function Truncate {
        param([string]$S, [int]$MaxLen)
        if ($S.Length -le $MaxLen) { return $S.PadRight($MaxLen) }
        return $S.Substring(0, $MaxLen - 3) + '...'
    }

    do {
        $filtered = Get-Filtered -F $filterText
        $fc       = $filtered.Count

        $pageSize = 15
        if ($fc -eq 0) { $cursor = 0; $scrollPos = 0 }
        else {
            $pageNum = [Math]::Floor($cursor / $pageSize)
            $scrollPos = $pageNum * $pageSize
            $cursor = [Math]::Min($cursor, $fc - 1)
        }

        Clear-Host
        Show-Banner
        Write-Host ''

        if ($inFilter) {
            Write-Host "  SEARCH: $filterText" -NoNewline -ForegroundColor Yellow
            Write-Host '_' -NoNewline -ForegroundColor Green
            Write-Host '  (Enter=apply  Esc=cancel)'
            Write-Host ''
        } else {
            Write-Host '  [Up/Dn] Nav  [Space] Toggle  [/] Search  [Enter] Go  [Q] Quit' -ForegroundColor DarkGray
            Write-Host '  [A] All  [C] Clear  [R] Reverse  [PgUp/PgDn] Page' -ForegroundColor DarkGray
            Write-Host ''
        }

        $endIdx = [Math]::Min($scrollPos + $pageSize, $fc) - 1
        for ($i = $scrollPos; $i -le $endIdx; $i++) {
            $item = $filtered[$i]
            $isCurrent = ($i -eq $cursor)
            $isSel     = $selected.ContainsKey($AllItems.IndexOf($item))

            $arrow = if ($isCurrent) { '>' } else { ' ' }
            $check = if ($isSel) { 'x' } else { ' ' }

            $name  = Truncate -S $item.DisplayName -MaxLen 60
            $extra = ''
            if ($item.SizeMB -gt 0)  { $extra = " $($item.SizeMB) MB" }
            if ($item.Version)       { $extra += " v$($item.Version)" }
            $line = " $arrow [$check] $name$extra"

            if ($isCurrent) {
                Write-Host $line -ForegroundColor $host.UI.RawUI.ForegroundColor -BackgroundColor DarkBlue
            } elseif ($isSel) {
                Write-Host $line -ForegroundColor Green
            } else {
                Write-Host $line -ForegroundColor $host.UI.RawUI.ForegroundColor
            }
        }

        $drawn = $endIdx - $scrollPos + 1
        for ($i = $drawn; $i -lt $pageSize; $i++) {
            Write-Host ''
        }

        $selCount = $selected.Keys.Count
        $totalPages = [Math]::Max(1, [Math]::Ceiling($fc / $pageSize))
        $curPage = [Math]::Floor($cursor / $pageSize) + 1
        Write-Host '----------------------------------------------------------------------' -ForegroundColor DarkGray
        Write-Host "  Page $curPage/$totalPages  |  Selected: $selCount / $($AllItems.Count)" -NoNewline
        if ($filterText) { Write-Host "  |  Showing: $fc (filter: `"$filterText`")" -NoNewline }
        Write-Host "  |  Total: $($AllItems.Count)"
        Write-Host '----------------------------------------------------------------------' -ForegroundColor DarkGray

        $key = $host.UI.RawUI.ReadKey('IncludeKeyDown,NoEcho')
        $k   = $key.VirtualKeyCode

        if ($inFilter) {
            switch ($k) {
                13 { $inFilter = $false; $cursor = 0; $scrollPos = 0 }
                27 { $filterText = ''; $inFilter = $false; $cursor = 0; $scrollPos = 0 }
                8  {
                    if ($filterText.Length -gt 0) {
                        $filterText = $filterText.Substring(0, $filterText.Length - 1)
                    }
                }
                default {
                    if ($key.Character -gt 0x1f -and $key.Character -ne 0x7f) {
                        $filterText += [char]$key.Character
                    }
                }
            }
            continue
        }

        switch ($k) {
            38 {
                if ($cursor -gt 0) { $cursor-- }
                elseif ($fc -gt 0) { $cursor = $fc - 1 }
            }
            40 {
                if ($cursor -lt $fc - 1) { $cursor++ }
                else { $cursor = 0 }
            }
            33 { $cursor = [Math]::Max(0, $cursor - $pageSize) }
            34 { $cursor = [Math]::Min($fc - 1, $cursor + $pageSize) }
            36 { $cursor = 0 }
            35 { $cursor = $fc - 1 }
            32 {
                if ($fc -gt 0) {
                    $idx = $AllItems.IndexOf($filtered[$cursor])
                    if ($selected.ContainsKey($idx)) { $selected.Remove($idx) }
                    else { $selected[$idx] = $true }
                }
            }
            13 {
                if ($selected.Count -gt 0) {
                    $result = @($AllItems[$selected.Keys])
                    $quit = $true
                }
            }
            81 { $quit = $true }
            27 { $quit = $true }
            65 {
                $selected.Clear()
                foreach ($item in $filtered) {
                    $selected[$AllItems.IndexOf($item)] = $true
                }
            }
            67 { $selected.Clear() }
            82 {
                foreach ($item in $filtered) {
                    $idx = $AllItems.IndexOf($item)
                    if ($selected.ContainsKey($idx)) { $selected.Remove($idx) }
                    else { $selected[$idx] = $true }
                }
            }
            191 { $inFilter = $true; $filterText = '' }
        }
    } while (-not $quit)

    $host.UI.RawUI.CursorSize = $oldCursor
    Clear-Host
    Show-Banner
    return $result
}

function Invoke-BatchUninstall {
    param([object[]]$Items)

    $total   = $Items.Count
    $ok      = 0
    $failed  = 0

    Write-Host ''
    Write-Host "  Starting batch uninstall of $total program(s)..." -ForegroundColor Yellow
    Write-Host '  -------------------------------------------------' -ForegroundColor DarkGray

    for ($i = 0; $i -lt $total; $i++) {
        $item = $Items[$i]
        Write-Progress -Activity 'Batch Uninstall' -Status $item.DisplayName -PercentComplete (($i / $total) * 100) -CurrentOperation "$($i+1)/$total"

        Write-Host "  [$($i+1)/$total] " -NoNewline
        $result = Invoke-WingetUninstall -Item $item
        if ($result.Success) { $ok++ } else { $failed++ }
    }

    Write-Progress -Activity 'Batch Uninstall' -Completed

    Write-Host ''
    Write-Host '  -------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '  Batch uninstall complete: ' -NoNewline
    Write-Host "$ok succeeded" -NoNewline -ForegroundColor Green
    Write-Host ', ' -NoNewline
    Write-Host "$failed failed" -NoNewline -ForegroundColor Red
    Write-Host " / $total total"
}

function Clear-AllPrinters {
    $printers = Get-Printer -ErrorAction SilentlyContinue
    $ports = Get-PrinterPort -ErrorAction SilentlyContinue

    Clear-Host
    Show-Banner
    Write-Host ''
    Write-Host '  ⚠  WARNING: Printer Cleanup' -ForegroundColor Red
    Write-Host '  ===============================================' -ForegroundColor Red
    Write-Host '  This will remove ALL printers and printer ports' -ForegroundColor Yellow
    Write-Host '  from this computer, including network printers.' -ForegroundColor Yellow
    Write-Host '  ===============================================' -ForegroundColor Red
    Write-Host ''

    if ($printers) {
        Write-Host "  Printers to remove ($($printers.Count)):" -ForegroundColor DarkYellow
        foreach ($p in $printers) { Write-Host "    - $($p.Name)" }
        Write-Host ''
    }
    if ($ports) {
        Write-Host "  Ports to remove ($($ports.Count)):" -ForegroundColor DarkYellow
        foreach ($p in $ports) { Write-Host "    - $($p.Name)" }
        Write-Host ''
    }
    if (-not $printers -and -not $ports) {
        Write-Host '  No printers or ports found.' -ForegroundColor Green
        Write-Host ''
        Write-Host '  Press any key to continue...'
        WaitForKey
        return
    }

    Write-Host '  Type ' -NoNewline
    Write-Host 'REMOVE' -NoNewline -ForegroundColor Red
    Write-Host ' and press Enter to confirm, or press Enter to cancel:'
    Write-Host ''
    $input = Read-Host '  > '
    if ($input -ne 'REMOVE') {
        Write-Host '  Cancelled.' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  Press any key to continue...'
        WaitForKey
        return
    }

    Write-Host ''
    $ok = 0; $fail = 0

    if ($printers) {
        Write-Host '  Removing printers...' -ForegroundColor Yellow
        foreach ($p in $printers) {
            Write-Host "    $($p.Name) ... " -NoNewline
            try {
                Set-Printer -Name $p.Name -Shared $false -ErrorAction SilentlyContinue
                Remove-Printer -Name $p.Name -ErrorAction SilentlyContinue
                Write-Host 'OK' -ForegroundColor Green
                $ok++
            } catch {
                Write-Host 'FAILED' -ForegroundColor Red
                $fail++
            }
        }
    }

    if ($ports) {
        Write-Host '  Removing ports...' -ForegroundColor Yellow
        foreach ($p in $ports) {
            Write-Host "    $($p.Name) ... " -NoNewline
            try {
                Remove-PrinterPort -Name $p.Name -ErrorAction SilentlyContinue
                Write-Host 'OK' -ForegroundColor Green
                $ok++
            } catch {
                Write-Host 'FAILED' -ForegroundColor Red
                $fail++
            }
        }
    }

    Write-Host ''
    Write-Host '  Printer cleanup complete: ' -NoNewline
    Write-Host "$ok done" -NoNewline -ForegroundColor Green
    Write-Host ', ' -NoNewline
    Write-Host "$fail failed" -NoNewline -ForegroundColor Red
    Write-Host ''
    Write-Host ''
    Write-Host '  Press any key to continue...'
    WaitForKey
}

function Run-AllUpgrades {
    Write-Host '  Checking for available upgrades...' -ForegroundColor Yellow
    $raw = winget upgrade --accept-source-agreements 2>&1
    $exitCode = $LASTEXITCODE

    $lines = $raw -split "`r`n|`n"
    $headerIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^Name\s{2,}Id') { $headerIdx = $i; break }
    }

    $upgradable = @()
    if ($headerIdx -ge 0) {
        for ($i = $headerIdx + 2; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split '\s{2,}', 6
            if ($parts.Count -ge 4) {
                $upgradable += [PSCustomObject]@{
                    Name    = $parts[0].Trim()
                    Id      = $parts[1].Trim()
                    Version = $parts[2].Trim()
                    Available = $parts[3].Trim()
                }
            }
        }
    }

    if ($upgradable.Count -eq 0) {
        Write-Host '  All packages are up to date.' -ForegroundColor Green
        Write-Host ''
        Write-Host '  Press any key to continue...'
        WaitForKey
        return
    }

    Clear-Host
    Show-Banner
    Write-Host ''
    Write-Host "  $($upgradable.Count) upgrade(s) available:" -ForegroundColor Yellow
    Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkGray
    foreach ($p in $upgradable) {
        Write-Host "    $($p.Name) — $($p.Version) → $($p.Available)" -ForegroundColor DarkYellow
    }
    Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  [Y] Upgrade all' -ForegroundColor Green
    Write-Host '  [N] Cancel'
    Write-Host ''

    $key = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    if ([char]$key.Character -ne 'y' -and [char]$key.Character -ne 'Y') {
        Write-Host '  Cancelled.' -ForegroundColor DarkGray
        Write-Host '  Press any key to continue...'
        WaitForKey
        return
    }

    Clear-Host
    Show-Banner
    Write-Host ''
    Write-Host "  Upgrading $($upgradable.Count) package(s)..." -ForegroundColor Yellow
    Write-Host '  -------------------------------------------------' -ForegroundColor DarkGray

    $ok = 0; $fail = 0
    for ($i = 0; $i -lt $upgradable.Count; $i++) {
        $p = $upgradable[$i]
        Write-Progress -Activity 'Batch Upgrades' -Status $p.Name -PercentComplete (($i / $upgradable.Count) * 100) -CurrentOperation "$($i+1)/$($upgradable.Count)"
        Write-Host "  [$($i+1)/$($upgradable.Count)] $($p.Name) ... " -NoNewline

        $out = winget upgrade $p.Id --accept-source-agreements 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host 'OK' -ForegroundColor Green; $ok++
        } else {
            Write-Host 'FAILED' -ForegroundColor Red; $fail++
        }
    }
    Write-Progress -Activity 'Batch Upgrades' -Completed

    Write-Host ''
    Write-Host '  -------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '  Upgrades complete: ' -NoNewline
    Write-Host "$ok done" -NoNewline -ForegroundColor Green
    Write-Host ', ' -NoNewline
    Write-Host "$fail failed" -NoNewline -ForegroundColor Red
    Write-Host ''
    Write-Host ''
    Write-Host '  Press any key to continue...'
    WaitForKey
}

function Get-StarfieldKey {
    $width = [Console]::WindowWidth
    $height = [Console]::WindowHeight
    $starRows = [Math]::Max(1, $height - 15)

    $starChars = @('·', '∙', '°', '˙')
    $stars = 1..80 | ForEach-Object {
        [PSCustomObject]@{
            X = Get-Random -Max $width
            Y = (Get-Random -Max $starRows) + 15
            Dx = Get-Random -Minimum -1 -Maximum 2
            Dy = Get-Random -Minimum -1 -Maximum 2
            C = $starChars[(Get-Random -Max $starChars.Count)]
        }
    }

    $old = @{}
    foreach ($s in $stars) {
        $k = "$($s.X),$($s.Y)"
        $old[$k] = $s.C
        [Console]::SetCursorPosition($s.X, $s.Y)
        Write-Host $s.C -NoNewline -ForegroundColor DarkGray
    }
    [Console]::SetCursorPosition(0, [Math]::Min(16, $height - 1))

    do {
        Start-Sleep -Milliseconds 150

        foreach ($k in $old.Keys) {
            $p = $k -split ','
            [Console]::SetCursorPosition([int]$p[0], [int]$p[1])
            Write-Host ' ' -NoNewline
        }
        $old.Clear()

        foreach ($s in $stars) {
            $s.X = ($s.X + $s.Dx + $width) % $width
            $s.Y = ($s.Y + $s.Dy + $height) % $height
            if ($s.Y -lt 15) { $s.Y = 15 }

            if ((Get-Random -Max 12) -eq 0) { $s.C = $starChars[(Get-Random -Max $starChars.Count)] }
            if ((Get-Random -Max 20) -eq 0) { $s.Dx = Get-Random -Minimum -1 -Maximum 2; $s.Dy = Get-Random -Minimum -1 -Maximum 2 }

            $k = "$($s.X),$($s.Y)"
            $old[$k] = $s.C
            [Console]::SetCursorPosition($s.X, $s.Y)
            Write-Host $s.C -NoNewline -ForegroundColor DarkGray
        }
        [Console]::SetCursorPosition(0, [Math]::Min(16, $height - 1))

        if ($Host.UI.RawUI.KeyAvailable) {
            return $Host.UI.RawUI.ReadKey('IncludeKeyDown,NoEcho')
        }
    } while ($true)
}

# ------------------------------------------------------------------
#  MAIN
# ------------------------------------------------------------------

Clear-Host
Show-Banner
Write-Host ''

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host '  [!] Not running as Administrator.' -ForegroundColor Yellow
    Write-Host '  Some operations require elevation. Press any key to continue...'
    WaitForKey
}

$keepGoing = $true
while ($keepGoing) {
    Clear-Host
    Show-Banner
    Write-Host ''
    Write-Host '  [U] Uninstall Programs' -ForegroundColor Yellow
    Write-Host '  [G] Upgrade All Software (winget)' -ForegroundColor Green
    Write-Host '  [P] Printer Cleanup — remove all printers and ports' -ForegroundColor Red
    Write-Host '  [Q] Quit'
    Write-Host ''

    $modeKey = Get-StarfieldKey
    switch ([char]$modeKey.Character) {
        'g' { Run-AllUpgrades; continue }
        'G' { Run-AllUpgrades; continue }
        'p' { Clear-AllPrinters; continue }
        'P' { Clear-AllPrinters; continue }
        'q' { $keepGoing = $false; continue }
        'Q' { $keepGoing = $false; continue }
        'u' { }
        'U' { }
        default { continue }
    }

    Clear-Host
    Show-Banner
    Write-Host ''

    Write-Host '  Scanning Programs and Features... ' -NoNewline
    $all = Get-InstalledSoftware
    Write-Host "$($all.Count) programs found." -ForegroundColor Green
    Start-Sleep -Milliseconds 300

    if ($all.Count -eq 0) {
        Write-Host '  No installed programs found.' -ForegroundColor Red
        Write-Host ''
        Write-Host '  Press any key to continue...'
        WaitForKey
        continue
    }

    $progLoop = $true
    while ($progLoop) {
        $selected = Show-InteractiveMenu -AllItems $all
        if (-not $selected -or $selected.Count -eq 0) {
            $progLoop = $false
            continue
        }

        $confirmed = $false
        $doMenu = $true
        while ($doMenu) {
            Clear-Host
            Show-Banner
            Write-Host ''
            Write-Host '  ===============================================' -ForegroundColor Yellow
            Write-Host "  You are about to uninstall $($selected.Count) program(s):" -ForegroundColor Yellow
            foreach ($item in $selected) {
                Write-Host "    * $($item.DisplayName)" -ForegroundColor DarkYellow
            }
            Write-Host '  ===============================================' -ForegroundColor Yellow
            Write-Host ''
            Write-Host '  [Y] Proceed with uninstall' -ForegroundColor Green
            Write-Host '  [N] Cancel — back to program list' -ForegroundColor Yellow
            Write-Host '  [Q] Main menu'
            Write-Host ''

            $confirmKey = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            switch ([char]$confirmKey.Character) {
                'y' { $confirmed = $true; $doMenu = $false }
                'Y' { $confirmed = $true; $doMenu = $false }
                'n' { $doMenu = $false }
                'N' { $doMenu = $false }
                'q' { $doMenu = $false; $progLoop = $false }
                'Q' { $doMenu = $false; $progLoop = $false }
            }
        }

        if (-not $confirmed) { continue }

        Clear-Host
        Show-Banner
        Write-Host ''
        Invoke-BatchUninstall -Items $selected

        if ($isAdmin) {
            Write-Host ''
            Write-Host '  Tip: Some programs may leave leftovers. Consider running a cleanup tool.' -ForegroundColor DarkGray
        } else {
            Write-Host ''
            Write-Host '  Tip: Run as Administrator for better results with system-level programs.' -ForegroundColor DarkGray
        }

        Write-Host ''
        Clear-Host
        Show-Banner
        Write-Host ''
        Write-Host '  [Enter] Back to program list' -ForegroundColor Yellow
        Write-Host '  [M] Main menu'
        Write-Host ''
        $exitKey = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        if ($exitKey.VirtualKeyCode -eq 81) { $progLoop = $false }
    }
}
