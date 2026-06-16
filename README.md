# helper-utils

A loose collection of small helper tools, scripts, and GUI utilities for day-to-day Linux tasks.

## Contents

| Directory | Description |
|-----------|-------------|
| [`dbeaver-connections`](dbeaver-connections/) | Decrypt DBeaver saved credentials from `credentials-config.json` |
| [`helper-aux`](helper-aux/) | Assorted shell helpers for desktop automation and cleanup |
| [`openvpn3-gui-main`](openvpn3-gui-main/) | A simple GTK+ 3 OpenVPN connection manager written in Vala |

---

## dbeaver-connections

A Python CLI that decrypts DBeaver's `credentials-config.json` when no master password is set. It uses the well-known hardcoded AES key from DBeaver's model JAR and can optionally enrich output with connection metadata from `data-sources.json`.

**Key files:**

- `dbeaver_decrypt.py` — main CLI
- `requirements.txt` — Python dependencies (`pycryptodome`)
- `README.md` — detailed usage and security notes

Quick start:

```bash
cd dbeaver-connections
pip install -r requirements.txt
./dbeaver_decrypt.py
```

See [`dbeaver-connections/README.md`](dbeaver-connections/README.md) for options and security warnings.

---

## helper-aux

Small Bash helpers that live in `helper-aux/`.

| Script | Purpose |
|--------|---------|
| `bashColors` | Sets a colorful `PS1` prompt |
| `changelang` | Toggles GNOME keyboard input sources via D-Bus |
| `deskfind` | Greps installed `*.desktop` files for a pattern |
| `fixline.sh` | Show/hide Wine/Proton border windows for the LINE app |
| `fixline-debug.sh` | Same as `fixline.sh` with debug logging (`-d`) |

Most of these are standalone; add the directory to your `PATH` or symlink the scripts you use.

---

## openvpn3-gui-main

A GTK+ 3.0 OpenVPN connection manager written in Vala. It provides a small GUI with connect/disconnect buttons, a status indicator, and a real-time output log. Privilege elevation is handled via `pkexec`.

**Key files:**

- `src/openvpn-gui.vala` — application source
- `meson.build` / `meson_options.txt` — Meson build configuration
- `README.md` — build instructions and requirements

Quick start:

```bash
cd openvpn3-gui-main
meson setup builddir
ninja -C builddir
./builddir/openvpn-gui
```

See [`openvpn3-gui-main/README.md`](openvpn3-gui-main/README.md) for dependencies and configuration.
