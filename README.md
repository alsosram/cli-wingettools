```
░█████╗░██╗░░░░░██╗░░░░░░░██╗░░░░░░░██╗██╗███╗░░██╗░██████╗░███████╗████████╗████████╗░█████╗░░█████╗░██╗░░░░░░██████╗
██╔══██╗██║░░░░░██║░░░░░░░██║░░██╗░░██║██║████╗░██║██╔════╝░██╔════╝╚══██╔══╝╚══██╔══╝██╔══██╗██╔══██╗██║░░░░░██╔════╝
██║░░╚═╝██║░░░░░██║█████╗░╚██╗████╗██╔╝██║██╔██╗██║██║░░██╗░█████╗░░░░░██║░░░░░░██║░░░██║░░██║██║░░██║██║░░░░░╚█████╗░
██║░░██╗██║░░░░░██║╚════╝░░████╔═████║░██║██║╚████║██║░░╚██╗██╔══╝░░░░░██║░░░░░░██║░░░██║░░██║██║░░██║██║░░░░░░╚═══██╗
╚█████╔╝███████╗██║░░░░░░░░╚██╔╝░╚██╔╝░██║██║░╚███║╚██████╔╝███████╗░░░██║░░░░░░██║░░░╚█████╔╝╚█████╔╝███████╗██████╔╝
░╚════╝░╚══════╝╚═╝░░░░░░░░░╚═╝░░░╚═╝░░╚═╝╚═╝░░╚══╝░╚═════╝░╚══════╝░░░╚═╝░░░░░░╚═╝░░░░╚════╝░░╚════╝░╚══════╝╚═════╝░╝
```

# alsosar-cli-wingettools

Winget tools for Windows management — batch uninstall, bulk upgrade, and printer cleanup.

Two modes: **terminal** (keyboard-driven) and **GUI** (clickable window).

## Usage

### Terminal mode (default)

```powershell
irm https://raw.githubusercontent.com/alsosram/cli-wingettools/master/batun.ps1 | iex
```

Press a letter key to pick an option: `U` Uninstall, `G` Upgrade, `E` Export, `I` Import, `P` Printer Cleanup, `Q` Quit.

### GUI mode

```powershell
irm https://raw.githubusercontent.com/alsosram/cli-wingettools/master/batun.ps1 -GUI | iex
```

Opens a proper Windows window with buttons and a live output panel — no keyboard navigation needed.

## Options

| Key | Action |
|-----|--------|
| `U` | **Uninstall Programs** — browse, search, multi-select, and remove programs via winget. Lists Win32 apps from Programs and Features (registry). |
| `G` | **Upgrade All Software** — scans all installed packages with `winget upgrade` and bulk-upgrades everything to the latest version. |
| `E` | **Export packages** — saves your installed winget package list to a JSON file (defaults to desktop with timestamp). |
| `I` | **Import packages** — installs everything from a previously exported JSON file onto a new machine. |
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
- **Upgrade** runs `winget upgrade` to list outdated packages, then iterates each one with `winget upgrade <id>` to apply updates.
- **Export** runs `winget export -o <path>` to save all packages from configured sources into a portable JSON manifest.
- **Import** runs `winget import -i <path>` on that JSON — skips packages already installed, installs the rest.
- **Printer cleanup** uses `Get-Printer` / `Get-PrinterPort` to enumerate, then `Remove-Printer` / `Remove-PrinterPort` to delete. Requires typing `REMOVE` to confirm.

## About

Winget tools for Windows management: batch uninstall, upgrade all, and printer cleanup
