# line-chrome-extension

Helpers for launching the LINE Chrome extension and applying dark mode through Chrome DevTools Protocol (CDP).

## What changed in this session

- Added a launcher script for opening the extension as a standalone app window.
- Added a CDP helper for forcing dark mode and keeping the session open.
- Added optional CDP port support to the launcher.
- Copied the existing Chrome profile to `/tmp/google-chrome-cdp-profile` during the first CDP workflow so the extension could launch with a usable profile.
- Renamed and moved both scripts into this folder.

## Scripts

### `line-launcher.sh`

Launches the extension app window.

Examples:

```bash
./line-chrome-extension/line-launcher.sh
./line-chrome-extension/line-launcher.sh --cdp
./line-chrome-extension/line-launcher.sh --cdp --profile /tmp/google-chrome-cdp-profile
```

### `line-copy-profile.sh`

Copies an existing Chrome user data dir into a separate profile for CDP launches.

Example:

```bash
./line-chrome-extension/line-copy-profile.sh
./line-chrome-extension/line-copy-profile.sh -s ~/.config/google-chrome -d /tmp/google-chrome-cdp-profile
```

### `line-darkmode-cdp.sh`

Connects to the extension target over CDP and applies dark-mode settings plus CSS overrides.

Examples:

```bash
./line-chrome-extension/line-darkmode-cdp.sh
./line-chrome-extension/line-darkmode-cdp.sh -c '.my-selector { color: #ddd !important; }'
```

The helper automatically loads `line-darkmode-overrides.css` from this folder when it exists.

## Notes

- `--cdp` expects a profile that already has the LINE extension installed, or it will fall back to a temporary profile.
- `line-copy-profile.sh` is the easiest way to seed `/tmp/google-chrome-cdp-profile` from your main Chrome profile before launching with `--cdp`.
- The dark-mode helper supports:
  - `-c` to append inline CSS
  - `-s` to append CSS from a file
