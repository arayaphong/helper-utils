#!/usr/bin/env bash
# fixline_line.sh — Show/hide Wine/Proton edge-/corner-windows that act as borders for LINE
# -----------------------------------------------------------------------------
# * Matches "steam_proton" WM_CLASS (as seen in your setup)
# * Adds WM_NAME check for "LINE" to target only LINE windows
# * Detect borders dynamically using geometry (handles 11px full frames)
# * Track multiple windows, re-show on focus
# * Hide on unfocus (all others) & on actual close
# * Cleanup on SIGINT/SIGTERM
# -----------------------------------------------------------------------------

set -uo pipefail
IFS=$' \n\t' # include space for read splitting

# ──────────────────────────────  Global defaults  ─────────────────────────────
THIN_THRESHOLD=20  # Max width/height for border windows (covers your 11px)

# WM_CLASS → enabled (1); add others if needed
declare -A APP_CONFIGS=(
  [steam_proton]="1"  # Matches your Proton/Wine setup
)

# Tracked Wine/Proton executables
declare -A TRACKED_EXES=(
  [line.exe]="1"
  [linemediaplayer.exe]="1"
)

# ──────────────────────────────  Logging helpers  ─────────────────────────────
log() {
  local lvlname=$1 msg=$2 lvl want
  case $lvlname in info) lvl=1 ;; warn) lvl=2 ;; error) lvl=3 ;; esac
  case info in info) want=1 ;; warn) want=2 ;; error) want=3 ;; esac
  ((lvl >= want)) && printf '%s: %s\n' "${lvlname^^}" "$msg" >&2
}
info() { log info "$*"; }
warn() { log warn "$*"; }
error() { log error "$*"; }

# ──────────────────────────────  Sanity checks  ─────────────────────────────
for cmd in xprop xwininfo xdotool; do
  if ! command -v "$cmd" &>/dev/null; then
    error "$cmd is required"
    exit 1
  fi
done

info "Starting border manager (dynamic detection, threshold=$THIN_THRESHOLD)"
for app in "${!APP_CONFIGS[@]}"; do
  info "  Match '$app'"
done
info "Tracking executables:"
for exe in "${!TRACKED_EXES[@]}"; do
  info "  $exe"
done

# ──────────────────────────────  Helper functions  ────────────────────────────
get_wm_class() {
  xprop -id "$1" WM_CLASS 2>/dev/null |
    awk -F\" '{ print tolower($(NF-1)) }'
}

get_wm_name() {
  xprop -id "$1" WM_NAME 2>/dev/null |
    awk -F\" '{ print $2 }'
}

get_pid() {
  xprop -id "$1" _NET_WM_PID 2>/dev/null | awk '{print $3}'
}

window_exists() {
  xwininfo -id "$1" &>/dev/null
}

# Get Wine/Proton executable name from window
get_wine_exe_name() {
  local win_id=$1
  local pid=$(get_pid "$win_id")
  if [ -n "$pid" ]; then
    # Check if /proc/PID/cmdline exists and is readable
    if [ -r "/proc/$pid/cmdline" ]; then
      # Check cmdline for Wine executable patterns
      local cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
      # Look for patterns like: wine64-preloader /path/to/something.exe
      # or: pressure-vessel-wrap wine64 something.exe
      local exe_name=$(echo "$cmdline" | grep -oE '([^ /]+\.exe)' | tail -1)
      if [ -z "$exe_name" ] && [ -r "/proc/$pid/exe" ]; then
        # Try getting from exe symlink (for some Wine versions)
        exe_name=$(readlink "/proc/$pid/exe" 2>/dev/null | grep -oE '[^/]+\.exe$')
      fi
      echo "$exe_name"
    fi
  fi
}

# Find border windows for a main window by geometry
calculate_border_ids() {
  local main_id=$1 wm_class=$2
  local pid main_x main_y main_w main_h
  edge_ids=()
  corner_ids=()

  # Get main window geometry
  local info=$(xwininfo -id "$main_id" -all 2>/dev/null)
  main_x=$(echo "$info" | grep "Absolute upper-left X:" | awk '{print $4}')
  main_y=$(echo "$info" | grep "Absolute upper-left Y:" | awk '{print $4}')
  main_w=$(echo "$info" | grep "Width:" | awk '{print $2}')
  main_h=$(echo "$info" | grep "Height:" | awk '{print $2}')
  
  # Ensure main window geometry is valid
  if [ -z "$main_x" ] || [ -z "$main_y" ] || [ -z "$main_w" ] || [ -z "$main_h" ]; then
    return
  fi
  
  pid=$(get_pid "$main_id")

  # Find candidates: prefer same PID, fallback to same WM_CLASS
  local candidates
  if [ -n "$pid" ]; then
    candidates=$(xdotool search --pid "$pid" 2>/dev/null)
  else
    candidates=$(xdotool search --class "$wm_class" 2>/dev/null)
  fi

  for win in $candidates; do
    [ "$win" = "$main_id" ] && continue
    info=$(xwininfo -id "$win" -all 2>/dev/null)
    local override=$(echo "$info" | grep "Override Redirect State:" | awk '{print $4}')
    local wtype=$(echo "$info" | grep "Window type:" -A1 | grep -v "Window type:" | xargs)
    local x=$(echo "$info" | grep "Absolute upper-left X:" | awk '{print $4}')
    local y=$(echo "$info" | grep "Absolute upper-left Y:" | awk '{print $4}')
    local w=$(echo "$info" | grep "Width:" | awk '{print $2}')
    local h=$(echo "$info" | grep "Height:" | awk '{print $2}')

    # Skip if geometry is invalid
    if [ -z "$x" ] || [ -z "$y" ] || [ -z "$w" ] || [ -z "$h" ]; then
      continue
    fi

    # Check if it's a border (thin, override-redirect, dialog, adjacent)
    if [ "$override" = "yes" ] && [ "$wtype" = "Dialog" ] && { [ "$w" -le "$THIN_THRESHOLD" ] || [ "$h" -le "$THIN_THRESHOLD" ]; }; then
      # Left edge
      if [ "$x" -lt "$main_x" ] && [ "$y" -eq "$main_y" ] && [ "$h" -eq "$main_h" ]; then
        edge_ids+=("$win")
      # Top edge
      elif [ "$x" -eq "$main_x" ] && [ "$y" -lt "$main_y" ] && [ "$w" -eq "$main_w" ]; then
        edge_ids+=("$win")
      # Right edge
      elif [ $((x + w)) -gt $((main_x + main_w)) ] && [ "$y" -eq "$main_y" ] && [ "$h" -eq "$main_h" ]; then
        edge_ids+=("$win")
      # Bottom edge
      elif [ $((y + h)) -gt $((main_y + main_h)) ] && [ "$x" -eq "$main_x" ] && [ "$w" -eq "$main_w" ]; then
        edge_ids+=("$win")
      # Corner (general small square, offset from main)
      elif [ "$w" -le "$THIN_THRESHOLD" ] && [ "$h" -le "$THIN_THRESHOLD" ]; then
        corner_ids+=("$win")
      fi
    fi
  done
}

