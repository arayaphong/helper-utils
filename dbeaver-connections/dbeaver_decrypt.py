#!/usr/bin/env python3
"""
Decrypt DBeaver credentials-config.json.

DBeaver (default/no-master-password setup) encrypts credentials with
AES/CBC/PKCS5Padding using a hardcoded key embedded in the model JAR.

This script locates the credentials file automatically or accepts an explicit
path, decrypts it, and prints the JSON contents. Optionally, it can enrich the
output with connection names and server metadata from the nearby
``data-sources.json`` file.
"""

from __future__ import annotations

import argparse
import json
import stat
import sys
from pathlib import Path
from typing import Iterable

HARD_CODED_KEY_HEX = "babb4a9f774ab853c96c2d653dfe544a"


class DecryptionError(Exception):
    """Raised when ciphertext cannot be decrypted or un-padded."""


def _get_aes() -> type:
    """Import AES from pycryptodome."""
    try:
        from Crypto.Cipher import AES  # type: ignore
        return AES
    except ImportError as exc:
        print(
            "ERROR: pycryptodome is required.\n"
            "Install it with:\n"
            "  pip install pycryptodome",
            file=sys.stderr,
        )
        raise SystemExit(1) from exc


def _default_search_roots() -> Iterable[Path]:
    home = Path.home()
    candidates = [
        home / ".local" / "share" / "DBeaverData",
        home / "AppData" / "Roaming" / "DBeaverData",
        home / ".var" / "app",
    ]
    for root in candidates:
        if root.exists():
            yield root


def _find_credentials_files() -> list[Path]:
    files: list[Path] = []
    for root in _default_search_roots():
        files.extend(root.rglob("credentials-config.json"))
    return sorted(set(files))


def _check_file_permissions(path: Path) -> None:
    """Warn if the credentials file is readable by other users."""
    try:
        mode = path.stat().st_mode
    except OSError:
        return
    if mode & stat.S_IROTH:
        print(
            f"WARNING: {path} is world-readable. Anyone on this system can read "
            "your encrypted credentials (and decrypt them with the known key).",
            file=sys.stderr,
        )
    elif mode & stat.S_IRGRP:
        print(
            f"WARNING: {path} is group-readable. Members of its group can read "
            "your encrypted credentials (and decrypt them with the known key).",
            file=sys.stderr,
        )


def _load_connection_metadata(creds_path: Path) -> dict[str, dict[str, str]]:
    """
    Load connection names and server metadata from ``data-sources.json``.

    The metadata file normally lives in the same directory as
    ``credentials-config.json`` or one level above it.
    """
    for ds_path in (
        creds_path.with_name("data-sources.json"),
        creds_path.parent.parent / "data-sources.json",
    ):
        if not ds_path.is_file():
            continue
        try:
            data = json.loads(ds_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue

        connections = data.get("connections", {})
        return {
            conn_id: {
                "name": conn.get("name", ""),
                "host": conn.get("configuration", {}).get("host", ""),
                "port": conn.get("configuration", {}).get("port", ""),
                "database": conn.get("configuration", {}).get("database", ""),
            }
            for conn_id, conn in connections.items()
        }
    return {}


def _enrich_with_metadata(
    credentials: dict,
    metadata: dict[str, dict[str, str]],
) -> dict:
    """Add connection name/host/port/database next to each credential entry."""
    enriched: dict = {}
    for conn_id, conn_data in credentials.items():
        meta = metadata.get(conn_id, {})
        entry: dict = {}
        # Include metadata fields first if they have a value.
        for field in ("name", "host", "port", "database"):
            value = meta.get(field, "")
            if value:
                entry[field] = value
        entry.update(conn_data)
        enriched[conn_id] = entry
    return enriched


def decrypt(data: bytes, key: bytes, *, skip_unpad: bool = False) -> bytes:
    """
    Decrypt AES/CBC/PKCS5Padding ciphertext.

    The input is expected to be ``iv || ciphertext``. The first 16 bytes are the IV.
    """
    if len(key) != 16:
        raise ValueError("AES key must be 16 bytes")
    if len(data) < 32:
        raise ValueError("data is too short to be valid encrypted data")

    iv, ciphertext = data[:16], data[16:]
    AES = _get_aes()
    cipher = AES.new(key, AES.MODE_CBC, iv)
    decrypted = cipher.decrypt(ciphertext)

    if skip_unpad:
        return decrypted

    # PKCS5/PKCS7 unpadding (block size 16)
    pad_len = decrypted[-1]
    if not (1 <= pad_len <= 16):
        raise DecryptionError("invalid PKCS5 padding length")
    if decrypted[-pad_len:] != bytes([pad_len]) * pad_len:
        raise DecryptionError("PKCS5 padding verification failed")
    return decrypted[:-pad_len]


def decrypt_file(path: Path, key: bytes, *, skip_unpad: bool = False) -> bytes:
    """Read and decrypt a credentials-config.json file."""
    data = path.read_bytes()
    return decrypt(data, key, skip_unpad=skip_unpad)


def _parse_key(key_hex: str) -> bytes:
    try:
        key = bytes.fromhex(key_hex)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            "AES key must be a valid hex string"
        ) from exc
    if len(key) != 16:
        raise argparse.ArgumentTypeError(
            "AES key must be 16 bytes (32 hex characters)"
        )
    return key


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Decrypt DBeaver credentials-config.json",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s
  %(prog)s -f ~/.local/share/DBeaverData/workspace6/General/credentials-config.json
  %(prog)s --with-meta
  %(prog)s -r
