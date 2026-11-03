# Bringing zagreus fully online

zagreus is the AMD HP laptop and the daily driver. It already boots this
config, so this is not an install (`docs/INSTALL.md` is) — it is the list of
things that are **not** declarative, plus what to verify afterwards.

Read `docs/REMOTE.md` for the reasoning behind any of it. This file is only the
order of operations.

> It doubles as the template for machine #3. Everything here that is not
> literally the word "zagreus" applies to any new host.

## What you do not have to do

Worth knowing up front, because most guides for this would have you doing it by
hand:

- **NetBird enrolment, but ONLY for a peer that does not exist yet.**
  `services.netbird.clients.default.login` has `enable = true` and a
  `setupKeyFile` pointing at `netbird-setup-key` in
  `secrets/common/netbird.yaml` — common, so every machine's host key decrypts
  it. The key is reusable, non-ephemeral and auto-joins `my-devices`, so the
  policies apply the moment it joins. **A reinstalled zagreus rejoins on first
  boot with nobody at the keyboard.** (`login.enable` is load-bearing:
  `setupKeyFile` alone generates no login unit at all.)

  **A setup key cannot rescue an EXISTING peer whose SSO session expired**, and
  that is not a nuance — it is a hard refusal from the management server:

  ```
  daemon up failed: login failed: rpc error: code = PermissionDenied
  desc = this peer was originally enrolled via SSO and its session has expired.
  Setup keys can only enrol new peers
  ```

  `netbird-login.service` then fails on every boot forever, and `netbird up` by
  hand fails identically. This cost an evening on 2026-11-03. The fix is to
  **delete the peer in the dashboard** so the key has a genuinely new peer to
  enrol; the unit then succeeds unattended on the next start. Note the unit is
  `netbird-login.service`, not `netbird-default-login.service` — the `default`
  client gets unsuffixed unit names.

  Deleting costs a new overlay IP (the FQDN survives, since it follows the peer
  name and a fresh peer takes its name from the hostname) and resets group
  membership to whatever the key assigns — here `my-devices` alone, down from
  `dev`/`my-devices`/`ops`. Verified harmless before doing it: the `Default`
  policy is all-to-all so groups do not gate connectivity, and `my-devices` is
  itself a distribution group for the only nameserver. Check both before
  deleting a peer that has more groups than the key will give back.
- **Its WireGuard port.** `51821`, already set in `hosts/zagreus/default.nix`.
  Not cosmetic — two peers sharing a port collide under the gateway's
  static-port NAT rule and one silently falls back to a relay.
- **SSH hardening, the firewall scoping, Sunshine, wayvnc, the no-suspend
  policy.** All from `hosts/common` and `modules/nixos/`. Nothing per-host.
- **The client half**, via `my.remote.clients.enable` — Moonlight and TigerVNC.
  Worth knowing this was missing until 2026-11-03: `my.remote` was all server,
  so both machines could be streamed FROM and neither could stream TO the other
  for want of a client binary, with the firewall and overlay ready the whole
  time. It is opt-in so a headless host need not carry two Qt GUIs. TigerVNC
  specifically — one of only two viewers that negotiate wayvnc's OpenH264
  extension, so the rest fall back to software Tight.
- **Secret decryption.** zagreus's host key is already a `.sops.yaml` recipient;
  there is no `secrets/zagreus/` because it still shares
  `secrets/common/passwords.yaml` (see the comment in its host file about why
  splitting the hash is a deliberate two-step, not something to inherit
  half-finished).

So the remaining work is: two keys that can only be generated on zagreus, one
gateway rule, Sunshine pairing, and verification.

## 1. Apply the current config

```bash
cd ~/nix-config && git pull --ff-only
sudo nixos-rebuild switch --flake .#zagreus
sudo systemctl reboot
```

