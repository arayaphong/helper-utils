#!/usr/bin/env bash
# Launch the LINE Chrome extension as a standalone app window.

set -euo pipefail

APP_URL="chrome-extension://ophjlpahpchlmihnnnihgmmeilfjmjjc/index.html"
CHROME_BIN="${CHROME_BIN:-}"
PROFILE_DIR=""
FOREGROUND=0
ENABLE_CDP=0
TEMP_PROFILE_DIR=""
DEFAULT_CDP_PROFILE="${XDG_DATA_HOME:-$HOME/.local/share}/helper-utils/google-chrome-cdp-profile"

usage() {
  cat <<'EOF'
Usage: line-launcher.sh [options]

Options:
  -b, --binary BIN   Chrome binary (default: auto-detect google-chrome-stable)
  -u, --url URL      Extension app URL (default: LINE extension index page)
  -p, --profile DIR  User data dir to use for the launched window
      --cdp          Enable --remote-debugging-port=9222
  -f, --foreground   Run in the foreground instead of detaching
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--binary)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      CHROME_BIN="$2"
      shift 2
      ;;
    -u|--url)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      APP_URL="$2"
      shift 2
      ;;
    -p|--profile)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      PROFILE_DIR="$2"
      shift 2
      ;;
    --cdp)
      ENABLE_CDP=1
      shift
      ;;
    -f|--foreground)
      FOREGROUND=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$CHROME_BIN" ]]; then
  for candidate in google-chrome-stable google-chrome chromium chromium-browser; do
    if command -v "$candidate" >/dev/null 2>&1; then
      CHROME_BIN="$candidate"
      break
    fi
  done
fi

if [[ -z "$CHROME_BIN" ]]; then
  echo "No Chrome binary found" >&2
  exit 1
fi

args=(
  --app="$APP_URL"
  --no-first-run
  --no-default-browser-check
)

if [[ -n "$PROFILE_DIR" ]]; then
  args+=(--user-data-dir="$PROFILE_DIR")
fi

if [[ "$ENABLE_CDP" -eq 1 ]]; then
  if [[ -z "$PROFILE_DIR" ]]; then
    if [[ -d "$DEFAULT_CDP_PROFILE" ]]; then
      args+=(--user-data-dir="$DEFAULT_CDP_PROFILE")
    else
      TEMP_PROFILE_DIR="$(mktemp -d -t chrome-extension-launcher.XXXXXX)"
      args+=(--user-data-dir="$TEMP_PROFILE_DIR")
    fi
  fi
  args+=(--remote-debugging-port=9222)
fi

if [[ "$FOREGROUND" -eq 1 ]]; then
  exec "$CHROME_BIN" "${args[@]}"
fi

log_file="${XDG_STATE_HOME:-$HOME/.local/state}/helper-utils/chrome-extension-launcher.log"
mkdir -p "$(dirname "$log_file")"
nohup "$CHROME_BIN" "${args[@]}" >"$log_file" 2>&1 &
echo $!
