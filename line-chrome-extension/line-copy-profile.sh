#!/usr/bin/env bash
# Copy an existing Chrome profile to a separate user-data dir for CDP launches.

set -euo pipefail

SOURCE_DIR=""
DEST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/helper-utils/google-chrome-cdp-profile"
CHROME_PROFILE_NAME="Default"

usage() {
  cat <<'EOF'
Usage: line-copy-profile.sh [options]

Options:
  -s, --source DIR    Source Chrome user data dir
  -d, --dest DIR      Destination user data dir (default: ~/.local/share/helper-utils/google-chrome-cdp-profile)
  -p, --profile NAME   Profile folder to keep inside the user data dir (default: Default)
  -h, --help          Show this help

Examples:
  ./line-chrome-extension/line-copy-profile.sh
  ./line-chrome-extension/line-copy-profile.sh -s ~/.config/google-chrome -d ~/.local/share/helper-utils/google-chrome-cdp-profile
EOF
}

auto_source_dir() {
  local candidate
  for candidate in \
    "${CHROME_USER_DATA_DIR:-}" \
    "$HOME/.config/google-chrome" \
    "$HOME/.config/google-chrome-stable" \
    "$HOME/.config/chromium"; do
    [[ -n "$candidate" ]] || continue
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--source)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      SOURCE_DIR="$2"
      shift 2
      ;;
    -d|--dest)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      DEST_DIR="$2"
      shift 2
      ;;
    -p|--profile)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      CHROME_PROFILE_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$SOURCE_DIR" ]]; then
  SOURCE_DIR="$(auto_source_dir)" || {
    echo "No Chrome profile source directory found" >&2
    exit 1
  }
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

if [[ -z "$CHROME_PROFILE_NAME" ]]; then
  echo "Profile name cannot be empty" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"

copy_tree() {
  local src=$1
  local dest=$2

  rm -rf "$dest"
  mkdir -p "$dest"

  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude='Cache' \
      --exclude='Code Cache' \
      --exclude='GPUCache' \
      --exclude='GrShaderCache' \
      --exclude='ShaderCache' \
      --exclude='DawnCache' \
      --exclude='Crashpad' \
      --exclude='Singleton*' \
      --exclude='Safe Browsing' \
      --exclude='Service Worker/CacheStorage' \
      "$src"/ "$dest"/
    return
  fi

  cp -a "$src"/. "$dest"/
  find "$dest" \( \
    -name 'Singleton*' -o \
    -name 'Cache' -o \
    -name 'Code Cache' -o \
    -name 'GPUCache' -o \
    -name 'GrShaderCache' -o \
    -name 'ShaderCache' -o \
    -name 'DawnCache' -o \
    -name 'Crashpad' -o \
    -path '*/Service Worker/CacheStorage' \
  \) | while read -r path; do
    rm -rf "$path"
  done
}

if [[ -d "$SOURCE_DIR/$CHROME_PROFILE_NAME" ]]; then
  copy_tree "$SOURCE_DIR/$CHROME_PROFILE_NAME" "$DEST_DIR/$CHROME_PROFILE_NAME"
else
  echo "Profile folder not found: $SOURCE_DIR/$CHROME_PROFILE_NAME" >&2
  exit 1
fi

if [[ -f "$SOURCE_DIR/Local State" ]]; then
  cp -f "$SOURCE_DIR/Local State" "$DEST_DIR/Local State"
fi

echo "$DEST_DIR"
