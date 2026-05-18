```
░█████╗░██╗░░░░░██╗░░░░░░██████╗░░█████╗░████████╗██╗░░░██╗███╗░░██╗
██╔══██╗██║░░░░░██║░░░░░░██╔══██╗██╔══██╗╚══██╔══╝██║░░░██║████╗░██║
██║░░╚═╝██║░░░░░██║█████╗██████╦╝███████║░░░██║░░░██║░░░██║██╔██╗██║
██║░░██╗██║░░░░░██║╚════╝██╔══██╗██╔══██║░░░██║░░░██║░░░██║██║╚████║
╚█████╔╝███████╗██║░░░░░░██████╦╝██║░░██║░░░██║░░░╚██████╔╝██║░╚███║
░╚════╝░╚══════╝╚═╝░░░░░░╚═════╝░╚═╝░░╚═╝░░░╚═╝░░░░╚═════╝░╚═╝░░╚══╝
```

# alsosar-cli-wingettools

Winget tools for Windows management — batch uninstall, bulk upgrade, and printer cleanup.

## Usage

Run with no arguments for interactive mode:

```
batun
```

Or double-click `batun.bat` in Explorer.

### Run Directly From GitHub (no download required)

From **PowerShell 5+** (run as administrator for best results):

```
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/alsosar/alsosar-cli-wingettools/master/batun.ps1)))
```

## Options

| Key | Action |
|-----|--------|
| `U` | **Uninstall Programs** — browse, search, multi-select, and remove programs via winget. Lists Win32 apps from Programs and Features (registry). |
| `G` | **Upgrade All Software** — scans all installed packages with `winget upgrade` and bulk-upgrades everything to the latest version. |
| `P` | **Printer Cleanup** — lists all printers and ports, then removes them with a safety confirmation. |

### Uninstall key bindings

| Key | Action |
|-----|--------|
| Up/Down | Navigate list |
| PgUp/PgDn | Jump one page |
| Home/End | Jump to first/last item |
| Space | Toggle selection |
| `/` | Search/filter |
| Enter | Confirm and begin uninstall |
| `A` | Select all visible |
| `C` | Clear all |
| `R` | Reverse selection |
| `Q` / Esc | Quit / back |

## How it works

- **Uninstall** scans the registry for Win32 entries (Programs and Features), then removes via `winget uninstall` — no more fragile MSI/EXE dispatch.
- **Upgrade** runs `winget upgrade` to check for updates, then `winget upgrade --all` to apply them.
- **Printer cleanup** uses `Get-Printer` / `Get-PrinterPort` to enumerate, then `Remove-Printer` / `Remove-PrinterPort` to delete. Requires typing `REMOVE` to confirm.

## About

Winget tools for Windows management: batch uninstall, upgrade all, and printer cleanup
