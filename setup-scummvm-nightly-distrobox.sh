#!/usr/bin/env bash
set -Eeuo pipefail

box_name="scummvm-nightly"
image="docker.io/library/debian:13"
mount_mode="ro"
copy_flatpak_config=1
assume_yes=0
declare -a requested_mounts=()

usage() {
    cat <<'EOF'
Usage:
  setup-scummvm-nightly-distrobox.sh [options]

Options:
  --yes                    Do not ask for confirmation before deleting
  --rw                     Mount additional paths read/write
  --ro                     Mount additional paths read-only
  --mount PATH             Mount an additional host path
  --no-flatpak-config      Do not import the Flatpak configuration
  --box NAME               Use a different Distrobox name
  --image IMAGE            Use a different container image
  --help                   Show this help

Without --mount, existing directories from this list are mounted:
  /run/media/$USER
  /mnt
  /var/mnt

The existing nightly configuration is backed up.
Existing nightly save games are not deleted.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --yes)
            assume_yes=1
            shift
            ;;
        --rw)
            mount_mode="rw"
            shift
            ;;
        --ro)
            mount_mode="ro"
            shift
            ;;
        --mount)
            [ "$#" -ge 2 ] || {
                printf 'Missing path after --mount.\n' >&2
                exit 2
            }
            requested_mounts+=("$2")
            shift 2
            ;;
        --no-flatpak-config)
            copy_flatpak_config=0
            shift
            ;;
        --box)
            [ "$#" -ge 2 ] || {
                printf 'Missing name after --box.\n' >&2
                exit 2
            }
            box_name="$2"
            shift 2
            ;;
        --image)
            [ "$#" -ge 2 ] || {
                printf 'Missing image after --image.\n' >&2
                exit 2
            }
            image="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ -n "${CONTAINER_ID:-}" ]; then
    printf 'This script must be run on the host, not inside a Distrobox.\n' >&2
    exit 1
fi

for command_name in distrobox podman curl find readlink awk; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'Required command missing: %s\n' "$command_name" >&2
        exit 1
    fi
done

timestamp="$(date +%Y%m%d-%H%M%S)"
nightly_root="$HOME/.local/opt/scummvm-nightly"
nightly_cache="$HOME/.cache/scummvm-nightly"
nightly_config_dir="$HOME/.config/scummvm-nightly"
nightly_config="$nightly_config_dir/scummvm.ini"
nightly_data="$HOME/.local/share/scummvm-nightly"
nightly_saves="$nightly_data/saves"
nightly_engine_data="$nightly_data/engine-data"
host_bin="$HOME/.local/bin"
desktop_dir="$HOME/.local/share/applications"
desktop_file="$desktop_dir/scummvm-nightly.desktop"
stage="$HOME/.cache/scummvm-nightly-setup-$timestamp"
flatpak_root="$HOME/.var/app/org.scummvm.ScummVM"

