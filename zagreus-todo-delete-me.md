# zagreus — catch-up checklist

Temporary. **Delete this file once the last box is ticked** — the durable
versions live in `docs/REMOTE.md`, `secrets/README.md` and the hades repo's
`docs/REMOTE-ACCESS.md`.

zagreus has been offline since ~2026-10-05 and has missed everything below.
Most of it is one rebuild; the rest is collecting two keys and one password.

> **It is running NetBird 0.71.4, which has three HIGH advisories** —
> local privilege escalation via an unauthenticated IPC socket, SSH-config
> injection via a peer's hostname, and vulnerable `x/crypto/ssh` paths. Step 2
> is the one that matters; the rest can wait.

---

## 1. Restore your age key (do this first — nothing else needs it, but `sops` does)

The key is **yours, not the machine's** — the same note you saved from hestia.
zagreus decrypts its own secrets with its host key at activation, so the
machine is fine without this; you need it to *edit* secrets here.

```bash
mkdir -p ~/.config/sops/age
wl-paste > ~/.config/sops/age/keys.txt     # paste the nixcfg/age-key note
chmod 600 ~/.config/sops/age/keys.txt
```

Prove it before relying on it:

```bash
cd ~/nix-config
sops -d secrets/common/backup.yaml >/dev/null && echo "age key works"
```

- [ ] age key restored and verified

## 2. Pull and switch

```bash
cd ~/nix-config
git pull
sudo nixos-rebuild switch --flake .#zagreus
```

This delivers, all already verified building for this host:

| | |
| --- | --- |
| netbird | **0.82.0** (was 0.71.4 — the three HIGH advisories) |
| WireGuard port | **51821** (hestia keeps 51820; the gateway NAT rule is already live) |
| setup key | `/run/secrets/netbird-setup-key` — ends the daily `netbird up` |
| sunshine | **2026.914.233613** (patched; `capSysAdmin` stays off) |
| wayvnc | enabled, PAM auth, TLS |
| lid / idle | `ignore` — stays reachable when closed |
| sshd | keys-only, one user, no root, no agent forwarding, `wt0` only |

- [ ] switched without errors

## 3. NetBird — expect one last interactive login

That peer was *already expired* when login-expiration was disabled for it, so
it will probably need one final browser round-trip to clear the state. After
this it should never ask again.

```bash
netbird status          # if it says NeedsLogin:
netbird up
```

Then verify:

```bash
netbird version                      # 0.82.0
netbird status | grep -E "Management|Signal|FQDN|Wireguard port"
#   Management: Connected / Signal: Connected
#   FQDN: zagreus.netbird.cloud      <- renamed already, not workstation-*
#   Wireguard port: 51821
```

**Confirm it is not relaying.** Lazy connections mean a peer shows as
disconnected until traffic flows, so generate some first:

```bash
curl -ks -o /dev/null -w '%{http_code}\n' https://git.datadir.dev   # expect 200
netbird status --detail | grep -E "Connection type|ICE candidate"
#   want: P2P with real ICE candidates, NOT "Relayed" with -/-
```

If it says `Relayed`, the gateway NAT rule for **51821** is missing or wrong —
see `docs/REMOTE.md` → "Adding a machine".

- [ ] 0.82.0, connected, port 51821, **P2P**

## 4. Hand me its host key

So that connecting *to* zagreus stops prompting to trust it:

```bash
cat /etc/ssh/ssh_host_ed25519_key.pub
```

Paste that back and the commented `zagreus` block in
`hosts/common/default.nix` → `my.remote.peers` gets filled in (its addresses
`zagreus.netbird.cloud` / `100.94.242.62` are already there).

- [ ] host key collected and added to `my.remote.peers`

## 5. Sunshine — first-run setup

Sunshine ships configured but **unprovisioned**: it has no admin credentials
until you visit it once.

**a. Make sure it is running.** Both Sunshine and wayvnc are
`wantedBy=graphical-session.target`, and systemd does *not* retroactively pull
newly-added units into an already-running target — so right after a switch
they are often inactive. Either log out and back in, or:

```bash
systemctl --user start sunshine wayvnc
systemctl --user is-active sunshine wayvnc     # both: active
```

**b. Wait about a minute.** Sunshine probes every encoder at startup (~54s).
Do not try to pair during this window — Moonlight's pair request times out
after ~56s and will fail with no useful error, while the web UI cheerfully
answers the PIN with `{"status":true}` because it runs on a different thread.

```bash
journalctl --user -u sunshine -f | grep -m1 "Configuration UI available"
```

**c. Set admin credentials.** Open <https://localhost:47990>, accept the
self-signed certificate, and set a username and password at the welcome
screen. It is localhost-only by design (`origin_web_ui_allowed = pc`), so from
the overlay it returns **403** — that is correct, not a fault.

Store as `zagreus/sunshine-web-ui`, or skip it: deleting
`~/.config/sunshine/sunshine_state.json` and revisiting the page regenerates it.

**d. Check hardware encoding actually works.** The Intel VA-API trap does not
apply to zagreus (it is AMD, and Mesa ships `radeonsi_drv_video.so`), but
confirm rather than assume:

```bash
vainfo | grep -c VAEntrypointEncSlice      # want a non-zero count
journalctl --user -u sunshine | grep -E "va_openDriver|Selected monitor"
#   want: va_openDriver() returns 0   and   Selected monitor [...]
```

Ignore the `CUDA`/`nvenc` errors — there is no Nvidia GPU and Sunshine says so
itself: "Ignore any errors mentioned above, they are not relevant."

**e. Pair a client.** The web UI is not exposed on the overlay, so pair over
the SSH connection you already have — from the *client* machine:

```bash
ssh -L 47990:localhost:47990 sebastianstupak@zagreus.netbird.cloud
# then, locally: open https://localhost:47990
# in Moonlight: add host  zagreus.netbird.cloud
# type the PIN Moonlight shows into the web UI's PIN page
```

Pair only the machines you actually want driving this desktop — a paired
client can inject input, which is a bigger grant than SSH.

- [ ] sunshine active, credentials set, hardware encode confirmed
- [ ] at least one client paired

## 6. VNC — nothing to configure

wayvnc is already set up with PAM auth, so the credential is **your normal
login** — there is no separate VNC password. From another machine:

```bash
vncviewer zagreus.netbird.cloud:5900
```

Use **TigerVNC** specifically if you want the hardware-accelerated path: it is
one of only two clients that negotiate wayvnc's OpenH264 extension. Others
fall back to Tight, which works but is software-encoded.

- [ ] VNC connects and authenticates

## 7. Prove remote access end to end, from hestia

```bash
ssh sebastianstupak@zagreus.netbird.cloud 'hostname; herdr session list | wc -l'
ssh sebastianstupak@zagreus.netbird.cloud loginctl unlock-session   # unlock remotely
```

- [ ] SSH works by name, remote unlock works

## 8. Record what cannot be recovered

Only the Sunshine password is new (step 5c), and only if you chose to keep it.
Everything else — restic, the NetBird setup key, calendar URLs — is inside
sops and already covered by the one age key.

The login password is shared with hestia today. It becomes per-host only if
you follow "Splitting a host's password" in `secrets/README.md`.

- [ ] nothing left unrecorded

---

## Then

```bash
git rm zagreus-todo-delete-me.md && git commit -m "chore: zagreus caught up"
```
