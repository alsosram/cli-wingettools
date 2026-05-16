#Requires -Version 5.0

param(
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

function Show-AsosarBanner {
    $banner = @'
    _    _     ____   ___  ____    _    ____        ____ _     ___      ____    _  _____ _   _ _   _ 
   / \  | |   / ___| / _ \/ ___|  / \  |  _ \      / ___| |   |_ _|    | __ )  / \|_   _| | | | \ | |
  / _ \ | |   \___ \| | | \___ \ / _ \ | |_) |____| |   | |    | |_____|  _ \ / _ \ | | | | | |  \| |
 / ___ \| |___ ___) | |_| |___) / ___ \|  _ <_____| |___| |___ | |_____| |_) / ___ \| | | |_| | |\  |
/_/   \_\_____|____/ \___/|____/_/   \_\_| \_\     \____|_____|___|    |____/_/   \_\_|  \___/|_| \_|
                                                                                                     
                       Windows Batch Uninstaller — Search & Multi-Select
'@
    Write-Host "`n$banner" -ForegroundColor Cyan
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
            $prodCode  = ($item.PSChildName -or '')
            $isMSI     = ($item.WindowsInstaller -eq 1) -or ($uninstStr -match 'msiexec')
            $sizeMB    = 0
            if ($item.EstimatedSize) { $sizeMB = [math]::Round($item.EstimatedSize / 1MB, 1) }
            $type      = if ($isMSI) { 'MSI' } else { 'EXE' }
            $regPath   = $path -replace '\*$', $item.PSChildName
            $canUninst = $null -ne ($uninstStr -or $prodCode)

            $results.Add([PSCustomObject]@{
                DisplayName     = $name
                Publisher       = ($item.Publisher -or '')
                Version         = ($item.DisplayVersion -or '')
                UninstallString = $uninstStr
                QuietString     = ($item.QuietUninstallString -or '')
                ProductCode     = $prodCode
                InstallDate     = ($item.InstallDate -or '')
                SizeMB          = $sizeMB
                Type            = $type
                RegistryPath    = $regPath
                CanUninstall    = $canUninst
            })
        }
    }

    return $results | Sort-Object DisplayName
}

