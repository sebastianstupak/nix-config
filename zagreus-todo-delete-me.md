# zagreus — catch-up checklist

Temporary. **Delete this file once the last box is ticked** — the durable
versions live in `docs/ZAGREUS.md` (the non-declarative half of bringing a host
online), `docs/REMOTE.md`, `secrets/README.md` and the hades repo's
`docs/remote-access/`.

> **Updated 2026-11-02** after a session that changed Sunshine's capture
> backend and found several things this file used to state wrongly. The
> corrected items are flagged inline; the short version is that `capSysAdmin`
> is now ON, startup is ~1.6s rather than ~54s, you must REBOOT rather than
> switch, and the KMS path is unverified on AMD.

zagreus has been offline since ~2026-10-05 and has missed everything below.
Most of it is one rebuild; the rest is collecting two keys and one password.

> **Status after the 2026-11-03 session: 9 of 13 boxes done.** The machine is
> online, enrolled, streaming with hardware encode, and reachable by name, and
> `sops` works here again. Nothing left is blocking; all four need a human
> rather than a keyboard.
>
> The age key is worth one note, because step 1 below describes the wrong
> recovery path for what was actually wrong. The file already present on
> zagreus was a THIRD key (`age16x0az…`) that was never a recipient of
> anything, while `.sops.yaml` wants `age1nmnth…`. **hestia had the correct
> key all along**, so it was copied machine-to-machine rather than pasted from
> Proton Pass; the stale one is at `~/age-key-stale-backup.txt`. Prefer that
> route when a machine's key has drifted — it needs no password manager and
> the public half can be compared first.
>
> 1. **zagreus -> hestia pairing** — blocked, and not on anything in this repo:
>    hestia's Sunshine web UI password was never recorded, and that is the UI
>    the PIN must go into. `sunshine --creds` on hestia, then restart it, then
>    record it. hestia -> zagreus and apollo -> zagreus are both done.
> 2. **lid test** (step 5) — needs a human to shut the lid; the panel here is
>    `amdgpu_bl1`.
> 3. **VNC** (step 6) — port 5900 listens and accepts, but nobody has completed
>    a PAM-authenticated session.
> 4. **`remoteAccess`** (step 9) — the facts are in, the decision is not. Root
>    is ext4 with zram-only swap, so hibernation is not available as a way out.

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

- [x] age key restored and verified

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
| sunshine | **2026.914.233613**, `capture = "kms"`, **`capSysAdmin` now ON** |
| wayvnc | enabled, PAM auth, TLS |
| lid / idle | `ignore` — stays reachable when closed, **backlight blanks** |
| TLP | `RUNTIME_PM_ON_AC = "auto"` — idle PCIe devices may now suspend |
| hyprlock | shows the active keyboard layout (`us`/`sk`) |
| sshd | keys-only, one user, no root, no agent forwarding, `wt0` only |

**REBOOT AFTER THE SWITCH, do not just switch.** `capSysAdmin` is on for KMS
capture, and after a `nixos-rebuild switch` Sunshine can silently fail to gain
`CAP_SYS_ADMIN`: the unit stays `active`, `/run/wrappers/bin/sunshine` still
carries the capability, and yet no encoder works. The only symptom is
**Moonlight error 503**. `systemctl --user restart sunshine` does *not* clear
it; a reboot does. See "Open problem" under `capSysAdmin` in `docs/REMOTE.md`.

```bash
sudo systemctl reboot
journalctl --user -u sunshine -b | grep -E "effective cap:21|Failed to gain"
#   want: effective cap:21
```

- [x] switched without errors
- [x] rebooted, and `effective cap:21` present

## 3. NetBird — convert it to key enrolment

zagreus's peer is still SSO-enrolled and already sitting *expired*, so rather
than one more browser round-trip, delete it and let it come back on the setup
key. This was done on hestia on 2026-11-01 and works cleanly.

```bash
netbird down
# delete the `zagreus` peer in the NetBird dashboard (Peers -> ... -> Delete)
netbird up        # the daemon finds the setup key itself via setupKeyFile
```

Two things change, neither harmful here:

- **A new overlay IP.** The FQDN `zagreus.netbird.cloud` survives, because it
  follows the peer name, which comes from the hostname. Only `100.94.242.62`
  in `hosts/common/default.nix` needs updating afterwards.
- **Group membership resets** to whatever the key auto-assigns — `my-devices`.
  That is already a distribution group for the `datadir dev` nameserver, so
  DNS will work. Confirm anyway, because when this bit hestia it looked
  exactly like a DNS outage:

```bash
netbird status | grep -i nameserver     # want 1/1 Available, not 0/0
```

If you would rather not, plain `netbird up` also works — it stays SSO but no
longer expires.

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