**Reboot, don't just switch.** `capSysAdmin` is on for KMS capture, and after a
switch Sunshine can silently fail to gain `CAP_SYS_ADMIN` — the unit stays
`active`, the wrapper still carries the capability, and yet no encoder works,
which surfaces only as **Moonlight error 503**. A `systemctl --user restart`
does *not* clear it; a reboot does. See "Open problem" in `docs/REMOTE.md`.

## 2. Collect its two keys

These are the only values that cannot come from the repo, because they do not
exist until the machine does.

```bash
# ON zagreus
cat /etc/ssh/ssh_host_ed25519_key.pub   # -> my.remote.peers.zagreus.publicKey
cat ~/.ssh/id_ed25519.pub               # -> my.remote.authorizedKeys
netbird status | grep -E 'FQDN|NetBird IP'   # -> peers.zagreus.hostNames
```

Both go in `hosts/common/default.nix`, then rebuild **on the other machines**
so they take effect there:

- **`my.remote.peers.zagreus`** removes the trust-on-first-use prompt when you
  connect *to* zagreus and replaces it with a real guarantee. Until it is set,
  connecting prompts once — which is also exactly what a man-in-the-middle
  looks like.
- **`my.remote.authorizedKeys`** is what lets zagreus connect *out* to the
  others. It is currently missing, so **zagreus cannot SSH into hestia today.**
  Agent forwarding is off deliberately, so each machine needs its own key
  rather than borrowing one over the wire.

Add it to `allowed_signers` too, or commits made on zagreus stop verifying.

## 3. One gateway rule

Firewall → NAT → Outbound: duplicate an existing NetBird rule and set its
source port to `51821`.

> Do this once properly instead: replace the per-machine rules with a single
> rule pointing at a **port alias** (Firewall → Aliases, type `Port`, content
> `51820-51829`). The source-port field rejects a literal range but accepts an
> alias, after which a new machine needs no firewall change at all. The
> allocation table lives in `modules/nixos/netbird.nix`.

## 4. Sunshine: provision and pair

Per-host and not declarable. apollo being paired with hestia means nothing
here.

```bash
# wait for it to be ready first — ~1.6s under KMS, but check rather than assume
journalctl --user -u sunshine -b | grep -m1 "Configuration UI available"

# then, from the client
ssh -L 47990:localhost:47990 sebastianstupak@zagreus.netbird.cloud
```

Open <https://localhost:47990> on the client, accept the self-signed
certificate, set a username and password on first visit, and enter the PIN
Moonlight shows. The web UI is `origin_web_ui_allowed = "pc"`, so the same URL
over the overlay returns **403** — that is the setting working. (You will see
`Web UI: [100.94.x.y] -- denied` in the log when a peer tries; expected.)

Pair only the clients you actually want: a paired client can inject input,
which is a bigger grant than SSH.

**THE PIN GOES INTO THE WEB UI OF THE MACHINE BEING STREAMED FROM.** The client
generates it; the host accepts it. This sounds obvious and is the single
easiest thing to get backwards, because `localhost:47990` is a valid URL on
both machines and neither page says which host it belongs to. Two consequences:

- Opening `localhost:47990` inside a Moonlight window of another machine gives
  you THAT machine's UI, not the one you are sitting at.
- A forgotten web UI password blocks precisely the direction that host serves.
  hestia's was never recorded, so zagreus -> hestia could not be paired while
  hestia -> zagreus went through in one go.

  **It is not actually a blocker**, which is worth knowing before you reset
  anything: `sunshine -0` reads the PIN from stdin and skips the web UI and its
  password entirely. That is how zagreus -> hestia was eventually paired, with
  hestia's password still unknown. See "Pairing with no password at all" in
  `scripts/pair-sunshine.md`. Prefer it over `sunshine --creds` when you do not
  already have the password — resetting means inventing and storing one. And in
  either case never delete `sunshine_state.json`, which would unpair every
  client; `secrets/README.md` has why.

`Incorrect PIN` from Moonlight does NOT mean you mistyped. It is also what it
reports when no PIN ever reached the server — including when your web UI login
was rejected. Check the host's log for `-- not authorized` before re-reading
the digits.

