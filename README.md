ScummVM Nightly in Distrobox

This repository-sized setup consists of one Bash script that creates a clean Debian 13 Distrobox for the current ScummVM master nightly build.

It is intended for immutable or container-oriented Linux desktops such as Bazzite, Fedora Atomic, Kinoite and Silverblue, but it works for normal Linux user profiles as long as Distrobox and rootless Podman are available.

What the setup does

The script:

removes and recreates the scummvm-nightly Distrobox

uses the official Debian 13 container image by default

downloads the official ScummVM master nightly archive

installs the libraries required by the Debian nightly build

installs FluidSynth and, when available, a General MIDI soundfont

installs Speech Dispatcher with the eSpeak NG output module

imports the official Flatpak ScummVM configuration only when that configuration exists

preserves an existing nightly configuration when no Flatpak configuration exists

preserves save games and persistent engine data

creates read-only host mounts for common external-storage locations

creates host commands for launching, updating and diagnosing the installation

creates a desktop entry named ScummVM Nightly

checks for an update every time ScummVM Nightly starts

falls back to the last working build when an automatic update fails

Requirements

Run the setup on the Linux host as a normal desktop user.

Required host tools:

Bash 4 or newer

Distrobox

rootless Podman

curl

standard GNU utilities such as find, awk, grep, tar and readlink

The script deliberately refuses to run:

as root

from inside a container

when Podman is unavailable for the current user

The default nightly URLs support:

x86_64 / amd64

i386 through i686

For another architecture, provide a compatible official .tar.xz archive with --nightly-url.

Quick start

Make the script executable and run it:

chmod +x setup-scummvm-nightly-distrobox.sh
./setup-scummvm-nightly-distrobox.sh

Run without the confirmation prompt:

./setup-scummvm-nightly-distrobox.sh --yes

The first run downloads a container image, installs Debian packages and downloads a ScummVM nightly archive of roughly 100 MB.

Command-line options

Option

Description

--yes

Rebuild without an interactive confirmation.

--ro

Mount additional host paths read-only. This is the default.

--rw

Mount additional host paths read/write.

--mount PATH

Add a host path. The option may be specified repeatedly.

--no-flatpak-config

Do not import the Flatpak ScummVM configuration.

--box NAME

Use a different Distrobox name.

--image IMAGE

Use another Debian-compatible container image.

--nightly-url URL

Override the official nightly archive URL. The archive must use the expected .tar.xz layout.

--help

Show the built-in help.

Example with selected game directories:

./setup-scummvm-nightly-distrobox.sh --yes \
  --mount "/run/media/$USER/Games" \
  --mount "/mnt/DOS-Games"

Example with write access to the mounted paths:

./setup-scummvm-nightly-distrobox.sh --yes --rw \
  --mount "/run/media/$USER/Games"

Read-only access is recommended for game installations. ScummVM save games are stored separately in the user profile and remain writable.

Host commands

After setup, these commands are created in ~/.local/bin by default:

scummvm-nightly
scummvm-nightly-update
scummvm-nightly-doctor

Start ScummVM

scummvm-nightly

The launcher checks for a newer nightly build before starting ScummVM.

Start once without checking for an update

SCUMMVM_NIGHTLY_SKIP_UPDATE=1 scummvm-nightly

Run the updater manually

scummvm-nightly-update

Run diagnostics

scummvm-nightly-doctor

The doctor reports:

the installed ScummVM version

the binary and data paths

unresolved shared-library dependencies

important data files

configuration status

save-directory writability

visibility of the configured host mounts

the status of the optional riddle_translations.dat file

If ~/.local/bin is not in PATH, use the full path or add it to your shell configuration.

Automatic update behavior

The updater uses the official *-master-latest.tar.xz archive and an HTTP conditional request.

When a new build is available, it:

downloads to a temporary file

validates the archive before accepting it

extracts into a separate staging directory

locates and tests the ScummVM executable

checks all dynamically linked libraries with ldd

copies persistent engine data into the new build

replaces the installed build atomically

If validation fails, the installed build remains unchanged.