If it says `Relayed`, **the gateway is not the first thing to suspect** — the
`51821` static-port rule was confirmed present on OPNsense on 2026-11-02 (WAN /
`LAN net` / `udp 51821` / static-port YES, Hybrid mode). Far more likely is
stale ICE state, which idle peers can sit on indefinitely. Recovery needs no
root:

```bash
netbird down && netbird up
netbird status -d | grep -E "netbird.cloud:|Connection type|Latency"
```

Note the unit is **`netbird.service`**, not `netbird-default.service` — see
"Docking drops peers onto a relay" in `docs/REMOTE.md` for why, and for the
other three things that look like causes and are not.

- [x] 0.82.0, connected, port 51821, **P2P**

## 4. Hand me its host key

So that connecting *to* zagreus stops prompting to trust it:

```bash
cat /etc/ssh/ssh_host_ed25519_key.pub
```

Paste that back and the commented `zagreus` block in
`hosts/common/default.nix` → `my.remote.peers` gets filled in (its addresses
`zagreus.netbird.cloud` / `100.94.242.62` are already there).

- [x] host key collected and added to `my.remote.peers`

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

**b. Wait for it to be ready — now ~1.6s, not ~54s.** The old warning here
said to wait a minute because the encoder probe raced Moonlight's ~56s pair
timeout. That was the `wlr` capture backend, where each VA-API probe
round-tripped a screencopy frame. Under `kms` the whole probe is about 1.6
seconds and the race is gone. Still wait for the line rather than a clock:

```bash
journalctl --user -u sunshine -f | grep -m1 "Configuration UI available"
```

If startup takes a minute again, something put the capture backend back to
`wlr`.

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

**f. Verify the KMS capture path, which is UNTESTED ON AMD.** Everything about
the switch from `wlr` to `kms` was validated on hestia's Intel iGPU. Expect it
to work here — AMD gets VA-API from Mesa's `radeonsi`, and the black-frame
reports against `wlr` are an Nvidia framebuffer-tiling problem — but treat the
first stream as a test:

```bash
journalctl --user -u sunshine -b -o cat | grep -E \
  "Start of KMS monitor list|Monitor 0 is|Found monitor for DRM|Found H.264|Found HEVC"
```

Two specifics that may differ from hestia:

- **`output_name` is hardcoded to `eDP-1`** (`my.remote.output`). Check what
  `Monitor 0 is …` actually reports. With one display Sunshine has nothing to
  choose between so it works regardless, but the setting would be a lie —
  report it and it becomes per-host.
- **The lid bind calls `brightnessctl` without naming a device.** On hestia
  that resolves to `intel_backlight`; here it will be `amdgpu_bl*`. Confirm:
  close the lid, then `cat /sys/class/backlight/*/brightness` (want `0`),
  reopen to restore. If it never fires, suspect the `switch:on:Lid Switch`
  polarity.

Then one real **lid-closed** stream — confirmed working on hestia, so it should
work here:

```bash
journalctl --user -u sunshine -b | grep -c "drm fb for plane"   # want 0
```

- [x] sunshine active, credentials set, hardware encode confirmed
- [x] KMS monitor list shows the right display; `drm fb for plane` is 0
- [ ] lid closed: backlight 0, stream still good
- [x] at least one client paired

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

- [x] SSH works by name, remote unlock works

## 8. Record what cannot be recovered

Only the Sunshine password is new (step 5c), and only if you chose to keep it.
Everything else — restic, the NetBird setup key, calendar URLs — is inside
sops and already covered by the one age key.

The login password is shared with hestia today. It becomes per-host only if
you follow "Splitting a host's password" in `secrets/README.md`.

- [ ] nothing left unrecorded

## 9. One decision to make rather than inherit

`my.power.remoteAccess = true` lives in `hosts/common`, so **zagreus never
suspends on a closed lid either.** Right for a machine worked *into* from
elsewhere; questionable for the laptop that actually gets carried, because it
will flatten itself in a bag. `my.power.lidBacklightOff` reclaims the panel's
share of that, not the machine being awake.

There is **no remote wake** to fall back on — Wake-on-LAN is Layer 2 and the
overlay is Layer 3, and while apollo is on the LAN and could relay a magic
packet, neither laptop has usable onboard Ethernet. So the choice really is
"awake and reachable" or "asleep and unreachable until touched".

Unless zagreus has an encrypted root, which hestia does not:

```bash
lsblk -o NAME,FSTYPE,MOUNTPOINT
```

If root is LUKS, `my.power.hibernate.enable` passes its assertion and
`suspend-then-hibernate` becomes available — an actual answer rather than a
trade-off. Report what it says and `remoteAccess` becomes per-host.

- [ ] reported whether root is encrypted; remoteAccess decided deliberately

---

## Then

```bash
git rm zagreus-todo-delete-me.md && git commit -m "chore: zagreus caught up"
```
