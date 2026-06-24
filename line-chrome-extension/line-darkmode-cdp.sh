#!/usr/bin/env bash
# Apply Chrome DevTools Protocol dark-mode settings and a light-touch CSS shim.

set -euo pipefail

PORT=9222
EXTENSION_ID="ophjlpahpchlmihnnnihgmmeilfjmjjc"
MONITOR_EVENTS=1
EXTRA_CSS=""
CSS_FILE=""

usage() {
  cat <<'EOF'
Usage: line-darkmode-cdp.sh [options]

Options:
  -p PORT        CDP port (default: 9222)
  -e EXTENSION   Chrome extension ID (default: ophjlpahpchlmihnnnihgmmeilfjmjjc)
  -c CSS         Append extra CSS rules
  -s FILE        Append extra CSS from FILE
  -q             Quiet mode (do not print CDP events)
  -h             Show this help

The script connects to the extension page target, enables auto dark mode,
sets prefers-color-scheme to dark, and injects a persistent CSS shim.
The script exits after the injection completes.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      PORT="$2"
      shift 2
      ;;
    -e)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      EXTENSION_ID="$2"
      shift 2
      ;;
    -c)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      EXTRA_CSS="$2"
      shift 2
      ;;
    -s)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      CSS_FILE="$2"
      shift 2
      ;;
    -q)
      MONITOR_EVENTS=0
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
    -*)
      usage >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CSS_FILE="$SCRIPT_DIR/line-darkmode-overrides.css"

CSS_BUNDLE=""
append_css() {
  local chunk=$1
  [[ -z "$chunk" ]] && return
  if [[ -n "$CSS_BUNDLE" ]]; then
    CSS_BUNDLE+=$'\n'
  fi
  CSS_BUNDLE+="$chunk"
}

if [[ -n "$CSS_FILE" ]]; then
  if [[ ! -r "$CSS_FILE" ]]; then
    echo "CSS file not readable: $CSS_FILE" >&2
    exit 1
  fi
  append_css "$( <"$CSS_FILE" )"
fi

if [[ -r "$DEFAULT_CSS_FILE" ]]; then
  append_css "$( <"$DEFAULT_CSS_FILE" )"
fi

append_css "$EXTRA_CSS"

export CDP_PORT="$PORT"
export CDP_EXTENSION_ID="$EXTENSION_ID"
export CDP_MONITOR_EVENTS="$MONITOR_EVENTS"
export CDP_EXTRA_CSS="$CSS_BUNDLE"

python3 - <<'PY'
import base64
import json
import os
import signal
import socket
import struct
import sys
import time
import urllib.request

PORT = int(os.environ["CDP_PORT"])
EXTENSION_ID = os.environ["CDP_EXTENSION_ID"]
MONITOR_EVENTS = int(os.environ["CDP_MONITOR_EVENTS"])
EXTRA_CSS = os.environ.get("CDP_EXTRA_CSS", "")

running = True

def stop(_signum, _frame):
    global running
    running = False

signal.signal(signal.SIGINT, stop)
signal.signal(signal.SIGTERM, stop)

def fetch_targets():
    with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json/list", timeout=5) as resp:
        return json.load(resp)

def find_target(items):
    prefix = f"chrome-extension://{EXTENSION_ID}/"
    for item in items:
        if item.get("type") == "page" and item.get("url", "").startswith(prefix):
            return item
    return None

def ws_handshake(sock, host, port, path):
    key = base64.b64encode(os.urandom(16)).decode()
    req = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n"
    )
    sock.sendall(req.encode())
    resp = b""
    while b"\r\n\r\n" not in resp:
        chunk = sock.recv(4096)
        if not chunk:
            raise RuntimeError("websocket handshake failed")
        resp += chunk
    status = resp.split(b"\r\n", 1)[0]
    if b"101" not in status:
        raise RuntimeError(status.decode("latin1", errors="replace"))

def ws_send(sock, message):
    payload = json.dumps(message, separators=(",", ":")).encode()
    mask = os.urandom(4)
    length = len(payload)
    if length < 126:
        header = struct.pack("!BB", 0x81, 0x80 | length)
    elif length < (1 << 16):
        header = struct.pack("!BBH", 0x81, 0x80 | 126, length)
    else:
        header = struct.pack("!BBQ", 0x81, 0x80 | 127, length)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    sock.sendall(header + mask + masked)

def ws_recv_messages(sock, timeout=2.0):
    sock.settimeout(timeout)
    buf = b""
    messages = []
    try:
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            buf += chunk
    except socket.timeout:
        pass

    idx = 0
    while idx + 2 <= len(buf):
        b1, b2 = buf[idx], buf[idx + 1]
        opcode = b1 & 0x0F
        masked = (b2 >> 7) & 1
        length = b2 & 0x7F
        idx += 2
        if length == 126:
            if idx + 2 > len(buf):
                break
            length = struct.unpack("!H", buf[idx:idx + 2])[0]
            idx += 2
        elif length == 127:
            if idx + 8 > len(buf):
                break
            length = struct.unpack("!Q", buf[idx:idx + 8])[0]
            idx += 8
        mask_key = b""
        if masked:
            if idx + 4 > len(buf):
                break
            mask_key = buf[idx:idx + 4]
            idx += 4
        if idx + length > len(buf):
            break
        payload = buf[idx:idx + length]
        idx += length
        if masked:
            payload = bytes(b ^ mask_key[i % 4] for i, b in enumerate(payload))
        if opcode == 1:
            messages.append(payload.decode("utf-8", errors="replace"))
    return messages