If the update check fails during normal launch, for example because the machine is offline, the launcher starts the last working build. The first installation still requires a successful download because no fallback build exists yet.

A file lock prevents two simultaneous updater processes from modifying the installation at the same time.

Flatpak installation safety

The existing Flatpak installation is left completely untouched.

The setup script:

never runs flatpak uninstall, flatpak remove or another Flatpak management command

never deletes or changes files below ~/.var/app/org.scummvm.ScummVM

reads the Flatpak scummvm.ini only when it exists

copies that file into the separate nightly profile; it never moves or edits the original

refuses custom managed paths that point into the Flatpak profile or would contain it

The installed Flatpak application, its configuration, save games and application data therefore remain available exactly as before.

Flatpak configuration import

The script looks for the official Flatpak application ID:

org.scummvm.ScummVM

The usual source file is:

~/.var/app/org.scummvm.ScummVM/config/scummvm/scummvm.ini

The behavior is intentionally conservative:

Flatpak configuration exists: it is copied to the nightly profile.

Flatpak configuration does not exist: an existing nightly configuration is retained.

Neither configuration exists: ScummVM creates a new one on first launch.

--no-flatpak-config is used: the Flatpak file is ignored, but an existing nightly configuration is still retained.

Before any possible import, an existing nightly configuration is backed up with a timestamp.

A copied Flatpak configuration may contain document-portal paths under /run/user/.../doc/.... These paths may not work outside the Flatpak sandbox. Re-add the affected game directory in ScummVM using its normal host path.

Profile and XDG support

No username is hard-coded.

The setup derives paths from:

$HOME

$XDG_CONFIG_HOME

$XDG_DATA_HOME

$XDG_CACHE_HOME

Relative or invalid XDG values fall back to their standard locations.

The resolved paths are stored in a private runtime file:

$XDG_CONFIG_HOME/scummvm-nightly/runtime.env

This lets the launcher, updater and doctor use the same profile paths even when started from a desktop menu with a smaller environment.

Optional environment overrides:

Variable

Purpose

SCUMMVM_NIGHTLY_BIN_DIR

Directory for the host commands.

SCUMMVM_NIGHTLY_ROOT

Installed nightly program files.

SCUMMVM_NIGHTLY_CACHE

Download and update cache.

SCUMMVM_NIGHTLY_CONFIG_DIR

Nightly configuration directory.

SCUMMVM_NIGHTLY_CONFIG

Exact scummvm.ini path.

SCUMMVM_NIGHTLY_DATA

Persistent data root.

SCUMMVM_NIGHTLY_SAVES

Save-game directory.

SCUMMVM_NIGHTLY_ENGINE_DATA

Persistent additional engine files.

For safety, managed setup paths must remain inside the current user's home directory.

Default paths

With standard XDG settings, the setup uses:

Purpose

Path

Nightly program files

~/.local/opt/scummvm-nightly

Configuration

~/.config/scummvm-nightly/scummvm.ini

Runtime settings

~/.config/scummvm-nightly/runtime.env

Save games

~/.local/share/scummvm-nightly/saves

Persistent engine data

~/.local/share/scummvm-nightly/engine-data

Download cache

~/.cache/scummvm-nightly

Host commands

~/.local/bin

Desktop entry

~/.local/share/applications/scummvm-nightly.desktop

The setup removes only the Distrobox, the nightly program directory and its download cache. It does not remove the configuration, saves or persistent engine-data directory.

Additional host mounts

Without explicit --mount options, the script adds every existing path from this list:

/run/media/<current-user>
/media/<current-user>
/mnt
/var/mnt

The paths are mounted at the same locations inside the Distrobox.

For Podman, the setup uses recursive bind mounts so already mounted filesystems below these directories are visible. When the host mount propagation permits it, rslave is added so later host-side mounts can also propagate into the container without propagating container-side mounts back to the host.

Check mount visibility with:

scummvm-nightly-doctor

A drive mounted only after the Distrobox was created may require the container to be rebuilt when the host's parent mount is private and does not support propagation.

