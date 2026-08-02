#!/usr/bin/env bash
set -Eeuo pipefail

# This script has two stages: the code below runs on the host to prepare and
# launch the container, and the heredoc further down is written out as a
# separate script that runs inside the Arch Linux Distrobox container.

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing host command: $1"
}

on_off() {
  if [ "$1" = "1" ]; then printf on; else printf off; fi
}

[ "$(id -u)" -ne 0 ] || fail "Do not run this installer as root. Distrobox must be run as a regular user."
[ -n "${HOME:-}" ] || fail "HOME is not set. Run this installer as a regular user with a valid home directory."

require_command distrobox
command -v podman >/dev/null 2>&1 || command -v docker >/dev/null 2>&1 || fail "Missing host command: a supported container manager (podman or docker)"

BOX_NAME="${BOX_NAME:-retroarch}"
IMAGE="${IMAGE:-docker.io/library/archlinux:latest}"
RETROARCH_ROOT="${RETROARCH_ROOT:-$HOME/Games/RetroArch}"
INSTALL_EXTRA_DATA="${INSTALL_EXTRA_DATA:-1}"
INSTALL_SYSTEM_FILES="${INSTALL_SYSTEM_FILES:-1}"
INSTALL_AUR_CORES="${INSTALL_AUR_CORES:-1}"
INSTALL_PARU_DEBUG="${INSTALL_PARU_DEBUG:-1}"
CHEZMOI_INTEGRATION="${CHEZMOI_INTEGRATION:-1}"
EXTRA_VOLUMES="${EXTRA_VOLUMES:-}"
EXTRA_VOLUMES_MODE="${EXTRA_VOLUMES_MODE:-ro}"
case "$EXTRA_VOLUMES_MODE" in
  ro|rw) ;;
  *) fail "EXTRA_VOLUMES_MODE must be 'ro' or 'rw', got: $EXTRA_VOLUMES_MODE" ;;
esac
extra_volume_paths=()
if [ -n "$EXTRA_VOLUMES" ]; then
  IFS=':' read -ra extra_volume_paths <<< "$EXTRA_VOLUMES"
  for extra_volume_path in "${extra_volume_paths[@]}"; do
    [ -d "$extra_volume_path" ] || fail "EXTRA_VOLUMES path does not exist: $extra_volume_path"
  done
fi
ASSUME_YES="${ASSUME_YES:-0}"
SETUP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/retroarch-distrobox"
INNER_SCRIPT="${SETUP_DIR}/setup-retroarch-inside-arch.sh"
INVENTORY_FILE="${SETUP_DIR}/inventory.txt"

case "$(uname -m)" in
  x86_64)
    BUILD_URL="${BUILD_URL:-https://buildbot.libretro.com/nightly/linux/x86_64/latest}"
    ;;
  *)
    fail "This installer supports Arch Linux containers on x86_64 hosts only."
    ;;
esac

ASSET_URL="${ASSET_URL:-https://buildbot.libretro.com/assets/frontend}"
SYSTEM_ASSET_URL="${SYSTEM_ASSET_URL:-https://buildbot.libretro.com/assets/system}"
BUILDBOT_ASSETS_URL="${BUILDBOT_ASSETS_URL:-https://buildbot.libretro.com/assets}"
CORE_INFO_URL="${CORE_INFO_URL:-https://raw.githubusercontent.com/libretro/libretro-core-info/master}"
HOST_NVIDIA=0

if command -v nvidia-smi >/dev/null 2>&1; then
  HOST_NVIDIA=1
fi

existing_container=0
if command -v podman >/dev/null 2>&1 && podman container exists "$BOX_NAME" 2>/dev/null; then
  existing_container=1
elif command -v docker >/dev/null 2>&1 && docker container inspect "$BOX_NAME" >/dev/null 2>&1; then
  existing_container=1
fi

printf '\n%s\n' "RetroArch will be fully rebuilt."
printf 'Distrobox:           %s\n' "$BOX_NAME"
printf 'Image:               %s\n' "$IMAGE"
printf 'Configuration:       %s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/retroarch/retroarch.cfg"
printf 'Saves:               %s\n' "$RETROARCH_ROOT/saves"
printf 'RetroArch data:      %s\n' "$RETROARCH_ROOT"
printf 'NVIDIA integration:  %s\n' "$(on_off "$HOST_NVIDIA")"
printf 'Extra data:          %s\n' "$(on_off "$INSTALL_EXTRA_DATA")"
printf 'System files:        %s\n' "$(on_off "$INSTALL_SYSTEM_FILES")"
printf 'AUR cores:           %s\n' "$(on_off "$INSTALL_AUR_CORES")"
printf 'Paru debug package:  %s\n' "$(on_off "$INSTALL_PARU_DEBUG")"
printf 'Chezmoi integration: %s\n' "$(on_off "$CHEZMOI_INTEGRATION")"