def parse_json_messages(messages):
    for message in messages:
        try:
            yield json.loads(message)
        except json.JSONDecodeError:
            continue

def cdp_script_source():
    extra_css_json = json.dumps(EXTRA_CSS)
    return r"""
(() => {
  const STYLE_ID = 'helper-utils-dark-mode-style';
  const ROOT_CLASS = 'helper-utils-dark-mode-root';
  const EXTRA_CSS = __EXTRA_CSS__;

  const css = `
    :root, html, body, input, textarea, select, button {
      color-scheme: dark !important;
    }
  ` + (EXTRA_CSS ? `\n${EXTRA_CSS}\n` : '');

  function ensureStyle() {
    const root = document.documentElement;
    if (!root) return false;

    root.classList.add(ROOT_CLASS);
    root.style.setProperty('color-scheme', 'dark', 'important');

    let style = document.getElementById(STYLE_ID);
    if (!style) {
      style = document.createElement('style');
      style.id = STYLE_ID;
      style.textContent = css;
      (document.head || root).appendChild(style);
    } else if (style.textContent !== css) {
      style.textContent = css;
    }
    return true;
  }

  function tagMessageSides() {
    const messages = document.querySelectorAll('.message-module__content_inner__j-iko');
    for (const inner of messages) {
      const isSelf = getComputedStyle(inner).flexDirection === 'row-reverse';
      inner.classList.toggle('helper-utils-self-message', isSelf);
      inner.classList.toggle('helper-utils-other-message', !isSelf);
    }
  }

  function boot() {
    if (ensureStyle()) {
      tagMessageSides();
      return;
    }
    const obs = new MutationObserver(() => {
      if (ensureStyle()) {
        tagMessageSides();
        obs.disconnect();
      }
    });
    obs.observe(document, { childList: true, subtree: true });
  }

  const tagObserver = new MutationObserver(() => tagMessageSides());

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot, { once: true });
  } else {
    boot();
  }

  tagObserver.observe(document, { childList: true, subtree: true });
  tagMessageSides();
})();
""".replace("__EXTRA_CSS__", extra_css_json)

def inject_dark_media(sock, msg_id):
    ws_send(sock, {
        "id": msg_id,
        "method": "Emulation.setEmulatedMedia",
        "params": {
            "media": "",
            "features": [{"name": "prefers-color-scheme", "value": "dark"}],
        },
    })

def inject_auto_dark(sock, msg_id):
    ws_send(sock, {
        "id": msg_id,
        "method": "Emulation.setAutoDarkModeOverride",
        "params": {"enabled": True},
    })

def inject_dark_css(sock, msg_id):
    ws_send(sock, {
        "id": msg_id,
        "method": "Runtime.evaluate",
        "params": {
            "expression": cdp_script_source(),
            "awaitPromise": False,
            "returnByValue": False,
            "userGesture": False,
        },
    })

def send_and_wait(sock, message, expected_id, timeout=5):
    ws_send(sock, message)
    deadline = time.time() + timeout
    while time.time() < deadline:
        for event in parse_json_messages(ws_recv_messages(sock, timeout=1.0)):
            if event.get("id") == expected_id:
                return event
            if MONITOR_EVENTS and event.get("method"):
                print(f"event: {event['method']}")
                sys.stdout.flush()
    raise TimeoutError(f"timed out waiting for response to id {expected_id}")

targets = fetch_targets()
target = find_target(targets)
if not target:
    raise SystemExit(f"target not found for extension {EXTENSION_ID}")

ws_url = target["webSocketDebuggerUrl"]
host_port = ws_url.split("/")[2]
host, port = host_port.split(":")
path = "/" + "/".join(ws_url.split("/")[3:])

sock = socket.create_connection((host, int(port)), timeout=5)
try:
    ws_handshake(sock, host, int(port), path)
    send_and_wait(sock, {"id": 1, "method": "Page.enable"}, 1)
    send_and_wait(sock, {"id": 2, "method": "DOM.enable"}, 2)
    send_and_wait(sock, {"id": 3, "method": "Runtime.enable"}, 3)
    send_and_wait(sock, {
        "id": 4,
        "method": "Page.addScriptToEvaluateOnNewDocument",
        "params": {"source": cdp_script_source()},
    }, 4)
    send_and_wait(sock, {
        "id": 5,
        "method": "Emulation.setAutoDarkModeOverride",
        "params": {"enabled": True},
    }, 5)
    send_and_wait(sock, {
        "id": 6,
        "method": "Emulation.setEmulatedMedia",
        "params": {
            "media": "",
            "features": [{"name": "prefers-color-scheme", "value": "dark"}],
        },
    }, 6)
    send_and_wait(sock, {
        "id": 7,
        "method": "Runtime.evaluate",
        "params": {
            "expression": cdp_script_source(),
            "awaitPromise": False,
            "returnByValue": False,
            "userGesture": False,
        },
    }, 7)

    print(f"target={target['id']}")
    print("injection complete")
finally:
    try:
        sock.close()
    except Exception:
        pass
PY
