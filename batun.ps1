#Requires -Version 5.0

$ErrorActionPreference = 'Stop'

function Show-AsosarBanner {
    $banner = @'
    _    _     ____   ___  ____    _    ____        ____ _     ___      ____    _  _____ _   _ _   _ 
   / \  | |   / ___| / _ \/ ___|  / \  |  _ \      / ___| |   |_ _|    | __ )  / \|_   _| | | | \ | |
  / _ \ | |   \___ \| | | \___ \ / _ \ | |_) |____| |   | |    | |_____|  _ \ / _ \ | | | | | |  \| |
 / ___ \| |___ ___) | |_| |___) / ___ \|  _ <_____| |___| |___ | |_____| |_) / ___ \| | | | |_| | |\  |
/_/   \_\_____|____/ \___/|____/_/   \_\_| \_\     \____|_____|___|    |____/_/   \_\_|  \___/|_| \_|
                                                                                                      
                        Windows Batch Uninstaller — Search & Multi-Select
'@
    Write-Host "`n$banner" -ForegroundColor Cyan
}

function WaitForKey {
    $null = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

function Show-MainMenu {
    Clear-Host
    Show-AsosarBanner
    Write-Host ''
    Write-Host '  [1] Uninstall Programs' -ForegroundColor Yellow
    Write-Host '  [2] Remove Printers / Ports' -ForegroundColor Yellow
    Write-Host '  [Q] Quit'
    Write-Host ''

    $key = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    switch ([char]$key.Character) {
        '1' { return 'programs' }
        '2' { return 'printers' }
        'q' { return 'quit' }
        'Q' { return 'quit' }
        default { return $null }
    }
}

function Get-WingetPackages {
    try {
        $raw = winget list --accept-source-agreements 2>$null
        if (-not $raw) { return @() }

        $lines = $raw -split "`r`n|`n"
        $headerIdx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^Name\s{2,}Id') {
                $headerIdx = $i
                break
            }
        }
        if ($headerIdx -lt 0) { return @() }

        $results = @()
        for ($i = $headerIdx + 2; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line.Trim() -eq '') { continue }

            $parts = $line -split '\s{2,}', 5
            if ($parts.Count -lt 3) { continue }

            $name = $parts[0].Trim()
            $id   = $parts[1].Trim()
            $ver  = $parts[2].Trim()

            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $results += [PSCustomObject]@{
                DisplayName = $name
                Id          = $id
                Version     = $ver
                Type        = 'WINGET'
            }
        }
        return $results | Sort-Object DisplayName
    } catch {
        return @()
    }
}

function Get-PrinterList {
    $printers = Get-Printer -ErrorAction SilentlyContinue
    if (-not $printers) { return @() }
    return $printers | ForEach-Object {
        [PSCustomObject]@{
            DisplayName = $_.Name
            Type        = 'PRINTER'
            Shared      = $_.Shared
            PortName    = $_.PortName
            DriverName  = $_.DriverName
        }
    } | Sort-Object DisplayName
}

function Get-PrinterPortList {
    $ports = Get-PrinterPort -ErrorAction SilentlyContinue
    if (-not $ports) { return @() }
    return $ports | ForEach-Object {
        [PSCustomObject]@{
            DisplayName = $_.Name
            Type        = 'PORT'
            Description = $_.Description
        }
    } | Sort-Object DisplayName
}

