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

**Or skip the password entirely** — see "Pairing with no password at all" below.
Prefer that when you do not already know the host's password: resetting it means
inventing one, writing it down somewhere, and typing it on a command line, where
the `-0` route needs none of that.

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

## Pairing with no password at all (`sunshine -0`)

Sunshine's `-0` flag makes it **read PINs from stdin**, which bypasses the web
UI and therefore its admin password completely. Used on 2026-11-03 to pair
zagreus -> hestia, which was otherwise blocked: hestia's password had never been
recorded, and the PIN for a pairing has to go into the web UI of the machine
being streamed FROM.

Better than resetting the password whenever you do not already have it — no
credential to invent, store or type, no web UI, and no ~1 minute PIN race.

It is a **startup** flag, so the running instance has to be replaced for the
duration. On the HOST:

```bash
export XDG_RUNTIME_DIR=/run/user/1000
eval "$(systemctl --user show-environment | sed 's/^/export /')"
CONF=$(systemctl --user show sunshine -p ExecStart |
  grep -oE '/nix/store/[a-z0-9]+-sunshine\.conf' | head -1)

systemctl --user stop sunshine
mkfifo -m 600 /tmp/sun.pin
setsid bash -c "exec 3<>/tmp/sun.pin; exec /run/wrappers/bin/sunshine -0 $CONF <&3 >/tmp/sun-manual.log 2>&1" &
# wait for: Configuration UI available
```

Then from the CLIENT, and feed the PIN on the host once it prompts
`Please insert pin:`

```bash
QT_QPA_PLATFORM=offscreen moonlight pair <host>.netbird.cloud --pin 6142
ssh <host> 'echo 6142 > /tmp/sun.pin'
```

Afterwards, on the host: `pkill -f "sunshine -0"`, `rm /tmp/sun.pin`,
`systemctl --user start sunshine`. The pairing lives in `sunshine_state.json`,
so it survives the swap back — confirm with `moonlight list` AFTER restarting
the managed unit, not before.

Four things that are not obvious and all cost time:

- **Open the FIFO read-write (`3<>`), not read-only.** With only a reader,
  stdin hits EOF the moment the first writer closes and the PIN thread dies, so
  the prompt appears and nothing you write afterwards is ever read.
- **The temporary instance cannot capture the screen.** It logs
  `Couldn't find monitor [0]` even with the session environment copied, because
  a process started outside the graphical session cannot reach KMS. Harmless —
  pairing is pure HTTP — but it means `-0` is a pairing tool and not a way to
  run Sunshine generally. The managed unit reclaims capture on restart.
- **The device pairs with an EMPTY name**, because the name comes from the web
  UI's field and there is no field here. Fix it with the unit stopped, or
  Sunshine will overwrite the edit:

  ```bash
  cp -a ~/.config/sunshine/sunshine_state.json{,.bak}
  # set root.named_devices[].name on the blank entry, then start sunshine
  ```

- **Check for an active stream first.** Stopping Sunshine drops whatever is
  streaming: `ss -tn state established | grep -cE ':4798[0-9]|:48010'`.
  Pairings of other clients are untouched — they live in the same state file,
  which is why `--creds` and this both preserve them and deleting the file does
  not.

## Notes

- **Persistence:** pairings survive on both ends. They are lost only if a host
  is reinstalled (its Sunshine CA is regenerated) — the durable fix is to put
  the host's `~/.config/sunshine/credentials/{cacert,cakey}.pem` under sops so a
  reinstall restores the same identity. (Not done yet; follow-up.)
- **Why a tunnel, not a direct call:** `origin_web_ui_allowed = "pc"` binds the
  Sunshine web/API to localhost, so the request must originate on the host. The
  SSH tunnel makes it appear local.
- **Linux/NixOS clients:** `pair-sunshine.sh`, same flow, same API calls.

  ```bash
  ./pair-sunshine.sh hestia.netbird.cloud --name zagreus
  ```

  It prompts for the password hidden on **every** run rather than caching it:
  Linux has no DPAPI, and the obvious equivalent (an age-encrypted blob under
  the personal key) is not worth the moving parts for a once-per-pair
  operation. The password is handed to curl via `--config` on stdin, never
  `-u user:pass`, which would put it in the process table for every local user
  to read — the same reason it is not an argument or an environment variable.

  Verified end to end except the authenticated half, which cannot be tested
  without the password: the tunnel opens, the UI answers 401 through it, and a
  wrong password is reported with the reset command rather than a curl dump.

- **`Incorrect PIN` does not mean you mistyped.** Moonlight also reports it when
  no PIN ever reached the server — including when the web UI login was rejected,
  which is a failure on a completely different machine from the one showing the
  error. Check the host for `-- not authorized` before re-reading digits.

- **Which UI the PIN goes into:** the one on the machine being streamed FROM.
  `localhost:47990` is a valid URL on both machines and neither page names its
  host, so opening it inside a Moonlight window of another machine silently
  gives you the wrong one.
