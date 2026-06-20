# Restic GUI

A GTK4 + libadwaita desktop app (written in Vala) for managing restic
repositories, scheduling backups via cron, and browsing/restoring snapshots.

## Features

- **Repositories**: add local/network, SFTP, S3, B2, or rest-server backed
  restic repos. Init, check connectivity, edit, delete.
- **Backup Jobs**: pick source paths, excludes, a cron schedule (presets or
  custom expression), and a retention policy (`restic forget --prune`).
  "Sync to crontab" writes everything into a clearly marked block in your
  user crontab — it never touches your other cron entries.
- **Snapshots**: pick a repo, browse its snapshots, restore to a folder you
  choose, or forget an individual snapshot.

## Build

On Arch :

```bash
sudo pacman -S vala gtk4 libadwaita meson ninja json-glib restic
meson setup build
ninja -C build
./build/restic-gui
```

On Debian/Ubuntu-based systems:

```bash
sudo apt install valac libgtk-4-dev libadwaita-1-dev libjson-glib-dev meson ninja-build restic
meson setup build
ninja -C build
./build/restic-gui
```

To install system-wide (adds it to your app launcher):

```bash
sudo meson install -C build
```

## Where things are stored

- `~/.config/restic-gui/repos.json` — repo definitions, **including
  passwords/credentials**. File is chmod'd to `0600`, but it's plaintext —
  see "Security notes" below if you want better-than-this.
- `~/.config/restic-gui/jobs.json` — job definitions.
- `~/.local/state/restic-gui/env/<repo-id>.env` — per-repo env files sourced
  by cron jobs at runtime (also `0600`).
- `~/.local/state/restic-gui/logs/<job-id>.log` — backup output logs.
- Crontab: a block delimited by
  `# >>> restic-gui managed jobs (do not edit by hand) >>>` /
  `# <<< restic-gui managed jobs <<<`. Anything outside that block in your
  existing crontab is preserved exactly as-is.

## Security notes (read this before pointing it at real data)

This first pass stores repo passwords and cloud credentials in plaintext
JSON/env files, just gated by Unix file permissions (`0600`, owner-only).
That's fine for a single-user homelab box you trust, but if you want it
hardened further, the natural next step is to swap `Repository.password`
storage for **libsecret** (GNOME Keyring) and have the cron job shell out
to `secret-tool lookup` instead of sourcing a flat env file. I didn't wire
that up yet — happy to add it if you want.

## Known rough edges / what's stubbed vs. real

- `restic ls` (browsing files inside a snapshot before restore) has a
  runner method (`list_snapshot_files`) but no UI yet — currently restore
  always restores the whole snapshot to a chosen folder.
- The Repos/Jobs page list-refresh rebuilds the whole `Adw.PreferencesGroup`
  each time rather than diffing rows — fine at homelab scale (a handful of
  repos/jobs), but not optimized for hundreds.
- No drag-and-drop reordering of jobs.
- `EntryRow` password fields don't have the "show/hide" eye icon wired up
  (GTK's `PasswordEntryRow` would be a nicer fit — easy follow-up).
- I haven't been able to compile this in my sandbox (no GTK4/Vala toolchain
  available there — only registry-mirror network access), so there may be
  a small API mismatch or two against your installed GTK4/libadwaita
  version once you build it for real. Most likely candidates: exact
  `Adw.Dialog`/`Adw.AlertDialog` constructor signatures and `Adw.SpinRow`
  availability — these shifted around libadwaita 1.4–1.6. If `meson setup`
  complains about a missing symbol, tell me the exact error and I'll patch
  it.

## Architecture

```
src/
  main.vala                 entry point
  application.vala          Adw.Application, owns stores/services
  models/
    repository.vala         Repository + BackendType
    backup-job.vala         BackupJob, builds the cron command line
    snapshot.vala           parsed `restic snapshots --json` entry
  services/
    restic-runner.vala      async wrapper around the restic CLI
    repo-store.vala         repos.json persistence
    job-store.vala          jobs.json persistence
    cron-manager.vala       safe managed-block crontab read/write
  ui/
    window.vala              Adw.NavigationSplitView shell
    repos-page.vala / repo-edit-dialog.vala
    jobs-page.vala / job-edit-dialog.vala
    snapshots-page.vala
```