function Invoke-WingetUninstall {
    param([object]$Item)

    try {
        $id = $Item.Id
        if ([string]::IsNullOrWhiteSpace($id)) { $id = "`"$($Item.DisplayName)`"" }
        else { $id = "--id `"$id`"" }

        Write-Host "  Running: winget uninstall $id ... " -NoNewline
        $output = winget uninstall $id --accept-source-agreements 2>&1
        $exitCode = $LASTEXITCODE

        $ok = ($exitCode -eq 0)
        if ($ok) {
            Write-Host 'OK' -ForegroundColor Green
        } else {
            Write-Host 'FAILED' -ForegroundColor Red
            Write-Host "         Exit code: $exitCode" -ForegroundColor DarkRed
        }
        return [PSCustomObject]@{ Name = $Item.DisplayName; Success = $ok; ExitCode = $exitCode; Error = if (-not $ok) { "Exit code: $exitCode" } else { '' } }
    } catch {
        Write-Host 'FAILED' -ForegroundColor Red
        return [PSCustomObject]@{ Name = $Item.DisplayName; Success = $false; ExitCode = -1; Error = $_.Exception.Message }
    }
}

function Invoke-PrinterRemove {
    param([object]$Item)

    try {
        Write-Host "  Removing printer: $($Item.DisplayName) ... " -NoNewline
        Set-Printer -Name $Item.DisplayName -Shared $false -ErrorAction SilentlyContinue
        Remove-Printer -Name $Item.DisplayName -ErrorAction SilentlyContinue
        Write-Host 'OK' -ForegroundColor Green
        return [PSCustomObject]@{ Name = $Item.DisplayName; Success = $true; Error = '' }
    } catch {
        Write-Host 'FAILED' -ForegroundColor Red
        Write-Host "         $($_.Exception.Message)" -ForegroundColor DarkRed
        return [PSCustomObject]@{ Name = $Item.DisplayName; Success = $false; Error = $_.Exception.Message }
    }
}

function Invoke-PortRemove {
    param([object]$Item)

    try {
        Write-Host "  Removing port: $($Item.DisplayName) ... " -NoNewline
        Remove-PrinterPort -Name $Item.DisplayName -ErrorAction SilentlyContinue
        Write-Host 'OK' -ForegroundColor Green
        return [PSCustomObject]@{ Name = $Item.DisplayName; Success = $true; Error = '' }
    } catch {
        Write-Host 'FAILED' -ForegroundColor Red
        Write-Host "         $($_.Exception.Message)" -ForegroundColor DarkRed
        return [PSCustomObject]@{ Name = $Item.DisplayName; Success = $false; Error = $_.Exception.Message }
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
        return $AllItems | Where-Object { $_.DisplayName.ToUpperInvariant().Contains($f) }
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
        Show-AsosarBanner
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
            $typeTag = "[$($item.Type)]"

            $name  = Truncate -S $item.DisplayName -MaxLen 50
            $extra = ''
            if ($item.Version) { $extra += " v$($item.Version)" }
            $line = " $arrow [$check] $typeTag $name$extra"

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
    Show-AsosarBanner
    return $result
}

function Run-ProgramsMode {
    Write-Host '  Scanning with winget... ' -NoNewline
    $packages = Get-WingetPackages
    Write-Host "$($packages.Count) packages found." -ForegroundColor Green
    Start-Sleep -Milliseconds 300

    if ($packages.Count -eq 0) {
        Write-Host '  No packages found.' -ForegroundColor Red
        Write-Host '  Press any key to continue...'
        WaitForKey
        return
    }

    $keepGoing = $true
    while ($keepGoing) {
        $selected = Show-InteractiveMenu -AllItems $packages
        if (-not $selected -or $selected.Count -eq 0) { $keepGoing = $false; continue }

        $confirmed = $false
        $doMenu = $true
        while ($doMenu) {
            Clear-Host
            Show-AsosarBanner
            Write-Host ''
            Write-Host '  ===============================================' -ForegroundColor Yellow
            Write-Host "  Uninstall $($selected.Count) package(s):" -ForegroundColor Yellow
            foreach ($item in $selected) {
                Write-Host "    * $($item.DisplayName)" -ForegroundColor DarkYellow
            }
            Write-Host '  ===============================================' -ForegroundColor Yellow
            Write-Host ''
            Write-Host '  [Y] Proceed with uninstall' -ForegroundColor Green
            Write-Host '  [N] Cancel — back to list' -ForegroundColor Yellow
            Write-Host '  [Q] Quit'
            Write-Host ''

            $key = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            switch ([char]$key.Character) {
                'y' { $confirmed = $true; $doMenu = $false }
                'Y' { $confirmed = $true; $doMenu = $false }
                'n' { $doMenu = $false }
                'N' { $doMenu = $false }
                'q' { $doMenu = $false; $keepGoing = $false }
                'Q' { $doMenu = $false; $keepGoing = $false }
            }
        }

        if (-not $confirmed) { continue }

        Clear-Host
        Show-AsosarBanner
        Write-Host ''

        $total  = $selected.Count
        $ok     = 0
        $failed = 0
        for ($i = 0; $i -lt $total; $i++) {
            Write-Progress -Activity 'Batch Uninstall' -Status $selected[$i].DisplayName -PercentComplete (($i / $total) * 100) -CurrentOperation "$($i+1)/$total"
            Write-Host "  [$($i+1)/$total] " -NoNewline
            $result = Invoke-WingetUninstall -Item $selected[$i]
            if ($result.Success) { $ok++ } else { $failed++ }
        }
        Write-Progress -Activity 'Batch Uninstall' -Completed

        Write-Host ''
        Write-Host '  -------------------------------------------------' -ForegroundColor DarkGray
        Write-Host '  Complete: ' -NoNewline
        Write-Host "$ok succeeded" -NoNewline -ForegroundColor Green
        Write-Host ', ' -NoNewline
        Write-Host "$failed failed" -NoNewline -ForegroundColor Red
        Write-Host " / $total total"

        Write-Host ''
        Clear-Host
        Show-AsosarBanner
        Write-Host ''
        Write-Host '  [Enter] Back to program list' -ForegroundColor Yellow
        Write-Host '  [Q] Main menu'
        Write-Host ''
        $exitKey = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        if ($exitKey.VirtualKeyCode -eq 81) { $keepGoing = $false }
    }
}

function Run-PrintersMode {
    $keepGoing = $true
    while ($keepGoing) {
        Clear-Host
        Show-AsosarBanner
        Write-Host ''
        Write-Host '  [1] List / Remove Printers' -ForegroundColor Yellow
        Write-Host '  [2] List / Remove Printer Ports' -ForegroundColor Yellow
        Write-Host '  [3] Remove ALL printers and ports' -ForegroundColor Red
        Write-Host '  [Q] Back to main menu'
        Write-Host ''

        $key = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        switch ([char]$key.Character) {
            '1' {
                $printers = Get-PrinterList
                if ($printers.Count -eq 0) {
                    Write-Host ''; Write-Host '  No printers found.' -ForegroundColor Red; Write-Host '  Press any key...'; WaitForKey; continue
                }
                $selected = Show-InteractiveMenu -AllItems $printers
                if (-not $selected -or $selected.Count -eq 0) { continue }

                Clear-Host; Show-AsosarBanner; Write-Host ''
                Write-Host "  Removing $($selected.Count) printer(s)..." -ForegroundColor Yellow
                Write-Host '  -------------------------------------------------' -ForegroundColor DarkGray
                $ok = 0; $fail = 0
                foreach ($item in $selected) {
                    $r = Invoke-PrinterRemove -Item $item
                    if ($r.Success) { $ok++ } else { $fail++ }
                }
                Write-Host "  Done: $ok removed, $fail failed" -ForegroundColor Yellow
                Write-Host ''; Write-Host '  Press any key...'; WaitForKey
            }
            '2' {
                $ports = Get-PrinterPortList
                if ($ports.Count -eq 0) {
                    Write-Host ''; Write-Host '  No printer ports found.' -ForegroundColor Red; Write-Host '  Press any key...'; WaitForKey; continue
                }
                $selected = Show-InteractiveMenu -AllItems $ports
                if (-not $selected -or $selected.Count -eq 0) { continue }

                Clear-Host; Show-AsosarBanner; Write-Host ''
                Write-Host "  Removing $($selected.Count) port(s)..." -ForegroundColor Yellow
                Write-Host '  -------------------------------------------------' -ForegroundColor DarkGray
                $ok = 0; $fail = 0
                foreach ($item in $selected) {
                    $r = Invoke-PortRemove -Item $item
                    if ($r.Success) { $ok++ } else { $fail++ }
                }
                Write-Host "  Done: $ok removed, $fail failed" -ForegroundColor Yellow
                Write-Host ''; Write-Host '  Press any key...'; WaitForKey
            }
            '3' {
                Clear-Host; Show-AsosarBanner; Write-Host ''
                Write-Host '  This will remove ALL non-system printers and ports.' -ForegroundColor Red
                Write-Host '  [Y] Proceed  [N] Cancel'
                Write-Host ''
                $ck = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                if ([char]$ck.Character -ne 'y' -and [char]$ck.Character -ne 'Y') { continue }

                $printers = Get-PrinterList
                $ports = Get-PrinterPortList
                $ok = 0; $fail = 0

                Write-Host ''; Write-Host '  Removing printers...' -ForegroundColor Yellow
                foreach ($p in $printers) {
                    $r = Invoke-PrinterRemove -Item $p
                    if ($r.Success) { $ok++ } else { $fail++ }
                }
                Write-Host '  Removing ports...' -ForegroundColor Yellow
                foreach ($p in $ports) {
                    $r = Invoke-PortRemove -Item $p
                    if ($r.Success) { $ok++ } else { $fail++ }
                }
                Write-Host "  Done: $ok removed, $fail failed" -ForegroundColor Yellow
                Write-Host ''; Write-Host '  Press any key...'; WaitForKey
            }
            'q' { $keepGoing = $false }
            'Q' { $keepGoing = $false }
        }
    }
}

# ------------------------------------------------------------------
#  MAIN
# ------------------------------------------------------------------

Clear-Host
Show-AsosarBanner
Write-Host ''

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host '  [!] Not running as Administrator.' -ForegroundColor Yellow
    Write-Host '  Printer removal and some winget uninstalls require elevation. Continuing anyway.' -ForegroundColor DarkGray
    Write-Host '  Press any key to continue...'
    WaitForKey
}

$keepGoing = $true
while ($keepGoing) {
    $mode = Show-MainMenu
    switch ($mode) {
        'programs'  { Run-ProgramsMode }
        'printers'  { Run-PrintersMode }
        'quit'      { $keepGoing = $false }
    }
}
