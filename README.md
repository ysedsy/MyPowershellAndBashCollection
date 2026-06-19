# PC Maintenance Scripts

A small toolkit for cleaning up disk space, finding duplicate files safely, backing up folders, and reporting disk usage. Every script is available in both **PowerShell** (Windows) and **Bash** (Linux/macOS) versions with identical logic.

All destructive operations follow the same safety pattern: **dry-run first, confirm before acting, log everything, and provide an undo path.**

---

## Contents

| Tool | PowerShell | Bash | What it does | Modifies files? |
|------|-----------|------|--------------|-----------------|
| Cleanup + duplicate finder | `disk-cleanup.ps1` | `disk-cleanup.sh` | Clears temp files, finds and quarantines duplicates | Yes (with confirmation) |
| Undo | `disk-undo.ps1` | `disk-undo.sh` | Restores quarantined duplicates to their original location | Yes (restore only) |
| Backup mirror | `backup-mirror.ps1` | `backup-mirror.sh` | Mirrors folders to a backup destination | Yes (to destination) |
| Disk usage report | `disk-usage.ps1` | `disk-usage.sh` | Reports largest files, folders, and file types | No (read-only) |
| Disk usage + delete (GUI) | `disk-usage-gui.ps1` | `disk-usage-gui.sh` | Lists largest files, select via dialog, send to Recycle Bin / Trash | Yes (to Recycle Bin / Trash, recoverable) |

---

## Requirements

**Windows (PowerShell)**
- PowerShell 5.1+ (built into Windows 10/11)
- Run as Administrator if touching protected locations
- If script execution is blocked, run once per session: `Set-ExecutionPolicy -Scope Process Bypass`

**Linux / macOS (Bash)**
- **Bash 4+** for `disk-cleanup.sh` and `disk-undo.sh` (associative arrays)
  - Linux: default
  - macOS: ships bash 3.2 — install a newer one with `brew install bash` and run via `/opt/homebrew/bin/bash` (Apple Silicon) or `/usr/local/bin/bash` (Intel)
- `rsync` for the backup tool (preinstalled on both)
- Standard `find`, `du`, `df`, `stat`, and `md5`/`md5sum` (auto-detected GNU vs BSD)
- For the GUI delete tool (`disk-usage-gui.sh`):
  - Linux dialog: `zenity` (`sudo apt install zenity`) — otherwise falls back to a terminal selector
  - Linux trash: `trash-cli` (`sudo apt install trash-cli`) or GNOME's `gio`
  - macOS uses built-in `osascript` for both the dialog and Trash — no install needed
- Make executable first: `chmod +x *.sh`

---

## 1. Cleanup + Duplicate Finder

Clears old temp files, then finds true duplicates (matched by **content hash**, not filename) and moves them to a quarantine folder for review. Nothing is deleted outright — you delete the quarantine folder yourself once satisfied.

### Usage

**PowerShell**
```powershell
.\disk-cleanup.ps1                                   # report only (dry-run)
.\disk-cleanup.ps1 -RemoveDuplicates                 # move duplicates (asks first)
.\disk-cleanup.ps1 -ScanPaths "D:\Photos","E:\Docs"  # custom folders
.\disk-cleanup.ps1 -MaxDuplicates 1000 -MinSizeKB 50 # tune limits
```

**Bash**
```bash
./disk-cleanup.sh                                    # report only (dry-run)
./disk-cleanup.sh --remove                           # move duplicates (asks first)
./disk-cleanup.sh --paths ~/Photos ~/Docs            # custom folders
./disk-cleanup.sh --max 1000 --min-kb 50             # tune limits
```

### Parameters

| PowerShell | Bash | Default | Meaning |
|-----------|------|---------|---------|
| `-ScanPaths` | `--paths` | Downloads, Documents | Folders to scan |
| `-RemoveDuplicates` | `--remove` | off (report only) | Actually move duplicates |
| `-MaxDuplicates` | `--max` | 500 | Abort if more duplicates than this are found |
| `-MinSizeKB` | `--min-kb` | 10 | Ignore files smaller than this |

### Built-in protections

- **Protected folders** — system paths (`Windows`, `Program Files`, `/usr`, `/etc`, `/System`, etc.) and cloud-sync folders (OneDrive, Dropbox) are blocked from scanning.
- **Protected folder names** — `.git`, `.svn`, `node_modules` are skipped wherever they appear.
- **Protected file types** — executables and system files (`.exe`, `.dll`, `.so`, `.dylib`, `.ini`, etc.) are never treated as duplicates.
- **Symlink/junction safe** — links are not followed.
- **Minimum size** — tiny files are ignored.
- **Count limit** — aborts if the duplicate count exceeds the limit (catches misconfigured paths).
- **Whitelist confirmation** — shows the final scan list and asks before starting.
- **Hash re-check** — each file is re-hashed immediately before moving; if it (or the file being kept) changed since the scan, it is skipped.
- **Logging** — every action is timestamped in the quarantine folder.

### What "keep" means

Within each group of identical files, the **oldest** file (by modification time) is kept as the original. All newer copies are moved to quarantine.

---

## 2. Undo

Moves everything from a cleanup run back to its original location using the map file that the cleanup script generated.

**PowerShell**
```powershell
.\disk-undo.ps1 -MapFile "$env:USERPROFILE\_Duplicates_Quarantine\undo_map_20260618_143000.csv"
```

**Bash**
```bash
./disk-undo.sh ~/_Duplicates_Quarantine/undo_map_20260618_143000.csv
```

It will not overwrite a file that already exists at the original location — those are skipped and reported.

