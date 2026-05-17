```
░█████╗░██╗░░░░░██╗░░░░░░██████╗░░█████╗░████████╗██╗░░░██╗███╗░░██╗
██╔══██╗██║░░░░░██║░░░░░░██╔══██╗██╔══██╗╚══██╔══╝██║░░░██║████╗░██║
██║░░╚═╝██║░░░░░██║█████╗██████╦╝███████║░░░██║░░░██║░░░██║██╔██╗██║
██║░░██╗██║░░░░░██║╚════╝██╔══██╗██╔══██║░░░██║░░░██║░░░██║██║╚████║
╚█████╔╝███████╗██║░░░░░░██████╦╝██║░░██║░░░██║░░░╚██████╔╝██║░╚███║
░╚════╝░╚══════╝╚═╝░░░░░░╚═════╝░╚═╝░░╚═╝░░░╚═╝░░░░╚═════╝░╚═╝░░╚══╝
```

# alsosar-cli-batun

Interactive batch uninstaller for Windows — browse, search, multi-select, and remove multiple programs at once. Supports both Win32 (MSI/EXE) and AppX (Windows Store) packages.

## Usage

Run with no arguments for interactive mode:

```
batun
```

From **CMD** or **PowerShell** with `-WhatIf` (preview only):

```
batun -WhatIf
```

Or double-click `batun.bat` in Explorer.

### Run Directly From GitHub (no download required)

From **PowerShell 5+** (run as administrator for best results):

```
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/alsosar/alsosar-cli-batun/master/batun.ps1)))
```

This downloads the script into memory and runs it immediately — no file saved to disk.

## Flags

| Flag | Description |
|------|-------------|
| `-WhatIf` | Preview what would be uninstalled without actually removing anything |

## Key bindings

| Key | Action |
|-----|--------|
| Up/Down | Navigate list (wraps to first/last page) |
| PgUp/PgDn | Jump one page |
| Home/End | Jump to first/last item |
| Space | Toggle selection |
| `/` | Search/filter |
| Enter | Confirm and begin uninstall |
| `A` | Select all visible |
| `C` | Clear all |
| `R` | Reverse selection |
| `Q` / Esc | Quit |

## How it works

The tool scans three registry locations for installed Win32 software plus all provisioned AppX packages. Each item shows its type (`[MSI]`, `[EXE]`, or `[APPX]`). When you initiate a batch uninstall:

- **MSI** packages are removed via `msiexec /x /qn` (silent)
- **EXE** packages use their registered `UninstallString` or `QuietUninstallString`
- **APPX** packages are removed via `Remove-AppxPackage`

All uninstall results (success/failure) are reported per-item during the batch process.

## About

Interactive batch uninstaller with search and multi-select