""",
    )
    parser.add_argument(
        "-f", "--file",
        type=Path,
        help="Path to credentials-config.json (auto-detected if omitted)",
    )
    parser.add_argument(
        "-k", "--key",
        default=HARD_CODED_KEY_HEX,
        type=_parse_key,
        help="AES key in hex (default: hardcoded DBeaver key)",
    )
    parser.add_argument(
        "-r", "--raw",
        action="store_true",
        help="Print raw decrypted bytes instead of formatted JSON",
    )
    parser.add_argument(
        "--no-unpad",
        dest="no_unpad",
        action="store_true",
        help="Skip PKCS5 unpadding and print raw AES-decrypted bytes",
    )
    parser.add_argument(
        "--with-meta",
        dest="with_meta",
        action="store_true",
        help="Enrich output with connection name/host/port/database from data-sources.json",
    )
    parser.add_argument(
        "-l", "--list",
        action="store_true",
        help="List discovered credentials-config.json files and exit",
    )
    args = parser.parse_args()

    if args.file:
        creds_path = args.file.expanduser().resolve()
        if not creds_path.is_file():
            print(f"ERROR: file not found: {creds_path}", file=sys.stderr)
            return 1
    else:
        found = _find_credentials_files()
        if args.list:
            if not found:
                print("No credentials-config.json files found in default locations.")
                return 0
            for p in found:
                print(p)
            return 0
        if not found:
            print(
                "ERROR: Could not find credentials-config.json in default locations.\n"
                "Run with -l to see searched locations, or pass -f /path/to/file.",
                file=sys.stderr,
            )
            return 1
        if len(found) > 1:
            print("Multiple credentials files found:", file=sys.stderr)
            for p in found:
                print(f"  {p}", file=sys.stderr)
            print("Use -f to choose one, or -l to list them.", file=sys.stderr)
            return 1
        creds_path = found[0]
        print(f"Using: {creds_path}", file=sys.stderr)

    _check_file_permissions(creds_path)

    try:
        plaintext = decrypt_file(creds_path, args.key, skip_unpad=args.no_unpad)
    except DecryptionError as exc:
        print(
            f"ERROR: decryption failed: {exc}\n"
            "If this file was encrypted with a DBeaver master password, "
            "this tool cannot decrypt it.",
            file=sys.stderr,
        )
        return 1

    print(
        "WARNING: decrypted credentials will be printed to stdout. "
        "They may be captured by shell history, logs, or terminal scrollback.",
        file=sys.stderr,
    )

    if args.raw or args.no_unpad:
        sys.stdout.buffer.write(plaintext)
    else:
        try:
            parsed = json.loads(plaintext)
        except json.JSONDecodeError:
            print(
                "WARNING: decrypted data is not valid JSON; printing raw bytes.",
                file=sys.stderr,
            )
            sys.stdout.buffer.write(plaintext)
            return 0

        if args.with_meta:
            metadata = _load_connection_metadata(creds_path)
            if metadata:
                parsed = _enrich_with_metadata(parsed, metadata)
            else:
                print(
                    "WARNING: could not find or parse data-sources.json; "
                    "output will not include connection metadata.",
                    file=sys.stderr,
                )
        print(json.dumps(parsed, indent=2, ensure_ascii=False))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