---

## 3. Backup Mirror

Copies folders to a backup destination (local drive or network share). Uses `robocopy` on Windows and `rsync` on Unix. Defaults to a **dry-run** and to **copy mode** (the safe combination).

**PowerShell**
```powershell
.\backup-mirror.ps1 -Destination "E:\Backup"                    # dry-run
.\backup-mirror.ps1 -Destination "E:\Backup" -Run               # copy for real
.\backup-mirror.ps1 -Destination "E:\Backup" -Run -Mirror       # exact mirror
.\backup-mirror.ps1 -Sources "C:\Work","D:\Media" -Destination "\\NAS\backup" -Run
```

**Bash**
```bash
./backup-mirror.sh --dest /mnt/backup                           # dry-run
./backup-mirror.sh --dest /mnt/backup --run                     # copy for real
./backup-mirror.sh --dest /mnt/backup --run --mirror            # exact mirror
./backup-mirror.sh --sources ~/Work ~/Media --dest /mnt/nas --run
```

### Copy vs Mirror

- **Copy mode** (default) — adds new and updated files to the destination. Never deletes anything.
- **Mirror mode** (`-Mirror` / `--mirror`) — makes the destination *exactly* match the source, **deleting** files in the destination that no longer exist in the source. Requires typing `MIRROR` to confirm. There is no undo for mirror deletions.

Each source folder is copied into a subfolder of the destination named after the source (e.g. `Documents/` → `E:\Backup\Documents\`). Logs are written to `_BackupLogs`.

---

## 4. Disk Usage Report

Read-only. Shows the largest files, the largest top-level folders, and a breakdown of space by file type. Changes nothing.

**PowerShell**
```powershell
.\disk-usage.ps1                                     # scan home folder
.\disk-usage.ps1 -Path "C:\" -TopFiles 30            # whole drive, top 30 files
.\disk-usage.ps1 -Path "D:\Media" -MinSizeMB 100
```

**Bash**
```bash
./disk-usage.sh                                      # scan home folder
./disk-usage.sh --path / --top-files 30              # whole drive, top 30 files
./disk-usage.sh --path ~/Media --min-mb 100
```

| PowerShell | Bash | Default | Meaning |
|-----------|------|---------|---------|
| `-Path` | `--path` | home folder | Where to scan |
| `-TopFiles` | `--top-files` | 20 | How many large files to list |
| `-TopFolders` | `--top-folders` | 15 | How many large folders to list |
| `-MinSizeMB` | `--min-mb` | 50 | Ignore files smaller than this in the file list |

Scanning an entire drive can be slow, since every file is examined. For a quick look, point it at a specific folder.

---

## 5. Disk Usage + Delete (GUI)

Like the report above, but interactive: it lists the largest files and lets you **select which to delete through a dialog**. Selected files go to the **Recycle Bin (Windows)** or **Trash (Linux/macOS)**, so they remain recoverable — nothing is permanently deleted.

**PowerShell** — opens a checkbox grid (WinForms):
```powershell
.\disk-usage-gui.ps1                                 # scan home folder, files >= 50 MB
.\disk-usage-gui.ps1 -Path "D:\Media" -MinSizeMB 100
.\disk-usage-gui.ps1 -Path "C:\" -TopFiles 200
```

**Bash** — graphical picker if available, terminal selector otherwise:
```bash
./disk-usage-gui.sh                                  # scan home folder
./disk-usage-gui.sh --path ~/Media --min-mb 100
./disk-usage-gui.sh --path / --top-files 200
```

| PowerShell | Bash | Default | Meaning |
|-----------|------|---------|---------|
| `-Path` | `--path` | home folder | Where to scan |
| `-TopFiles` | `--top-files` | 100 | How many large files to list |
| `-MinSizeMB` | `--min-mb` | 50 | Ignore files smaller than this |

### How the dialog and deletion work per platform

- **Windows** — a full checkbox grid (size + path columns). Selected files are sent to the Recycle Bin via the `Microsoft.VisualBasic.FileIO` API, exactly like deleting from Explorer.
- **Linux** — a `zenity` checklist dialog if `zenity` is installed; otherwise a numbered terminal multi-select. Files go to Trash via `trash-put` or `gio trash`.
- **macOS** — a native multi-select list via `osascript` (shows paths only — sizes don't fit that dialog type). Files go to Trash via Finder.

Every deletion is confirmed before it happens, and because files land in the Recycle Bin / Trash you can restore them from there if needed.

---

## Recommended workflow

1. **See what you have** — run the disk-usage report to find what's taking space.
2. **Delete the obvious junk** — use the GUI tool to pick large files and send them to the Recycle Bin / Trash (recoverable).
3. **Find duplicates safely** — run the cleanup script with no flags (report only) and review.
4. **Quarantine** — re-run with `-RemoveDuplicates` / `--remove`; files move to the quarantine folder, not the trash.
5. **Verify** — check the quarantine folder. If something is wrong, run the undo script.
6. **Finalize** — once satisfied, delete the quarantine folder yourself.
7. **Back up** — mirror your important folders to an external drive (dry-run first, then `-Run`).

---

## Safety notes

- These tools default to the cautious option everywhere: report before acting, copy before mirror, quarantine before delete.
- Nothing is ever hard-deleted by the cleanup script — it only *moves* files, and logs every move.
- The backup mirror mode is the one genuinely irreversible operation; it requires explicit typed confirmation and has no undo.
- Always run a dry-run first when trying new paths or options.
- Do not point the cleanup tool at system or program directories; the protections block the common ones, but custom install locations are your responsibility.