# Guards in both directions: a nightly-managed path must not sit inside the Flatpak
# profile, and must not contain it either, since the Flatpak install must stay untouched.
protect_flatpak_profile() {
    local managed_path normalized_path

    for managed_path in \
        "$nightly_root" \
        "$nightly_cache" \
        "$nightly_config_dir" \
        "$nightly_config" \
        "$nightly_data" \
        "$nightly_saves" \
        "$nightly_engine_data" \
        "$host_bin" \
        "$desktop_dir" \
        "$desktop_file"; do

        normalized_path="${managed_path%/}"

        case "$normalized_path" in
            "$flatpak_root"|"$flatpak_root"/*)
                printf 'Refusing to use the Flatpak installation or profile as a nightly-managed path: %s\n' "$managed_path" >&2
                exit 1
                ;;
        esac

        case "$flatpak_root" in
            "$normalized_path"/*)
                printf 'Refusing a nightly-managed path that would contain the Flatpak profile: %s\n' "$managed_path" >&2
                exit 1
                ;;
        esac
    done
}

protect_flatpak_profile

declare -a mounts=()

if [ "${#requested_mounts[@]}" -gt 0 ]; then
    mounts=("${requested_mounts[@]}")
else
    for path in "/run/media/$USER" "/mnt" "/var/mnt"; do
        if [ -d "$path" ]; then
            mounts+=("$path")
        fi
    done
fi

declare -A seen_mounts=()
declare -a normalized_mounts=()

# "${arr[@]-}" avoids Bash's pre-4.4 nounset bug on an empty array (the script's minimum documented Bash version is 4).
for path in "${mounts[@]-}"; do
    if [ ! -d "$path" ]; then
        printf 'Mount path does not exist: %s\n' "$path" >&2
        exit 1
    fi

    real_path="$(readlink -f "$path")"

    if [ -z "${seen_mounts[$real_path]+x}" ]; then
        seen_mounts["$real_path"]=1
        normalized_mounts+=("$real_path")
    fi
done

mapfile -t existing_boxes < <(
    podman ps -a --format '{{.Names}}' |
    # Also matches timestamped backup containers named "$box_name-backup-*", in case
    # one was created outside this script; nothing here creates that name itself.
    awk -v name="$box_name" '
        $0 == name || index($0, name "-backup-") == 1 { print }
    '
)

printf '\nScummVM Nightly will be fully rebuilt.\n'
printf 'Distrobox:        %s\n' "$box_name"
printf 'Image:            %s\n' "$image"
printf 'Mount mode:       %s\n' "$mount_mode"
printf 'Configuration:    %s\n' "$nightly_config"
printf 'Save games:       %s\n' "$nightly_saves"
printf 'Nightly files:    %s\n' "$nightly_root"

if [ "${#normalized_mounts[@]}" -gt 0 ]; then
    printf 'Additional mounts:\n'
    printf '  %s\n' "${normalized_mounts[@]}"
else
    printf 'Additional mounts: none\n'
fi

if [ "${#existing_boxes[@]}" -gt 0 ]; then
    printf 'Containers to be removed:\n'
    printf '  %s\n' "${existing_boxes[@]}"
fi

printf '\nThe nightly save games are preserved.\n'

if [ "$assume_yes" -ne 1 ]; then
    printf 'Continue? [y/N] '
    read -r answer
    case "${answer,,}" in
        y|yes)
            ;;
        *)
            printf 'Aborted.\n'
            exit 0
            ;;
    esac
fi

cleanup_stage() {
    rm -rf "$stage"
}

trap cleanup_stage EXIT

mkdir -p \
    "$stage" \
    "$nightly_config_dir" \
    "$nightly_saves" \
    "$nightly_engine_data" \
    "$host_bin" \
    "$desktop_dir"

# Avoids ScummVM's initial cloud-save-timestamp warning on first run.
touch "$nightly_saves/timestamps"

if [ -f "$nightly_config" ]; then
    config_backup="${nightly_config}.backup-${timestamp}"
    cp -a "$nightly_config" "$config_backup"
    printf '\nConfiguration backed up: %s\n' "$config_backup"
fi

# "${arr[@]-}" avoids Bash's pre-4.4 nounset bug on an empty array (the script's minimum documented Bash version is 4).
for existing_box in "${existing_boxes[@]-}"; do
    printf '\nRemoving container %s ...\n' "$existing_box"
    podman stop --time 10 "$existing_box" >/dev/null 2>&1 || true
    podman rm -f "$existing_box" >/dev/null
done

rm -f \
    "$host_bin/scummvm-nightly" \
    "$host_bin/scummvm-nightly-update" \
    "$host_bin/scummvm-nightly-doctor" \
    "$desktop_file"

printf '\nRemoving old nightly program files ...\n'
rm -rf "$nightly_root" "$nightly_cache"

declare -a volume_args=()

# "${arr[@]-}" avoids Bash's pre-4.4 nounset bug on an empty array (the script's minimum documented Bash version is 4).
for path in "${normalized_mounts[@]-}"; do
    options="$mount_mode,rbind"

    if command -v findmnt >/dev/null 2>&1; then
        propagation="$(findmnt -no PROPAGATION -T "$path" 2>/dev/null || true)"
        case "$propagation" in
            # rslave lets later host-side mounts propagate into the container
            # without propagating container-side mounts back out to the host.
            *shared*|*slave*)
                options="$options,rslave"
                ;;
        esac
    fi

    volume_args+=(--volume "$path:$path:$options")
done

printf '\nCreating Distrobox %s ...\n' "$box_name"
# "${arr[@]-}" avoids Bash's pre-4.4 nounset bug on an empty array (the script's minimum documented Bash version is 4).
distrobox create \
    --yes \
    --image "$image" \
    --name "$box_name" \
    "${volume_args[@]-}"

run_in_box() {
    distrobox enter \
        --name "$box_name" \
        --no-tty \
        -- "$@"
}

printf '\nInitializing Distrobox ...\n'
run_in_box true

printf '\nInstalling Debian packages. This step may take a while ...\n'
run_in_box bash -lc '
set -Eeuo pipefail
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    findutils \
    fonts-liberation \
    fluidsynth \
    fluid-soundfont-gm \
    libmikmod3 \
    libunity9 \
    libvpx9 \
    scummvm \
    speech-dispatcher \
    speech-dispatcher-espeak-ng \
    xz-utils
'

cat >"$stage/scummvm-nightly-update" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

url="https://buildbot.scummvm.org/dailybuilds/master/debian-x86-64-master-latest.tar.xz"
target="$HOME/.local/opt/scummvm-nightly"
cache="$HOME/.cache/scummvm-nightly"
archive="$cache/latest.tar.xz"
download="$cache/latest.tar.xz.download"
new="${target}.new"
old="${target}.old"
persistent_data="$HOME/.local/share/scummvm-nightly/engine-data"

mkdir -p "$cache" "$persistent_data"

curl_args=(
    --fail
    --location
    --retry 3
    --retry-delay 2
    --remote-time
    --output "$download"
    --write-out "%{http_code}"
)

if [ -f "$archive" ]; then
    curl_args+=(--time-cond "$archive")
fi

printf 'Checking for a current ScummVM nightly build ...\n'
status="$(curl "${curl_args[@]}" "$url")"

case "$status" in
    200)
        mv "$download" "$archive"
        printf 'A new nightly build was downloaded.\n'
        ;;
    304)
        rm -f "$download"
        printf 'The existing download is already up to date.\n'
        ;;
    *)
        rm -f "$download"
        printf 'Download failed: HTTP %s\n' "$status" >&2
        exit 1
        ;;
esac

printf 'Checking archive ...\n'
tar -tJf "$archive" >/dev/null

rm -rf "$new"
mkdir -p "$new"

printf 'Extracting nightly build ...\n'
tar -xJf "$archive" -C "$new"

binary="$(find "$new" -type f -name scummvm -perm /111 -print -quit)"

if [ -z "$binary" ]; then
    printf 'No executable ScummVM file was found in the archive.\n' >&2
    rm -rf "$new"
    exit 1
fi

bindir="$(dirname "$binary")"
data="$bindir/data"

if [ ! -d "$data" ]; then
    printf 'Data directory not found: %s\n' "$data" >&2
    rm -rf "$new"
    exit 1
fi

if find "$persistent_data" -mindepth 1 -print -quit | grep -q .; then
    cp -a "$persistent_data"/. "$data"/
fi

missing="$(ldd "$binary" 2>/dev/null | awk '/not found/{print $1}')"

if [ -n "$missing" ]; then
    printf 'The nightly build is missing libraries:\n%s\n' "$missing" >&2
    printf 'The previous nightly build remains unchanged.\n' >&2
    rm -rf "$new"
    exit 1
fi

relative="${binary#"$new"/}"
printf '%s\n' "$relative" >"$new/.binary-path"

cd "$bindir"
"$binary" --version

# Staging into .new and keeping .old until the swap succeeds means a failed or
# interrupted update leaves the previous working build in place.
rm -rf "$old"

if [ -d "$target" ]; then
    mv "$target" "$old"
fi

if mv "$new" "$target"; then
    rm -rf "$old"
else
    rm -rf "$new"
    if [ -d "$old" ]; then
        mv "$old" "$target"
    fi
    exit 1
fi

printf 'ScummVM Nightly was updated successfully.\n'
EOF

cat >"$stage/scummvm-nightly" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

root="$HOME/.local/opt/scummvm-nightly"
config="$HOME/.config/scummvm-nightly/scummvm.ini"
saves="$HOME/.local/share/scummvm-nightly/saves"
pathfile="$root/.binary-path"

if [ ! -f "$pathfile" ]; then
    printf 'ScummVM Nightly is not installed. Run scummvm-nightly-update.\n' >&2
    exit 1
fi

binary="$root/$(cat "$pathfile")"

if [ ! -x "$binary" ]; then
    printf 'ScummVM file not found: %s\n' "$binary" >&2
    printf 'Run scummvm-nightly-update again.\n' >&2
    exit 1
fi

bindir="$(dirname "$binary")"
data="$bindir/data"

if [ ! -d "$data" ]; then
    printf 'ScummVM data directory not found: %s\n' "$data" >&2
    exit 1
fi

mkdir -p "$(dirname "$config")" "$saves"
# Avoids ScummVM's initial cloud-save-timestamp warning on first run.
touch "$saves/timestamps"

if command -v speech-dispatcher >/dev/null 2>&1; then
    speech-dispatcher --spawn >/dev/null 2>&1 || true
fi

cd "$bindir"

exec "$binary" \
    --config="$config" \
    --savepath="$saves" \
    --extrapath="$data" \
    --themepath="$data" \
    "$@"
EOF

cat >"$stage/scummvm-nightly-doctor" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

root="$HOME/.local/opt/scummvm-nightly"
pathfile="$root/.binary-path"
config="$HOME/.config/scummvm-nightly/scummvm.ini"
saves="$HOME/.local/share/scummvm-nightly/saves"
engine_data="$HOME/.local/share/scummvm-nightly/engine-data"

printf 'Configuration: %s\n' "$config"
printf 'Save games:    %s\n' "$saves"
printf 'Engine data:   %s\n' "$engine_data"

if [ ! -f "$pathfile" ]; then
    printf 'Nightly build: not installed\n'
    exit 1
fi

binary="$root/$(cat "$pathfile")"
bindir="$(dirname "$binary")"
data="$bindir/data"

printf 'Binary:        %s\n' "$binary"
printf 'Data:          %s\n' "$data"

printf '\nVersion:\n'
cd "$bindir"
"$binary" --version

printf '\nMissing libraries:\n'
missing="$(ldd "$binary" 2>/dev/null | awk '/not found/{print $1}')"

if [ -n "$missing" ]; then
    printf '%s\n' "$missing"
else
    printf 'none\n'
fi

printf '\nImportant data files:\n'
for file in translations.dat gui-icons.dat shaders.dat scummremastered.zip riddle_translations.dat; do
    if [ -f "$data/$file" ]; then
        printf 'present    %s\n' "$file"
    else
        printf 'missing    %s\n' "$file"
    fi
done

printf '\nVisible mount directories:\n'
for path in "/run/media/$USER" /mnt /var/mnt; do
    if [ -d "$path" ]; then
        printf '%s\n' "$path"
        find "$path" -mindepth 1 -maxdepth 2 -type d 2>/dev/null | head -n 20
    fi
done
EOF

chmod +x \
    "$stage/scummvm-nightly" \
    "$stage/scummvm-nightly-update" \
    "$stage/scummvm-nightly-doctor"

printf '\nInstalling nightly helper programs in the Distrobox ...\n'
run_in_box sudo install -m 0755 \
    "$stage/scummvm-nightly" \
    /usr/local/bin/scummvm-nightly

run_in_box sudo install -m 0755 \
    "$stage/scummvm-nightly-update" \
    /usr/local/bin/scummvm-nightly-update

run_in_box sudo install -m 0755 \
    "$stage/scummvm-nightly-doctor" \
    /usr/local/bin/scummvm-nightly-doctor

printf '\nDownloading and installing the current ScummVM nightly build ...\n'
run_in_box /usr/local/bin/scummvm-nightly-update

if [ "$copy_flatpak_config" -eq 1 ]; then
    flatpak_config=""

    if [ -f "$flatpak_root/config/scummvm/scummvm.ini" ]; then
        flatpak_config="$flatpak_root/config/scummvm/scummvm.ini"
    elif [ -d "$flatpak_root" ]; then
        flatpak_config="$(
            find "$flatpak_root" \
                -type f \
                -name scummvm.ini \
                -print -quit
        )"
    fi

    if [ -n "$flatpak_config" ] && [ -f "$flatpak_config" ]; then
        cp -a "$flatpak_config" "$nightly_config"
        printf '\nFlatpak configuration copied to the separate nightly profile: %s\n' "$flatpak_config"
    elif [ -f "$nightly_config" ]; then
        printf '\nNo Flatpak configuration found. The existing nightly configuration is preserved.\n'
    else
        printf '\nNo Flatpak configuration found. ScummVM will create a new configuration on first nightly start.\n'
    fi
elif [ -f "$nightly_config" ]; then
    printf '\nFlatpak import is disabled. The existing nightly configuration is preserved.\n'
else
    printf '\nFlatpak import is disabled. ScummVM will create a new configuration on first nightly start.\n'
fi

printf '\nExporting commands to the host ...\n'
run_in_box distrobox-export \
    --bin /usr/local/bin/scummvm-nightly \
    --export-path "$host_bin"

run_in_box distrobox-export \
    --bin /usr/local/bin/scummvm-nightly-update \
    --export-path "$host_bin"

run_in_box distrobox-export \
    --bin /usr/local/bin/scummvm-nightly-doctor \
    --export-path "$host_bin"

cat >"$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=ScummVM Nightly
Comment=Current ScummVM master build in Distrobox
Exec=$host_bin/scummvm-nightly
TryExec=$host_bin/scummvm-nightly
Icon=org.scummvm.ScummVM
Terminal=false
Categories=Game;Emulator;
StartupNotify=true
EOF

chmod 0644 "$desktop_file"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$desktop_dir" >/dev/null 2>&1 || true
fi

printf '\nRunning final check ...\n'
"$host_bin/scummvm-nightly-doctor"

printf '\nSetup complete.\n'
printf 'Start:       scummvm-nightly\n'
printf 'Update:      scummvm-nightly-update\n'
printf 'Diagnostics: scummvm-nightly-doctor\n'
printf 'Desktop:     ScummVM Nightly\n'
printf 'Save games:  %s\n' "$nightly_saves"
printf 'Extra data:  %s\n' "$nightly_engine_data"
printf '\nThe riddle_translations.dat file is not currently distributed officially.\n'
printf 'If it becomes available later, place it here and run the update again:\n'
printf '  %s/riddle_translations.dat\n' "$nightly_engine_data"