if [ "${#extra_volume_paths[@]}" -gt 0 ]; then
  printf 'Additional mounts (%s):\n' "$EXTRA_VOLUMES_MODE"
  printf '  %s\n' "${extra_volume_paths[@]}"
else
  printf 'Additional mounts:   none (Distrobox provides its own default host access)\n'
fi

if [ "$existing_container" -eq 1 ]; then
  printf 'Containers to be removed:\n'
  printf '  %s\n' "$BOX_NAME"
fi

printf '\n%s\n' "RetroArch configuration, saves, and installed cores under \$HOME are preserved."

if [ "$ASSUME_YES" -ne 1 ]; then
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

printf '\n%s\n' "Preparing the installation script..."
mkdir -p "$SETUP_DIR"

# The quotes around the ARCHSETUP delimiter prevent any expansion while this
# heredoc is written out; variables are instead passed in explicitly via
# `distrobox enter ... env ...` when the inner script is actually run below.
cat > "$INNER_SCRIPT" <<'ARCHSETUP'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

fail() {
  printf '%b\n' "$1" >&2
  exit 1
}

trap 'printf "Error on line %s.\n" "$LINENO" >&2' ERR

. /etc/os-release
[ "${ID:-}" = "arch" ] || fail "The container is not an Arch Linux Distrobox."
[ "$(uname -m)" = "x86_64" ] || fail "The container is not running on x86_64."

printf '\n%s\n' "Starting the RetroArch installation inside the Arch Linux container..."

BUILD_URL="${BUILD_URL:?BUILD_URL is missing}"
ASSET_URL="${ASSET_URL:?ASSET_URL is missing}"
SYSTEM_ASSET_URL="${SYSTEM_ASSET_URL:?SYSTEM_ASSET_URL is missing}"
BUILDBOT_ASSETS_URL="${BUILDBOT_ASSETS_URL:?BUILDBOT_ASSETS_URL is missing}"
CORE_INFO_URL="${CORE_INFO_URL:?CORE_INFO_URL is missing}"
INSTALL_EXTRA_DATA="${INSTALL_EXTRA_DATA:-1}"
INSTALL_SYSTEM_FILES="${INSTALL_SYSTEM_FILES:-1}"
INSTALL_AUR_CORES="${INSTALL_AUR_CORES:-1}"
INSTALL_PARU_DEBUG="${INSTALL_PARU_DEBUG:-1}"
HOST_NVIDIA="${HOST_NVIDIA:-0}"
INVENTORY_FILE="${INVENTORY_FILE:-${XDG_DATA_HOME:-$HOME/.local/share}/retroarch-distrobox/inventory.txt}"
RA_ROOT="${RETROARCH_ROOT:-$HOME/Games/RetroArch}"
RA_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/retroarch"
CORE_DIR="$RA_CONFIG/cores"
INFO_DIR="$RA_CONFIG/info"
AUTOCONFIG_DIR="$RA_CONFIG/autoconfig"
DATABASE_DIR="$RA_CONFIG/database/rdb"
CHEAT_DIR="$RA_CONFIG/cheats"
CONFIG_DIR="$RA_CONFIG/config"
REMAP_DIR="$RA_CONFIG/remaps"
CACHE_DIR="$RA_CONFIG/cache"
SYSTEM_DIR="$RA_ROOT/system"
SAVE_DIR="$RA_ROOT/saves"
STATE_DIR="$RA_ROOT/states"
SCREENSHOT_DIR="$RA_ROOT/screenshots"
PLAYLIST_DIR="$RA_ROOT/playlists"
THUMBNAIL_DIR="$RA_ROOT/thumbnails"
CORE_ASSETS_DIR="$RA_ROOT/downloads"
RECORDING_DIR="$RA_ROOT/recordings"
CFG="$RA_CONFIG/retroarch.cfg"