Moonlight's CLI takes the PIN as an argument, which makes the whole flow
scriptable and removes the ~1 minute race, and it runs headless:

```bash
QT_QPA_PLATFORM=offscreen moonlight pair <host>.netbird.cloud --pin 1234
QT_QPA_PLATFORM=offscreen moonlight list <host>.netbird.cloud   # proves it
```

`list` returning apps (`Desktop`, `Low Res Desktop`, `Steam Big Picture`) is the
real confirmation — an entry in `root.named_devices` only shows it was written.
The GUI picks its own PIN and does not let you choose.

## 5. Record its secrets

`zagreus/login-password`, `zagreus/sunshine-web-ui`,
`zagreus/ssh-key-passphrase` — the per-host items in `secrets/README.md`. None
can be recovered from the repo.

## 6. Verify

In this order, because the first one fails silently and invalidates the rest.

```bash
# the capability — checked first, because a working stream can hide its absence
journalctl --user -u sunshine -b | grep -E "effective cap:21|Failed to gain"

# that KMS is really the backend, not a silent fallback, and which display
journalctl --user -u sunshine -b -o cat | grep -E \
  "config: 'capture'|Screencasting with|Mapped '.*' to kmsgrab|Found H.264|Found HEVC"
#   want: capture = kms / Screencasting with KMS / Mapped 'eDP-1' to kmsgrab monitor index 0

# overlay reachability and DNS-by-group
netbird status | grep -iE "nameserver|expire"   # want 1/1 Available
resolvectl query git.datadir.dev                # want an answer on link wt0

# ports open on the overlay interface ONLY.
# ANCHOR the ports. The obvious `dport (22|5900|...)` is unanchored, so `22`
# also matches 22000 (syncthing, deliberately not overlay-scoped) and reads as
# a leak. It also missed Sunshine's whole UDP family, because `4798[0-9]` spans
# 47980-47989 and the UDP ports are 47998+. Offsets: modules/nixos/remote.nix.
sudo iptables -S nixos-fw |
  grep -E 'dport (22|5900|47984|47989|47990|47998|47999|48000|48002|48010)( |$)'
# every line must end in  -i wt0

# the lid, post-switch
grep ^RUNTIME_PM_ON_AC /etc/tlp.conf            # auto
```

**On hardware encode, do not grep for VA-API here.** The natural check —
`vainfo | grep -c VAEntrypointEncSlice` and a `va_openDriver() returns 0` line
— was written against hestia's Intel iGPU. On zagreus Sunshine picks **Vulkan**:

```
Found H.264 encoder: h264_vulkan [vulkan]
Found HEVC encoder: hevc_vulkan [vulkan]
Vulkan encode using GPU: AMD Radeon Graphics (RADV RENOIR)
```

There is no `va_openDriver` line at all, so the VA-API check finds nothing and
looks like a failure while encoding is in fact hardware. `vainfo` does report
encode entrypoints (5 here) — VA-API is available and simply not chosen. The
line that actually proves hardware encode on this machine is
`Vulkan encode using GPU`.

Sunshine sets `RADV_PERFTEST=video_encode` itself to get that path, and Mesa
now warns the variable is deprecated in favour of `RADV_EXPERIMENTAL=video_enc`.
It is not in this config and not ours to set — but it is the first thing to
suspect if Vulkan encode silently stops working after a nixpkgs bump.

Then one real lid-closed stream from Moonlight, and:

```bash
journalctl --user -u sunshine -b | grep -c "drm fb for plane"   # want 0
```

## KMS on AMD — verified 2026-11-03, no longer an open question

This section used to warn that the whole KMS switch had only been validated on
hestia's **Intel** iGPU and that the first AMD stream should be treated as a
test. It has now been done, and it works. A real 35-second session from apollo:

```
CLIENT CONNECTED
[wayland] Resolution: 1920x1080
Color coding: SDR (Rec. 601) / Color depth: 8-bit / Color range: JPEG
Streaming bitrate is 14988000
Vulkan encode using GPU: AMD Radeon Graphics (RADV RENOIR)
Opus initialized: 48 kHz, 2 channels, 512 kbps (total), LOWDELAY
CLIENT DISCONNECTED
```

