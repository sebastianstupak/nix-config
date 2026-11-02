# Headless Moonlight pairing (`pair-sunshine.ps1`)

Pair a Windows Moonlight client with a Sunshine host over the NetBird overlay
**without the web UI, without typing a PIN, and without any credential touching
a shell history or an AI context.** Pairing is mutual and persistent — once
paired, you never pair that client<->host again.

## One-time setup (per host)

Each Sunshine host has **its own** admin password. Store it **encrypted** — the
script prompts for it hidden and writes a Windows **DPAPI** blob that only *your
Windows account, on this machine* can decrypt. The password is never typed on a
command line, never written in plaintext, and never committed:

```powershell
.\pair-sunshine.ps1 hestia.netbird.cloud -SetPassword
```

The resulting `~\.config\sunshine-pair\hestia.netbird.cloud.pass` is ciphertext
(begins `01000000d08c9ddf…`, the DPAPI header) and is additionally ACL-locked to
your user. Copying it to another PC or user makes it undecryptable — by design.

If you don't know the host's password (or it was rotated), set a fresh one on
the host over SSH — no old password needed:

```bash
ssh hestia 'systemctl --user stop sunshine; sunshine --creds sebastianstupak "YourNewPass"; systemctl --user start sunshine'
```

Then put that same value in the `.pass` file above.

## Pair

```powershell
./pair-sunshine.ps1 hestia.netbird.cloud
```

What it does: opens an SSH tunnel to the host's localhost-only Sunshine API,
runs `moonlight pair` with a random PIN, reads the pending pairing's id from
`GET /api/pin`, and submits `{pairing_id, pin, name}` to `POST /api/pin` with
the admin password from your `.pass` file (Basic auth; no Origin/Referer header,
so Sunshine's CSRF check skips non-browser clients). Verifies with
`moonlight list`.

## Notes

- **Persistence:** pairings survive on both ends. They are lost only if a host
  is reinstalled (its Sunshine CA is regenerated) — the durable fix is to put
  the host's `~/.config/sunshine/credentials/{cacert,cakey}.pem` under sops so a
  reinstall restores the same identity. (Not done yet; follow-up.)
- **Why a tunnel, not a direct call:** `origin_web_ui_allowed = "pc"` binds the
  Sunshine web/API to localhost, so the request must originate on the host. The
  SSH tunnel makes it appear local.
- **Linux/NixOS clients:** the same flow works with `bash` + `curl` + `ssh`; a
  bash port can live here too if needed.