sudo_cmd=()
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || fail "sudo is missing inside the container."
  sudo_cmd=(sudo)
fi

if [ ! -s /etc/pacman.d/gnupg/pubring.gpg ]; then
  printf '\n%s\n' "Initializing the pacman keyring..."
  "${sudo_cmd[@]}" pacman-key --init
  "${sudo_cmd[@]}" pacman-key --populate archlinux
fi

printf '\n%s\n' "Refreshing package databases and updating the Arch keyring..."
"${sudo_cmd[@]}" pacman -Sy --needed --noconfirm archlinux-keyring

official_packages=(
  7zip
  alsa-lib
  alsa-plugins
  base
  base-devel
  bash-completion
  bc
  ca-certificates
  curl
  desktop-file-utils
  diffutils
  ffmpeg
  fontconfig
  freetype2
  gamemode
  git
  glibc-locales
  hicolor-icon-theme
  inetutils
  less
  libdecor
  libglvnd
  libpipewire
  libpulse
  libretro-beetle-pce
  libretro-beetle-pce-fast
  libretro-beetle-psx
  libretro-beetle-psx-hw
  libretro-beetle-supergrafx
  libretro-blastem
  libretro-bsnes
  libretro-core-info
  libretro-desmume
  libretro-dolphin
  libretro-flycast
  libretro-gambatte
  libretro-genesis-plus-gx
  libretro-kronos
  libretro-mame
  libretro-melonds
  libretro-mesen
  libretro-mesen-s
  libretro-mgba
  libretro-mupen64plus-next
  libretro-nestopia
  libretro-overlays
  libretro-parallel-n64
  libretro-picodrive
  libretro-play
  libretro-ppsspp
  libretro-sameboy
  libretro-scummvm
  libretro-shaders-slang
  libretro-snes9x
  libx11
  libxcb
  libxext
  libxinerama
  libxkbcommon
  libxrandr
  lsof
  man-db
  man-pages
  mesa
  mtr
  noto-fonts
  nss-mdns
  openssh
  pigz
  pipewire-alsa
  qt6-base
  retroarch
  retroarch-assets-glui
  retroarch-assets-ozone
  retroarch-assets-xmb
  rsync
  sdl2-compat
  sudo
  tcpdump
  time
  traceroute
  tree
  unzip
  vte-common
  vulkan-icd-loader
  vulkan-intel
  vulkan-radeon
  vulkan-tools
  wayland
  wget
  words
  xdg-utils
  xorg-xauth
  xorg-xwayland
  zip
)

nvidia_gpu=0
for vendor_file in /sys/class/drm/card*/device/vendor; do
  [ -r "$vendor_file" ] || continue
  read -r vendor_id < "$vendor_file"
  if [ "$vendor_id" = "0x10de" ]; then
    nvidia_gpu=1
  fi
done

if [ "$nvidia_gpu" -eq 1 ] && [ "$HOST_NVIDIA" -ne 1 ]; then
  official_packages+=(vulkan-nouveau)
fi

printf '\n%s\n' "Checking package availability..."
declare -A available_repo_packages=()
while IFS=' ' read -r _ pkg_name _; do
  available_repo_packages["$pkg_name"]=1
done < <(pacman -Sl)

missing_repo_packages=()
for package in "${official_packages[@]}"; do
  [ -n "${available_repo_packages[$package]:-}" ] || missing_repo_packages+=("$package")
done

if [ "${#missing_repo_packages[@]}" -ne 0 ]; then
  fail "These packages are missing from the enabled Arch repositories:\n$(printf '  %s\n' "${missing_repo_packages[@]}")"
fi

printf '\n%s\n' "Installing RetroArch, cores, and dependencies. This step downloads many packages and may take a while..."
"${sudo_cmd[@]}" pacman -Syu --needed --noconfirm "${official_packages[@]}"

build_paru() {
  # makepkg itself refuses to run as root, so check here first for a clearer error.
  [ "$(id -u)" -ne 0 ] || fail "AUR packages must not be built as root."
  printf '\n%s\n' "Building paru from the AUR..."
  local work_dir
  local repo_dir
  local makepkg_conf
  local -a package_files
  work_dir="$(mktemp -d)"
  # Safety net for the failure path; the explicit rm -rf below handles cleanup on success.
  trap 'rm -rf "$work_dir"' EXIT
  repo_dir="$work_dir/paru"
  makepkg_conf="$work_dir/makepkg.conf"
  git clone --depth 1 https://aur.archlinux.org/paru.git "$repo_dir"
  cp /etc/makepkg.conf "$makepkg_conf"
  if [ "$INSTALL_PARU_DEBUG" = "1" ]; then
    cat >> "$makepkg_conf" <<'MAKEPKGDEBUG'
case " ${OPTIONS[*]} " in
  *" strip "*) ;;
  *) OPTIONS+=(strip) ;;
