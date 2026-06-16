# DBeaver Credential Decrypt Helper

> ⚠️ **Compatibility:** This only works with DBeaver's **default/no-master-password**
> setup. If you have set a DBeaver master password, decryption will fail because
> the key is derived from your password, not the hardcoded `LOCAL_KEY_CACHE` key.

A small Python CLI that automates the reverse-engineered decryption of DBeaver's
`credentials-config.json`.

## Background

DBeaver stores saved database credentials in `credentials-config.json` under the
workspace directory. With the default setup (no master password), the file is
encrypted with **AES/CBC/PKCS5Padding** using a static 16-byte key hardcoded in
`org.jkiss.dbeaver.model`'s `BaseProjectImpl.class` (`LOCAL_KEY_CACHE`).

This script locates the file automatically, decrypts it, and prints the JSON
contents.

## Install

Requires [pycryptodome](https://www.pycryptodome.org/):

```bash
pip install -r requirements.txt
```

## Usage

Auto-locate and decrypt:

```bash
./dbeaver_decrypt.py
```

List discovered files:

```bash
./dbeaver_decrypt.py -l
```

Decrypt a specific file:

```bash
./dbeaver_decrypt.py -f ~/.local/share/DBeaverData/workspace6/General/credentials-config.json
```

Use a custom key:

```bash
./dbeaver_decrypt.py -k babb4a9f774ab853c96c2d653dfe544a
```

Print raw decrypted bytes instead of pretty JSON:

```bash
./dbeaver_decrypt.py -r
```

Skip PKCS5 unpadding and print raw AES-decrypted bytes:

```bash
./dbeaver_decrypt.py --no-unpad
```

Include connection names and server metadata from `data-sources.json`:

```bash
./dbeaver_decrypt.py --with-meta
```

This adds `name`, `host`, `port`, and `database` next to each credential entry.

## Supported locations

The script searches common DBeaver data directories:

- `~/.local/share/DBeaverData/**/credentials-config.json`
- `~/AppData/Roaming/DBeaverData/**/credentials-config.json` (Windows,
  equivalent to `%APPDATA%\DBeaverData`)
- Flatpak: `~/.var/app/**/credentials-config.json`

## Behavior

- If exactly one file is found, it is decrypted automatically.
- If multiple files are found, you must select one with `-f`.
- Non-zero exit codes are returned for missing files or decryption failures.
- If the decrypted bytes are not valid JSON, they are printed raw with a warning.

## Security warnings

- **Output is plaintext.** Decrypted passwords are printed to stdout and may be
  captured by shell history, terminal scrollback, logging tools, or adjacent users.
  Avoid piping output to files or shared sessions; clear terminal history afterward.
- **Custom keys are visible.** If you use `-k`, the key appears in your shell
  history and in process listings (`ps`) while the command runs.
- **File permissions matter.** The script warns if `credentials-config.json` is
  readable by other users. Because the default key is public knowledge, anyone
  with read access to the file can recover your passwords.
- **Use a master password or OS keyring.** To mitigate this, enable a DBeaver
  master password or configure DBeaver to use your OS keyring for sensitive
  connections.
