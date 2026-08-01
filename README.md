# ScummVM Nightly in Distrobox

This repository-sized setup consists of one Bash script that creates a clean Debian 13 Distrobox for the current ScummVM master nightly build.

It is intended for immutable or container-oriented Linux desktops such as Bazzite, Fedora Atomic, Kinoite and Silverblue, but it works for normal Linux user profiles as long as Distrobox and rootless Podman are available.

## Contents

- [What the Script Does](#what-the-script-does)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Command-Line Options](#command-line-options)
- [Host Commands](#host-commands)
- [Automatic Update Behavior](#automatic-update-behavior)
- [Flatpak Installation Safety](#flatpak-installation-safety)
- [Flatpak Configuration Import](#flatpak-configuration-import)
- [Flatpak Save Game Import](#flatpak-save-game-import)
- [Flatpak Extras Import](#flatpak-extras-import)
- [Profile and XDG Support](#profile-and-xdg-support)
- [Default Paths](#default-paths)
- [Additional Host Mounts](#additional-host-mounts)
- [MIDI, MT-32, and Text-to-Speech](#midi-mt-32-and-text-to-speech)
- [Other Console Messages](#other-console-messages)
- [Troubleshooting](#troubleshooting)
- [Rebuilding](#rebuilding)
- [Uninstalling](#uninstalling)
- [Upstream References](#upstream-references)

## What the Script Does

The script:

- removes and recreates the `scummvm-nightly` Distrobox
- uses the official Debian 13 container image by default
- downloads the official ScummVM master nightly archive
- installs the libraries required by the Debian nightly build
- installs FluidSynth and, when available, a General MIDI soundfont
- installs Speech Dispatcher with the eSpeak NG output module
- imports the official Flatpak ScummVM configuration only when that configuration exists
- preserves an existing nightly configuration when no Flatpak configuration exists
- preserves save games and persistent engine data
- creates read/write host mounts by default for common external-storage locations
- creates host commands for launching, updating and diagnosing the installation
- creates a desktop entry named **ScummVM Nightly**
- checks for an update every time ScummVM Nightly starts
- falls back to the last working build when an automatic update fails

## Requirements

Run the setup on the Linux host as a normal desktop user.

### Required Host Tools

- Bash 4 or newer
- Distrobox
- rootless Podman
- `curl`
- standard GNU utilities such as `find`, `awk` and `readlink`

`grep`, `tar` and `ldd` are also used, but only inside the Distrobox, where they are guaranteed by Debian's essential package set — no separate host installation is needed.

### The Script Deliberately Refuses to Run

- as root
- from inside a container
- when Podman is unavailable for the current user

### Supported Architectures

The default nightly URLs support:

- x86_64 / amd64
- i386 through i686

For another architecture, provide a compatible official `.tar.xz` archive with `--nightly-url`.

## Quick Start

Make the script executable and run it:

```bash
chmod +x setup-scummvm-nightly-distrobox.sh
./setup-scummvm-nightly-distrobox.sh
```

Run without the confirmation prompt:

```bash
./setup-scummvm-nightly-distrobox.sh --yes
```

The first run downloads a container image, installs Debian packages and downloads a ScummVM nightly archive of roughly 100 MB.

## Command-Line Options

| Option | Description |
| --- | --- |
| `--yes` | Rebuild without an interactive confirmation. |
| `--rw` | Mount additional host paths read/write. This is the default. |
| `--ro` | Mount additional host paths read-only. |
| `--mount PATH` | Add a host path. The option may be specified repeatedly. |
| `--no-flatpak-config` | Do not import the Flatpak ScummVM configuration. |
| `--box NAME` | Use a different Distrobox name. |
| `--image IMAGE` | Use another Debian-compatible container image. |
| `--nightly-url URL` | Override the official nightly archive URL. The archive must use the expected `.tar.xz` layout. |
| `--help` | Show the built-in help. |

Example with selected game directories:

```bash
./setup-scummvm-nightly-distrobox.sh --yes \
  --mount "/run/media/$USER/Games" \
  --mount "/mnt/DOS-Games"
```

Example with read-only access to the mounted paths:

```bash
./setup-scummvm-nightly-distrobox.sh --yes --ro \
  --mount "/run/media/$USER/Games"
```

Mounts are read/write by default. Pass `--ro` if you'd rather ScummVM not be able to modify files on the mounted paths — this is a reasonable choice for game installations, since ScummVM save games are stored separately in the user profile either way and remain writable regardless of this setting.

## Host Commands

After setup, these commands are created in `~/.local/bin` by default:

- `scummvm-nightly`
- `scummvm-nightly-update`
- `scummvm-nightly-doctor`

### Start ScummVM

```bash
scummvm-nightly
```

The launcher checks for a newer nightly build before starting ScummVM.

### Start Once Without Checking for an Update

```bash
SCUMMVM_NIGHTLY_SKIP_UPDATE=1 scummvm-nightly
```

### Run the Updater Manually

```bash
scummvm-nightly-update
```

### Run Diagnostics

```bash
scummvm-nightly-doctor
```

The doctor reports:

- the installed ScummVM version
- the binary and data paths
- unresolved shared-library dependencies
- important data files
- configuration status
- save-directory writability
- visibility of the configured host mounts

If `~/.local/bin` is not in `PATH`, use the full path or add it to your shell configuration.

## Automatic Update Behavior

The updater uses the official `*-master-latest.tar.xz` archive and an HTTP conditional request.

When a new build is available, it:

- downloads to a temporary file
- validates the archive before accepting it
- extracts into a separate staging directory
- locates and tests the ScummVM executable
- checks all dynamically linked libraries with `ldd`
- copies persistent engine data into the new build
- replaces the installed build atomically

If validation fails, the installed build remains unchanged.

After a successful update, the previous build is kept on disk rather than deleted, so a working fallback build is always available on disk; the next successful update overwrites that retained copy with whatever build it replaces at that time.

If the update check fails during normal launch, for example because the machine is offline, the launcher starts the last working build. The first installation still requires a successful download because no fallback build exists yet.

A file lock prevents two simultaneous updater processes from modifying the installation at the same time.

## Flatpak Installation Safety

The existing Flatpak installation is left completely untouched.

The setup script:

- never runs `flatpak uninstall`, `flatpak remove` or another Flatpak management command
- never deletes or changes files below `~/.var/app/org.scummvm.ScummVM`
- reads the Flatpak `scummvm.ini` only when it exists
- copies that file into the separate nightly profile; it never moves or edits the original
- refuses custom managed paths that point into the Flatpak profile or would contain it

The installed Flatpak application, its configuration, save games and application data therefore remain available exactly as before.

## Flatpak Configuration Import

The script looks for the official Flatpak application ID: `org.scummvm.ScummVM`.

The usual source file is:

```
~/.var/app/org.scummvm.ScummVM/config/scummvm/scummvm.ini
```

The behavior is intentionally conservative:

- **Flatpak configuration exists**: it is copied to the nightly profile.
- **Flatpak configuration does not exist**: an existing nightly configuration is retained.
- **Neither configuration exists**: ScummVM creates a new one on first launch.
- **`--no-flatpak-config` is used**: the Flatpak file is ignored, but an existing nightly configuration is still retained.

Before any possible import, an existing nightly configuration is backed up with a timestamp.

A copied Flatpak configuration may contain document-portal paths under `/run/user/.../doc/...`. These paths may not work outside the Flatpak sandbox. Re-add the affected game directory in ScummVM using its normal host path.

## Flatpak Save Game Import

Alongside the configuration, existing Flatpak save games are copied into the nightly saves folder once, so games default to the correct location with their existing saves already present, instead of relying on any per-game path configuration.

The usual source directory is:

```
~/.var/app/org.scummvm.ScummVM/data/scummvm/saves
```

If that exact directory isn't found, the script falls back to searching for a `saves` directory anywhere under the Flatpak profile. Existing files in the nightly saves folder are never overwritten during this first pass — only files that don't already exist there are copied.

The script then checks the `savepath` actually configured in the imported Flatpak configuration. If it points somewhere other than the default directory above, save games are copied from there too — this second pass is allowed to overwrite files, since the explicitly configured path is assumed to hold the more recently used saves.

This runs whenever Flatpak import isn't disabled (`--no-flatpak-config` skips it, the same as the configuration import).

## Flatpak Extras Import

Soundfonts, MT-32/CM-32L ROMs, custom shaders, and any other extra data ScummVM's Flatpak install has accumulated are also picked up and copied wholesale into the persistent engine-data directory, which every nightly build (and rebuild) automatically picks up. Nothing already present in the nightly profile is ever overwritten by this step.

Three source directories are copied in full, whichever of them exist and contain anything:

- `~/.var/app/org.scummvm.ScummVM/data/scummvm` — ScummVM's own Flatpak data folder. This is where soundfonts, ROMs, or shader/icon packs typically end up if the Flatpak install was left on its default paths (for example, packs downloaded via ScummVM's own "Update Shaders" button land here unless the Icon Path was customized).
- The Extra Path directory declared in the imported configuration, if one was explicitly set (ScummVM's own convention for soundfonts, MT-32/CM-32L ROMs, and other misc extra files).
- The Icon Path directory declared in the imported configuration, if one was explicitly set (ScummVM's own convention for shader and icon packs — a separate setting from Extra Path, not a typo).

Because whole directories are copied as-is rather than filtered by file type, internal folder structure is preserved — this matters for shader packs, since ScummVM's `.glslp` presets reference sibling files by relative path. A side effect is that if the Flatpak data folder still has its `saves` subdirectory, a redundant copy of it may also land in the engine-data directory; this is harmless, since ScummVM does not look for save games there.

Like the other Flatpak imports, this runs whenever Flatpak import isn't disabled (`--no-flatpak-config` skips it too).

## Profile and XDG Support

No username is hard-coded.

The setup derives paths from:

- `$HOME`
- `$XDG_CONFIG_HOME`
- `$XDG_DATA_HOME`
- `$XDG_CACHE_HOME`

Relative or invalid XDG values fall back to their standard locations.

The resolved paths are stored in a private runtime file:

```
$XDG_CONFIG_HOME/scummvm-nightly/runtime.env
```

This lets the launcher, updater and doctor use the same profile paths even when started from a desktop menu with a smaller environment.

Optional environment overrides:

| Variable | Purpose |
| --- | --- |
| `SCUMMVM_NIGHTLY_BIN_DIR` | Directory for the host commands. |
| `SCUMMVM_NIGHTLY_ROOT` | Installed nightly program files. |
| `SCUMMVM_NIGHTLY_CACHE` | Download and update cache. |
| `SCUMMVM_NIGHTLY_CONFIG_DIR` | Nightly configuration directory. |
| `SCUMMVM_NIGHTLY_CONFIG` | Exact `scummvm.ini` path. |
| `SCUMMVM_NIGHTLY_DATA` | Persistent data root. |
| `SCUMMVM_NIGHTLY_SAVES` | Save-game directory. |
| `SCUMMVM_NIGHTLY_ENGINE_DATA` | Persistent additional engine files. |

For safety, managed setup paths must remain inside the current user's home directory.

## Default Paths

With standard XDG settings, the setup uses:

| Purpose | Path |
| --- | --- |
| Nightly program files | `~/.local/opt/scummvm-nightly` |
| Configuration | `~/.config/scummvm-nightly/scummvm.ini` |
| Runtime settings | `~/.config/scummvm-nightly/runtime.env` |
| Save games | `~/.local/share/scummvm-nightly/saves` |
| Persistent engine data | `~/.local/share/scummvm-nightly/engine-data` |
| Download cache | `~/.cache/scummvm-nightly` |
| Host commands | `~/.local/bin` |
| Desktop entry | `~/.local/share/applications/scummvm-nightly.desktop` |

The setup removes only the Distrobox, the nightly program directory and its download cache. It does not remove the configuration, saves or persistent engine-data directory.

The official nightly archive unpacks into a nested wrapper directory (for example `debian-x86-64-master-<hash>/scummvm/`). The updater flattens this automatically, so the `scummvm` binary and its `data` folder end up directly under the nightly program files path above rather than several levels deep.

## Additional Host Mounts

Without explicit `--mount` options, the script discovers candidate directories automatically:

- every existing subdirectory of `/run/media` (not just one named after the current user — automount services can use other names, such as `system` or `media-automount`)
- every existing subdirectory of `/media`
- `/mnt`
- `/var/mnt`

When run interactively, selection happens in two steps:

1. The discovered top-level directories are listed and you choose which ones to use by number (press Enter for all, or type `none`).
2. For each one chosen, its own subdirectories are listed the same way, since the actual drives usually live one level below the automount root (for example `/run/media/media-automount/Games`) rather than being the root itself. A root with no subdirectories is mounted as-is.

With `--yes`, or when nothing was discovered, everything found at every level is mounted automatically without a prompt.

The paths are mounted at the same locations inside the Distrobox.

For Podman, the setup uses recursive bind mounts so already mounted filesystems below these directories are visible. When the host mount propagation permits it, `rslave` is added so later host-side mounts can also propagate into the container without propagating container-side mounts back to the host.

Check mount visibility with:

```bash
scummvm-nightly-doctor
```

A drive mounted only after the Distrobox was created may require the container to be rebuilt when the host's parent mount is private and does not support propagation.

## MIDI, MT-32, and Text-to-Speech

The container installs FluidSynth. When Debian's configured repositories provide `fluid-soundfont-gm`, the setup installs that soundfont as well.

In ScummVM, select FluidSynth or General MIDI in the MIDI settings. If necessary, point ScummVM to the installed `.sf2` file under `/usr/share/sounds/sf2/` inside the Distrobox.

MT-32 emulation requires legally obtained MT-32 or CM-32L ROM files. These ROMs are not downloaded or supplied by this script, but existing ones already configured in a Flatpak install are copied over automatically; see [Flatpak Extras Import](#flatpak-extras-import).

Speech Dispatcher and its eSpeak NG output module are installed. The launcher attempts to start Speech Dispatcher automatically. A failure affects only ScummVM's optional text-to-speech feature, not normal game speech or audio.

## Other Console Messages

These messages are normally non-fatal:

- `Using game controller: Generic X-Box pad` appearing twice
- a missing Speech Dispatcher warning when text-to-speech is unused
- `TODO: digi_change_panning`, which reflects an unfinished M4 audio-panning function

The setup creates an empty timestamps file in the save directory to avoid the initial cloud-timestamp warning.

## Troubleshooting

### The Setup Appears to Stop During Package Installation

Package installation and the roughly 100 MB nightly download are the longest steps. The script prints the current high-level operation. Do not run a second setup concurrently.

### A Mounted Game Directory Is Missing

Run:

```bash
scummvm-nightly-doctor
```

Then rebuild with the exact path:

```bash
./setup-scummvm-nightly-distrobox.sh --yes --mount "/exact/host/path"
```

### A Mounted Directory Is Visible but Cannot Be Modified

Mounts are read/write by default; this happens if the rebuild explicitly used `--ro`. Rebuild without it to restore write access:

```bash
./setup-scummvm-nightly-distrobox.sh --yes --mount "/exact/host/path"
```

### Automatic Update Fails but ScummVM Still Starts

This is expected fallback behavior. Run the updater in a terminal to see the complete error:

```bash
scummvm-nightly-update
```

### The New Nightly Is Missing a Shared Library

Run:

```bash
scummvm-nightly-doctor
```

The updater refuses to replace the previous installation when `ldd` reports an unresolved library.

### The Desktop Entry Does Not Appear Immediately

Log out and back in, restart the desktop shell, or run:

```bash
update-desktop-database "${XDG_DATA_HOME:-$HOME/.local/share}/applications"
```

### The Copied Game Paths Do Not Work

Flatpak document-portal paths are sandbox-specific. Edit the game in ScummVM and select the actual host directory mounted into the Distrobox.

## Rebuilding

The setup is designed to be rerun. Rebuilding removes the old container and nightly executable files but retains user data.

```bash
./setup-scummvm-nightly-distrobox.sh --yes
```

## Uninstalling

Remove the Distrobox and generated launchers:

```bash
DBX_CONTAINER_MANAGER=podman distrobox rm -f scummvm-nightly
rm -f ~/.local/bin/scummvm-nightly \
      ~/.local/bin/scummvm-nightly-update \
      ~/.local/bin/scummvm-nightly-doctor \
      ~/.local/share/applications/scummvm-nightly.desktop
```

Remove the installed nightly and cache:

```bash
rm -rf ~/.local/opt/scummvm-nightly \
       ~/.cache/scummvm-nightly
```

Configuration and save games are intentionally not included above. Remove them only when they are no longer needed:

```bash
rm -rf ~/.config/scummvm-nightly \
       ~/.local/share/scummvm-nightly
```

Adjust these commands when custom XDG paths or environment overrides were used.

## Upstream References

- [Distrobox create and additional volumes](https://distrobox.it/usage/distrobox-create/)
- [Distrobox enter and headless commands](https://distrobox.it/usage/distrobox-enter/)
- [Podman bind mounts and mount propagation](https://docs.podman.io/en/latest/markdown/podman-run.1.html)
- [ScummVM master nightly builds](https://buildbot.scummvm.org/dailybuilds/master/)