MIDI, MT-32 and text-to-speech

The container installs FluidSynth. When Debian's configured repositories provide fluid-soundfont-gm, the setup installs that soundfont as well.

In ScummVM, select FluidSynth or General MIDI in the MIDI settings. If necessary, point ScummVM to the installed .sf2 file under /usr/share/sounds/sf2/ inside the Distrobox.

MT-32 emulation requires legally obtained MT-32 or CM-32L ROM files. These ROMs are not downloaded or supplied by this script.

Speech Dispatcher and its eSpeak NG output module are installed. The launcher attempts to start Speech Dispatcher automatically. A failure affects only ScummVM's optional text-to-speech feature, not normal game speech or audio.

The Riddle of Master Lu notes

The script supports the current ScummVM M4 implementation but does not modify the game itself.

riddle_translations.dat

This file is optional and is not generated by the setup. Without it, the game remains playable, but ScummVM's additional M4 subtitles are unavailable.

If an official copy becomes available, place it in:

~/.local/share/scummvm-nightly/engine-data/riddle_translations.dat

The updater copies files from this persistent directory into every new nightly build. It also copies them into the current build when the nightly archive has not changed.

Other console messages

These messages are normally non-fatal:

Using game controller: Generic X-Box pad appearing twice

a missing Speech Dispatcher warning when text-to-speech is unused

TODO: digi_change_panning, which reflects an unfinished M4 audio-panning function

The setup creates an empty timestamps file in the save directory to avoid the initial cloud-timestamp warning.

Troubleshooting

The setup appears to stop during package installation

Package installation and the roughly 100 MB nightly download are the longest steps. The script prints the current high-level operation. Do not run a second setup concurrently.

A mounted game directory is missing

Run:

scummvm-nightly-doctor

Then rebuild with the exact path:

./setup-scummvm-nightly-distrobox.sh --yes --mount "/exact/host/path"

A mounted directory is visible but cannot be modified

The default mode is read-only. Rebuild with --rw only when write access is required:

./setup-scummvm-nightly-distrobox.sh --yes --rw --mount "/exact/host/path"

Automatic update fails but ScummVM still starts

This is expected fallback behavior. Run the updater in a terminal to see the complete error:

scummvm-nightly-update

The new nightly is missing a shared library

Run:

scummvm-nightly-doctor

The updater refuses to replace the previous installation when ldd reports an unresolved library.

The desktop entry does not appear immediately

Log out and back in, restart the desktop shell, or run:

update-desktop-database "${XDG_DATA_HOME:-$HOME/.local/share}/applications"

The copied game paths do not work

Flatpak document-portal paths are sandbox-specific. Edit the game in ScummVM and select the actual host directory mounted into the Distrobox.

Rebuilding

The setup is designed to be rerun. Rebuilding removes the old container and nightly executable files but retains user data.

./setup-scummvm-nightly-distrobox.sh --yes

Uninstalling

Remove the Distrobox and generated launchers:

DBX_CONTAINER_MANAGER=podman distrobox rm -f scummvm-nightly
rm -f ~/.local/bin/scummvm-nightly \
      ~/.local/bin/scummvm-nightly-update \
      ~/.local/bin/scummvm-nightly-doctor \
      ~/.local/share/applications/scummvm-nightly.desktop

Remove the installed nightly and cache:

rm -rf ~/.local/opt/scummvm-nightly \
       ~/.cache/scummvm-nightly

Configuration and save games are intentionally not included above. Remove them only when they are no longer needed:

rm -rf ~/.config/scummvm-nightly \
       ~/.local/share/scummvm-nightly

Adjust these commands when custom XDG paths or environment overrides were used.

Upstream references

Distrobox create and additional volumes: https://distrobox.it/usage/distrobox-create/

Distrobox enter and headless commands: https://distrobox.it/usage/distrobox-enter/

Podman bind mounts and mount propagation: https://docs.podman.io/en/latest/markdown/podman-run.1.html

ScummVM master nightly builds: https://buildbot.scummvm.org/dailybuilds/master/