esac
case " ${OPTIONS[*]} " in
  *" debug "*) ;;
  *) OPTIONS+=(debug) ;;
esac
MAKEPKGDEBUG
  fi
  (
    cd "$repo_dir"
    makepkg --config "$makepkg_conf" --syncdeps --cleanbuild --clean --noconfirm
  )
  mapfile -t package_files < <(
    cd "$repo_dir"
    makepkg --config "$makepkg_conf" --packagelist
  )
  [ "${#package_files[@]}" -ne 0 ] || fail "Paru was not built."
  for index in "${!package_files[@]}"; do
    if [[ "${package_files[$index]}" != /* ]]; then
      package_files[$index]="$repo_dir/${package_files[$index]}"
    fi
  done
  "${sudo_cmd[@]}" pacman -U --noconfirm "${package_files[@]}"
  rm -rf "$work_dir"
}

if ! command -v paru >/dev/null 2>&1; then
  build_paru
elif [ "$INSTALL_PARU_DEBUG" = "1" ] && ! pacman -Q paru-debug >/dev/null 2>&1; then
  build_paru
fi

if [ "$INSTALL_PARU_DEBUG" = "1" ] && ! pacman -Q paru-debug >/dev/null 2>&1; then
  fail "paru-debug could not be installed."
fi

if [ "$INSTALL_AUR_CORES" = "1" ]; then
  aur_packages=(
    libretro-fbneo-git
    libretro-lrps2-git
  )
  printf '\n%s\n' "Installing AUR cores (FinalBurn Neo, LRPS2)..."
  PARU_PAGER=cat paru --sync --needed --noconfirm --skipreview "${aur_packages[@]}"
fi

printf '\n%s\n' "Setting up RetroArch directories..."
mkdir -p \
  "$CORE_DIR" \
  "$INFO_DIR" \
  "$AUTOCONFIG_DIR" \
  "$DATABASE_DIR" \
  "$CHEAT_DIR" \
  "$CONFIG_DIR" \
  "$REMAP_DIR" \
  "$CACHE_DIR" \
  "$SYSTEM_DIR" \
  "$SYSTEM_DIR/pcsx2/bios" \
  "$SYSTEM_DIR/pcsx2/memcards" \
  "$SAVE_DIR" \
  "$STATE_DIR" \
  "$SCREENSHOT_DIR" \
  "$PLAYLIST_DIR" \
  "$THUMBNAIL_DIR" \
  "$CORE_ASSETS_DIR" \
  "$RECORDING_DIR" \
  "$(dirname "$INVENTORY_FILE")"

for required_dir in \
  /usr/share/retroarch/assets \
  /usr/share/libretro/info \
  /usr/share/libretro/overlays \
  /usr/share/libretro/shaders \
  /usr/lib/retroarch/filters/audio \
  /usr/lib/retroarch/filters/video \
  /usr/lib/libretro; do
  [ -d "$required_dir" ] || fail "Expected RetroArch path is missing: $required_dir"
done

printf '\n%s\n' "Linking packaged cores and core info files..."
find /usr/share/libretro/info -maxdepth 1 -type f -name '*.info' -exec cp -f -t "$INFO_DIR" {} +

while IFS= read -r -d '' link; do
  [ -e "$link" ] || rm -f "$link"
done < <(find "$CORE_DIR" -maxdepth 1 -type l -print0)

while IFS= read -r -d '' packaged_core; do
  target="$CORE_DIR/$(basename "$packaged_core")"
  if [ ! -e "$target" ] || [ -L "$target" ]; then
    ln -sfn "$packaged_core" "$target"
  fi
done < <(find /usr/lib/libretro -maxdepth 1 -type f -name '*_libretro.so' -print0)

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fetch_file() {
  local url="$1"
  local output="$2"
  curl \
    --proto '=https' \
    --tlsv1.2 \
    --fail \
    --location \
    --retry 5 \
    --retry-all-errors \
    --connect-timeout 20 \
    --output "$output" \
    "$url"
}

fetch_zip() {
  local url="$1"
  local output="$2"
  fetch_file "$url" "$output"
  unzip -tqq "$output"
}

download_core_archive() {
  local archive_name="$1"
  fetch_zip "${BUILD_URL%/}/$archive_name" "$tmp_dir/$archive_name"
}

download_core_info() {
  local archive_name="$1"
  local info_file="${archive_name%.so.zip}.info"
  fetch_file "${CORE_INFO_URL%/}/$info_file" "$INFO_DIR/$info_file"
}

install_core() {
  local archive_name="$1"
  local core_name="${archive_name%.zip}"
  local archive="$tmp_dir/$archive_name"
  local extract_dir="$tmp_dir/$core_name"
  local core_file
  mkdir -p "$extract_dir"
  unzip -oq "$archive" -d "$extract_dir"
  core_file="$(find "$extract_dir" -type f -name "$core_name" -print -quit)"
  [ -n "$core_file" ] || fail "Core is missing from archive: $archive_name"
  rm -f "$CORE_DIR/$core_name"
  install -m 0644 "$core_file" "$CORE_DIR/$core_name"
}

install_archive() {
  local base_url="$1"
  local archive_name="$2"
  local destination="$3"
  local archive="$tmp_dir/$archive_name"
  local url_name="${archive_name// /%20}"
  local before_count
  local after_count
  fetch_zip "${base_url%/}/$url_name" "$archive"
  # unzip -tqq only checks the archive's own integrity; comparing file counts
  # before and after extraction confirms it actually put files in place.
  before_count="$(find "$destination" -mindepth 1 | wc -l)"
  unzip -oq "$archive" -d "$destination"
  after_count="$(find "$destination" -mindepth 1 | wc -l)"
  [ "$after_count" -gt "$before_count" ] || fail "Archive extracted no files: $archive_name"
}

core_archives=(
  puae_libretro.so.zip
  puae2021_libretro.so.zip
  vice_x64sc_libretro.so.zip
  dosbox_pure_libretro.so.zip
  melondsds_libretro.so.zip
  mednafen_saturn_libretro.so.zip
  stella2023_libretro.so.zip
  atari800_libretro.so.zip
  prosystem_libretro.so.zip
  mednafen_lynx_libretro.so.zip
  fuse_libretro.so.zip
  cap32_libretro.so.zip
  hatari_libretro.so.zip
  bluemsx_libretro.so.zip
  swanstation_libretro.so.zip
  gearsystem_libretro.so.zip
  opera_libretro.so.zip
  mednafen_ngp_libretro.so.zip
  mednafen_vb_libretro.so.zip
  mednafen_wswan_libretro.so.zip
  freeintv_libretro.so.zip
  o2em_libretro.so.zip
  vecx_libretro.so.zip
  mame2003_plus_libretro.so.zip
  azahar_libretro.so.zip
  ymir_libretro.so.zip
)

# These functions and variables must be exported so the bash -c subshells
# spawned by xargs below can see them.
export -f fetch_file fetch_zip download_core_archive download_core_info
export tmp_dir BUILD_URL CORE_INFO_URL INFO_DIR

printf '\n%s\n' "Downloading Libretro cores and core info files from the Buildbot..."
# set -e is repeated here because each xargs-spawned bash -c shell does not
# inherit the parent shell's options.
printf '%s\n' "${core_archives[@]}" | xargs -P4 -I{} bash -c 'set -e; download_core_archive "$1"' _ {}
printf '%s\n' "${core_archives[@]}" | xargs -P4 -I{} bash -c 'set -e; download_core_info "$1"' _ {}

printf '\n%s\n' "Installing downloaded cores..."
for archive_name in "${core_archives[@]}"; do
  install_core "$archive_name"
done

if [ "$INSTALL_EXTRA_DATA" = "1" ]; then
  printf '\n%s\n' "Installing controller profiles, databases, and cheats..."
  install_archive "$ASSET_URL" autoconfig.zip "$AUTOCONFIG_DIR"
  install_archive "$ASSET_URL" database-rdb.zip "$DATABASE_DIR"
  install_archive "$ASSET_URL" cheats.zip "$CHEAT_DIR"
fi

if [ "$INSTALL_SYSTEM_FILES" = "1" ]; then
  printf '\n%s\n' "Installing core system files (PPSSPP, Dolphin, ScummVM, blueMSX, MAME 2003-Plus, and optionally LRPS2/FinalBurn Neo)..."
  system_archives=(
    PPSSPP.zip
    Dolphin.zip
    ScummVM.zip
    blueMSX.zip
    "MAME 2003-Plus.zip"
  )
  for archive_name in "${system_archives[@]}"; do
    install_archive "$SYSTEM_ASSET_URL" "$archive_name" "$SYSTEM_DIR"
  done
  if [ "$INSTALL_AUR_CORES" = "1" ]; then
    install_archive "$SYSTEM_ASSET_URL" LRPS2.zip "$SYSTEM_DIR"
    install_archive "$SYSTEM_ASSET_URL" "FinalBurn Neo (hiscore).zip" "$SYSTEM_DIR"
  fi
fi

printf '\n%s\n' "Verifying core info files..."
for archive_name in "${core_archives[@]}"; do
  info_file="${archive_name%.so.zip}.info"
  [ -s "$INFO_DIR/$info_file" ] || fail "Core info file is missing: $info_file"
done

if [ "$INSTALL_SYSTEM_FILES" = "1" ]; then
  [ -d "$SYSTEM_DIR/PPSSPP" ] || fail "PPSSPP system files are missing."
  [ -d "$SYSTEM_DIR/dolphin-emu/Sys" ] || fail "Dolphin system files are missing."
  [ -d "$SYSTEM_DIR/scummvm" ] || fail "ScummVM system files are missing."
  [ -d "$SYSTEM_DIR/Machines" ] || fail "blueMSX machine files are missing."
  [ -d "$SYSTEM_DIR/Databases" ] || fail "blueMSX databases are missing."
  if [ "$INSTALL_AUR_CORES" = "1" ]; then
    [ -f "$SYSTEM_DIR/pcsx2/resources/GameIndex.yaml" ] || fail "LRPS2 system files are missing."
  fi
fi

printf '\n%s\n' "Checking core library dependencies..."
missing_libraries=""
while IFS= read -r -d '' core_file; do
  if ! result="$(LC_ALL=C ldd "$core_file" 2>&1)" && ! grep -q 'not found' <<< "$result"; then
    missing_libraries+="$(basename "$core_file"): $result"$'\n'
    continue
  fi
  missing="$(awk '/not found/{print $1}' <<< "$result")"
  if [ -n "$missing" ]; then
    missing_libraries+="$(basename "$core_file"): $missing"$'\n'
  fi
done < <(find "$CORE_DIR" -maxdepth 1 \( -type f -o -type l \) -name '*_libretro.so' -print0)

[ -z "$missing_libraries" ] || fail "Missing core libraries:\n$missing_libraries"

printf '\n%s\n' "Configuring retroarch.cfg..."
new_config=0
if [ ! -e "$CFG" ]; then
  install -m 0644 /etc/retroarch.cfg "$CFG"
  new_config=1
fi

backup=""
if [ "$new_config" -eq 0 ] && [ -s "$CFG" ]; then
  backup="$CFG.bak.$(date +%Y%m%d-%H%M%S)"
  cp -p "$CFG" "$backup"
  mapfile -t old_backups < <(
    find "$(dirname "$CFG")" -maxdepth 1 -name "$(basename "$CFG").bak.*" -printf '%T@ %p\n' \
      | sort -rn \
      | awk 'NR>5{print $2}'
  )
  [ "${#old_backups[@]}" -eq 0 ] || rm -f "${old_backups[@]}"
fi

escape_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//&/\\&}"
  value="${value//|/\\|}"
  printf '%s' "$value"
}

set_cfg_string() {
  local key="$1"
  local value="$2"
  local escaped
  escaped="$(escape_value "$value")"
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$CFG"; then
    sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = \"${escaped}\"|" "$CFG"
  else
    printf '%s = "%s"\n' "$key" "$value" >> "$CFG"
  fi
}

set_cfg_bool() {
  local key="$1"
  local value="$2"
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$CFG"; then
    sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$CFG"
  else
    printf '%s = %s\n' "$key" "$value" >> "$CFG"
  fi
}

# This unconditionally overwrites the user's menu driver choice on every run; see README.md.
set_cfg_string menu_driver ozone
set_cfg_string assets_directory /usr/share/retroarch/assets
set_cfg_string libretro_directory "$CORE_DIR"
set_cfg_string libretro_info_path "$INFO_DIR"
set_cfg_string system_directory "$SYSTEM_DIR"
set_cfg_string savefile_directory "$SAVE_DIR"
set_cfg_string savestate_directory "$STATE_DIR"
set_cfg_string screenshot_directory "$SCREENSHOT_DIR"
set_cfg_string playlist_directory "$PLAYLIST_DIR"
set_cfg_string thumbnails_directory "$THUMBNAIL_DIR"
set_cfg_string core_assets_directory "$CORE_ASSETS_DIR"
set_cfg_string cache_directory "$CACHE_DIR"
set_cfg_string recording_output_directory "$RECORDING_DIR"
set_cfg_string input_remapping_directory "$REMAP_DIR"
set_cfg_string core_options_path "$RA_CONFIG/retroarch-core-options.cfg"
set_cfg_string joypad_autoconfig_dir "$AUTOCONFIG_DIR"
set_cfg_string content_database_path "$DATABASE_DIR"
set_cfg_string cheat_database_path "$CHEAT_DIR"
set_cfg_string overlay_directory /usr/share/libretro/overlays
set_cfg_string video_shader_dir /usr/share/libretro/shaders
set_cfg_string audio_filter_dir /usr/lib/retroarch/filters/audio
set_cfg_string video_filter_dir /usr/lib/retroarch/filters/video
set_cfg_string core_updater_buildbot_url "${BUILD_URL%/}/"
set_cfg_string core_updater_buildbot_assets_url "${BUILDBOT_ASSETS_URL%/}/"
set_cfg_bool core_updater_auto_extract_archive true

printf '\n%s\n' "Exporting RetroArch to the host desktop..."
if command -v distrobox-export >/dev/null 2>&1; then
  mkdir -p "$HOME/.local/bin"
  # Delete before re-exporting so reruns are idempotent and don't leave stale duplicate entries.
  distrobox-export --bin /usr/bin/retroarch --export-path "$HOME/.local/bin" --delete >/dev/null 2>&1 || true
  distrobox-export --bin /usr/bin/retroarch --export-path "$HOME/.local/bin"

  # `distrobox-export --app` on the packaged desktop file did not reliably appear in
  # host application menus: some desktop environments hide an entry whose Exec/TryExec
  # doesn't resolve to something directly runnable from the host. Writing a minimal
  # desktop entry that points straight at the already-exported host-side wrapper above
  # avoids that ambiguity entirely, and lets us set Categories explicitly.
  applications_dir="$HOME/.local/share/applications"
  mkdir -p "$applications_dir"
  rm -f "$applications_dir/com.libretro.RetroArch.desktop"
  cat > "$applications_dir/retroarch.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=RetroArch
Comment=Frontend for emulators, game engines and media players
Exec=$HOME/.local/bin/retroarch
TryExec=$HOME/.local/bin/retroarch
Icon=retroarch
Terminal=false
Categories=Game;Emulator;
StartupNotify=true
EOF
  chmod 0644 "$applications_dir/retroarch.desktop"
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$applications_dir" >/dev/null 2>&1 || true
  fi
fi

printf '\n%s\n' "Writing the installation inventory..."
{
  printf 'Created: %s\n' "$(date --iso-8601=seconds)"
  printf 'Distrobox: %s\n' "${CONTAINER_ID:-unknown}"
  retroarch_version="$(retroarch --version)"
  printf 'RetroArch: %s\n' "${retroarch_version%%$'\n'*}"
  printf '\nExplicitly installed packages\n'
  pacman -Qqe | sort
  printf '\nForeign and AUR packages\n'
  pacman -Qm | sort
  printf '\nAvailable cores\n'
  find "$CORE_DIR" -maxdepth 1 \( -type f -o -type l \) -name '*_libretro.so' -printf '%f -> %l\n' | sort
  printf '\nRetroArch directories\n'
  printf 'Configuration: %s\n' "$RA_CONFIG"
  printf 'Cores: %s\n' "$CORE_DIR"
  printf 'System and BIOS: %s\n' "$SYSTEM_DIR"
  printf 'Saves: %s\n' "$SAVE_DIR"
  printf 'States: %s\n' "$STATE_DIR"
} > "$INVENTORY_FILE"

printf '%s\n' "$retroarch_version"
[ -z "$backup" ] || printf '%s\n' "Configuration backup: $backup"
ARCHSETUP

chmod +x "$INNER_SCRIPT"

printf '\n%s\n' "Removing any existing Distrobox container '$BOX_NAME'..."
distrobox stop --yes "$BOX_NAME" >/dev/null 2>&1 || true
distrobox rm --force --yes "$BOX_NAME" >/dev/null 2>&1 || true

create_args=(
  create
  --name "$BOX_NAME"
  --image "$IMAGE"
  --pull
  --yes
  --additional-packages "sudo ca-certificates"
)
if [ "$HOST_NVIDIA" -eq 1 ]; then
  create_args+=(--nvidia)
fi
if [ -n "$EXTRA_VOLUMES" ]; then
  for extra_volume_path in "${extra_volume_paths[@]}"; do
    create_args+=(--volume "$extra_volume_path:$extra_volume_path:$EXTRA_VOLUMES_MODE,rslave")
  done
fi
printf '\n%s\n' "Creating Distrobox container '$BOX_NAME'..."
distrobox "${create_args[@]}"

printf '\n%s\n' "Running the installation inside the Distrobox container..."
distrobox enter "$BOX_NAME" -- env \
  BUILD_URL="$BUILD_URL" \
  ASSET_URL="$ASSET_URL" \
  SYSTEM_ASSET_URL="$SYSTEM_ASSET_URL" \
  BUILDBOT_ASSETS_URL="$BUILDBOT_ASSETS_URL" \
  CORE_INFO_URL="$CORE_INFO_URL" \
  RETROARCH_ROOT="$RETROARCH_ROOT" \
  INSTALL_EXTRA_DATA="$INSTALL_EXTRA_DATA" \
  INSTALL_SYSTEM_FILES="$INSTALL_SYSTEM_FILES" \
  INSTALL_AUR_CORES="$INSTALL_AUR_CORES" \
  INSTALL_PARU_DEBUG="$INSTALL_PARU_DEBUG" \
  HOST_NVIDIA="$HOST_NVIDIA" \
  INVENTORY_FILE="$INVENTORY_FILE" \
  /bin/bash "$INNER_SCRIPT"

ra_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/retroarch"

if [ "$CHEZMOI_INTEGRATION" = "1" ] && command -v chezmoi >/dev/null 2>&1 && chezmoi source-path >/dev/null 2>&1; then
  printf '\n%s\n' "Adding RetroArch configuration to chezmoi..."
  if [ -f "$ra_config_dir/retroarch.cfg" ]; then
    chezmoi add "$ra_config_dir/retroarch.cfg" || printf 'Warning: chezmoi add failed for %s\n' "$ra_config_dir/retroarch.cfg" >&2
  fi
  if [ -f "$ra_config_dir/retroarch-core-options.cfg" ]; then
    chezmoi add "$ra_config_dir/retroarch-core-options.cfg" || printf 'Warning: chezmoi add failed for %s\n' "$ra_config_dir/retroarch-core-options.cfg" >&2
  fi
  if find "$ra_config_dir/remaps" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
    chezmoi add "$ra_config_dir/remaps" || printf 'Warning: chezmoi add failed for %s\n' "$ra_config_dir/remaps" >&2
  fi
fi

printf '\n%s\n' "Setup complete."
printf 'Start:               %s\n' "retroarch"
printf 'Alternative start:   %s\n' "distrobox enter $BOX_NAME -- retroarch"
printf 'Desktop:             %s\n' "RetroArch"
printf 'Configuration:       %s\n' "$ra_config_dir/retroarch.cfg"
printf 'Cores:               %s\n' "$ra_config_dir/cores"
printf 'System and BIOS:     %s\n' "$RETROARCH_ROOT/system"
printf 'Saves:               %s\n' "$RETROARCH_ROOT/saves"
printf 'States:              %s\n' "$RETROARCH_ROOT/states"
printf 'Controller profiles: %s\n' "$ra_config_dir/autoconfig"
printf 'Inventory:           %s\n' "$INVENTORY_FILE"

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *)
    printf '\n%s\n' "Note: $HOME/.local/bin is not on your PATH, so \"retroarch\" will not run directly in a new terminal yet. Add it to your shell's PATH, or run $HOME/.local/bin/retroarch directly."
    ;;
esac