with `grep -c "drm fb for plane"` at **0** — the black-frame failure that the
`wlr` backend produced on Nvidia does not appear here.

Note the `[wayland]` tag on the resolution line is not evidence of a fallback;
it comes from Sunshine's Wayland interface discovery. The backend is confirmed
by `Screencasting with KMS`, which is why `capSysAdmin` is genuinely load
bearing rather than belt-and-braces: kmsgrab needs it.

- **`output_name = "eDP-1"`** via `my.remote.output` is **correct here**, not a
  lucky guess with one display: `Mapped 'eDP-1' to kmsgrab monitor index 0`.
  Still make it per-host if a third machine's panel is named differently.
- **The lid bind calls `brightnessctl` without naming a device**, and that part
  is **fine on AMD**: `brightnessctl info` with no argument resolves to
  `amdgpu_bl1` (note `bl1`, not `bl0`), and it is the only device of class
  `backlight` — the others are `leds`, a different class, so there is nothing
  to pick wrongly. On hestia the same call lands on `intel_backlight`.

  What remains untested is only whether the **lid switch event itself** fires:
  that needs someone to physically shut the lid, and `my.power.remoteAccess`
  means nothing else about a closed lid is observable. Check with
  `cat /sys/class/backlight/*/brightness` (want `0`), reopening to restore. If
  the backlight does not go out, suspect the `switch:on:Lid Switch` polarity
  rather than the device name — the generated config has
  `bindl=, switch:on:Lid Switch, exec, brightnessctl -s set 0` and a matching
  `switch:off` that restores with `-r`.

## One decision to make rather than inherit

`my.power.remoteAccess = true` lives in `hosts/common`, so **zagreus never
suspends on a closed lid either.** That is right for a machine that sits on a
desk being worked into; it is questionable for the laptop you actually carry,
because it will flatten itself in a bag. `my.power.lidBacklightOff` reclaims
the panel's share of that, not the machine being awake.

This section used to hold out hope that zagreus could settle the question
properly, because `my.power.hibernate.enable` asserts an encrypted root and
hestia's is plain `ext4`. **Checked 2026-11-03: zagreus is `ext4` too.**

```
nvme0n1p1 vfat /boot
nvme0n1p2 ext4 /
zram0     swap [SWAP]
```

So hibernation is unavailable here for the same reason, and for a second
independent one the assertion does not even cover: swap is zram only, so there
is no on-disk space to hibernate into. There is no third option to find — the
choice really is "awake and reachable" or "asleep and unreachable", and it has
to be made rather than inherited.

**So the trade-off was resolved sideways rather than chosen**, 2026-11-03:
`my.power.remoteAccessRequiresAC = true` in `hosts/common` keeps the machine
awake and reachable with the lid shut *while charging*, and hands the lid and
the idle timer back on battery. The stated usage is charger in, lid closed, so
mains is the normal state and reachability costs nothing — while unplugging now
means one thing only, that the machine is going in a bag and should sleep.
That reverses an argument `modules/nixos/power.nix` made deliberately; the
argument is still there, next to why it no longer applies.

And on remote wake, do not repeat what this file used to say — that neither
machine has Ethernet. **zagreus does**: onboard Realtek Gigabit `enp1s0`
(`r8169`), listed in `/proc/acpi/wakeup` as `NIC` and already armed for S5. The
old pessimism was hestia's situation (no onboard NIC, so a dock and its shaky
USB power across suspend) generalised to both. `my.power.wakeOnLan = [ "enp1s0" ]`
arms it, and apollo at `192.168.1.223` is the LAN peer that can send the packet
— it needs a cable in the socket, and TLP had to be stopped from disabling WoL
by default. Plugging the charger in wakes it too, with no configuration: the AC
adapter is already an armed wake source. docs/REMOTE.md → "Waking it again".