map_ids() { for id; do xdotool windowmap "$id" 2>/dev/null || true; done; }
unmap_ids() { for id; do xdotool windowunmap "$id" 2>/dev/null || true; done; }

show_borders() {
  info "SHOW $current_app ($current_id): ${#edge_ids[@]} edges, ${#corner_ids[@]} corners"
  map_ids "${edge_ids[@]}"
  map_ids "${corner_ids[@]}"
}

hide_borders() {
  info "HIDE $current_app ($current_id)"
  unmap_ids "${edge_ids[@]}"
  unmap_ids "${corner_ids[@]}"
}

# ──────────────────────────────  Multi-window state & cleanup ───────────────────
declare -A open_windows=() # window_hex_id → wm_class
prev_event=""

cleanup_closed() {
  for win in "${!open_windows[@]}"; do
    if ! xprop -id "$win" &>/dev/null; then
      wm_class=${open_windows[$win]}
      current_id=$((16#${win#0x}))
      current_app="$wm_class"
      calculate_border_ids "$current_id" "$wm_class"
      hide_borders
      unset open_windows["$win"]
    fi
  done
}

cleanup_all() {
  info "Cleaning up all borders…"
  for win in "${!open_windows[@]}"; do
    wm_class=${open_windows[$win]}
    current_id=$((16#${win#0x}))
    current_app="$wm_class"
    calculate_border_ids "$current_id" "$wm_class"
    hide_borders
  done
  exit
}
trap cleanup_all SIGINT SIGTERM

# Check if a window name looks like a media player title
is_media_player_window() {
  local wm_name="$1"
  local wm_class="$2"
  
  # Must be steam_proton class
  [[ "$wm_class" != "steam_proton" ]] && return 1
  
  # Must have a non-empty name
  [[ -z "$wm_name" ]] && return 1
  
  # Exclude known system windows
  case "$wm_name" in
    "Default IME"|"Input"|"QTrayIconMessageWindow"|"LINE") return 1 ;;
  esac
  
  # If it has a name and isn't a system window, it's likely media player
  return 0
}

# ─────────────────────────────── Event loop ────────────────────────────────
xprop -root -spy _NET_ACTIVE_WINDOW | while read -r line; do
  # extract "0x..." window ID
  active_hex=$(sed -n \
    's/^_NET_ACTIVE_WINDOW(WINDOW): window id # \(0x[0-9a-f]*\)/\1/p' \
    <<<"$line")
  [[ -z "$active_hex" || "$active_hex" == "$prev_event" ]] && continue

  cleanup_closed

  # Hide borders for every other tracked window
  for win in "${!open_windows[@]}"; do
    if [[ "$win" != "$active_hex" ]]; then
      wm_class=${open_windows[$win]}
      current_id=$((16#${win#0x}))
      current_app="$wm_class"
      calculate_border_ids "$current_id" "$wm_class"
      hide_borders
      unset open_windows["$win"]
    fi
  done

  wm_class=$(get_wm_class "$active_hex")
  wm_name=$(get_wm_name "$active_hex")

  # Only process if wm_class matches
  if [[ -n "$wm_class" && ${APP_CONFIGS[$wm_class]+_} ]]; then
    wine_exe=$(get_wine_exe_name "$active_hex")
    
    # Check if it's a LINE-related window
    is_line_app=0
    
    # Method 1: Window name contains "LINE"
    if [[ "$wm_name" == *"LINE"* ]]; then
      is_line_app=1
    # Method 2: Executable is tracked
    elif [[ -n "$wine_exe" && ${TRACKED_EXES[$wine_exe]+_} ]]; then
      is_line_app=1
    # Method 3: Media player pattern
    elif is_media_player_window "$wm_name" "$wm_class"; then
      is_line_app=1
    fi
    
    if [[ $is_line_app -eq 1 ]]; then
      current_id=$((16#${active_hex#0x}))
      current_app="$wm_class"
      calculate_border_ids "$current_id" "$wm_class"
      if [ "${#edge_ids[@]}" -gt 0 ] || [ "${#corner_ids[@]}" -gt 0 ]; then
        show_borders
        open_windows["$active_hex"]="$wm_class"
      fi
    fi
  fi

  prev_event="$active_hex"
done