function Get-UninstallCommand {
    param([object]$Item)

    if ($Item.Type -eq 'MSI') {
        $code = $Item.ProductCode
        if ($code -match '^{?[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}}?$') {
            $code = $code -replace '^\{|\}$', ''
            return @{
                Command     = 'msiexec'
                Arguments   = "/x {$code} /qn /norestart"
                Method      = 'msiexec'
            }
        }
        $str = $Item.UninstallString
        if ($str -match 'msiexec') {
            $argPart = $str -replace 'msiexec\s*/i\s*', '/x '
            $argPart = $argPart -replace 'msiexec(/[a-z]+)*\s*', ''
            return @{
                Command     = 'msiexec'
                Arguments   = "$argPart /qn /norestart"
                Method      = 'msiexec'
            }
        }
    }

    $str = if ($Item.QuietString) { $Item.QuietString } else { $Item.UninstallString }
    if (-not $str) { return $null }

    return @{
        Command     = "$env:ComSpec"
        Arguments   = "/c `"$str`""
        Method      = 'cmd'
    }
}

function Invoke-UninstallItem {
    param([object]$Item)

    $cmd = Get-UninstallCommand -Item $Item
    if (-not $cmd) {
        return [PSCustomObject]@{ Name = $Item.DisplayName; Success = $false; ExitCode = -1; Error = 'No uninstall command available' }
    }

    try {
        if ($cmd.Method -eq 'msiexec') {
            $proc = Start-Process -FilePath $cmd.Command -ArgumentList $cmd.Arguments -Wait -PassThru -ErrorAction SilentlyContinue
        } elseif ($cmd.Method -eq 'powershell') {
            $proc = Start-Process -FilePath $cmd.Command -ArgumentList $cmd.Arguments -Wait -PassThru -ErrorAction SilentlyContinue
        } else {
            $proc = Start-Process -FilePath $cmd.Command -ArgumentList $cmd.Arguments -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
        }

        if ($null -eq $proc) {
            $proc = Start-Process -FilePath $cmd.Command -ArgumentList $cmd.Arguments -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
        }

        $exitCode = if ($proc) { $proc.ExitCode } else { -1 }
        $ok = ($exitCode -eq 0 -or $exitCode -eq 3010 -or $exitCode -eq 1641 -or $exitCode -eq 2359302)
        $errMsg = if ($ok -or $null -eq $proc) { '' } else { "Exit code: $exitCode" }
        return [PSCustomObject]@{ Name = $Item.DisplayName; Success = $ok; ExitCode = $exitCode; Error = $errMsg }
    } catch {
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
    $lastDrawnLines = 0

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

            $arrow = ' '
            if ($isCurrent) { $arrow = '>' }
            $check = ' '
            if ($isSel) { $check = 'x' }
            $typeTag = "[$($item.Type)]"

            $name  = Truncate -S $item.DisplayName -MaxLen 50
            $extra = ''
            if ($item.SizeMB -gt 0)  { $extra = " $($item.SizeMB) MB" }
            if ($item.Version)       { $extra += " v$($item.Version)" }
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
        Write-Host "  |  Total apps: $($AllItems.Count)"
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
    $host.UI.RawUI.CursorPosition = @{ X = 0; Y = 0 }
    Show-AsosarBanner
    return $result
}

function Invoke-BatchUninstall {
    param([object[]]$Items)

    $total   = $Items.Count
    $ok      = 0
    $failed  = 0
    $details = [System.Collections.Generic.List[PSObject]]::new()

    Write-Host ''
    Write-Host "  Starting batch uninstall of $total program(s)..." -ForegroundColor Yellow
    Write-Host '  -------------------------------------------------' -ForegroundColor DarkGray

    for ($i = 0; $i -lt $total; $i++) {
        $item = $Items[$i]
        Write-Progress -Activity 'Batch Uninstall' -Status $item.DisplayName -PercentComplete (($i / $total) * 100) -CurrentOperation "$($i+1)/$total"

        Write-Host "  [$($i+1)/$total] Uninstalling: " -NoNewline
        Write-Host $item.DisplayName -NoNewline

        $result = Invoke-UninstallItem -Item $item

        Write-Host ' ... ' -NoNewline
        if ($result.Success) {
            Write-Host 'OK' -ForegroundColor Green
            $ok++
        } else {
            Write-Host 'FAILED' -ForegroundColor Red
            if ($result.Error) { Write-Host "         $($result.Error)" -ForegroundColor DarkRed }
            $failed++
        }
        $details.Add($result)
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
    Write-Host '  Some uninstallers may fail without elevation. Press any key to continue...'
    $null = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

Write-Host '  Scanning installed software... ' -NoNewline
$all = Get-InstalledSoftware
Write-Host "$($all.Count) programs found." -ForegroundColor Green
Start-Sleep -Milliseconds 500

if ($all.Count -eq 0) {
    Write-Host '  No installed programs found.' -ForegroundColor Red
    Write-Host ''
    Write-Host '  Press any key to exit...'
    $null = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    return
}

$keepGoing = $true
while ($keepGoing) {
    $selected = Show-InteractiveMenu -AllItems $all
    if (-not $selected -or $selected.Count -eq 0) {
        Write-Host '  No programs selected. Exiting.' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  Press any key to exit...'
        $null = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        $keepGoing = $false
        continue
    }

    $confirmed = $false
    $doMenu = $true
    while ($doMenu) {
        Clear-Host
        Show-AsosarBanner
        Write-Host ''
        Write-Host '  ===============================================' -ForegroundColor Yellow
        Write-Host "  You are about to uninstall $($selected.Count) program(s):" -ForegroundColor Yellow
        foreach ($item in $selected) {
            Write-Host "    * $($item.DisplayName)  [$($item.Type)]" -ForegroundColor DarkYellow
        }
        Write-Host '  ===============================================' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  [Y] Proceed with uninstall' -ForegroundColor Green
        Write-Host '  [N] Cancel — back to program list' -ForegroundColor Yellow
        Write-Host '  [Q] Quit'
        Write-Host ''

        $confirmKey = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        switch ([char]$confirmKey.Character) {
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
    Show-AsosarBanner
    Write-Host ''
    Write-Host '  [Enter] Back to program list' -ForegroundColor Yellow
    Write-Host '  [Q] Quit'
    Write-Host ''
    $exitKey = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    if ($exitKey.VirtualKeyCode -eq 81) { $keepGoing = $false }
}
