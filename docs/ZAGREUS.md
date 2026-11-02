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

- **NetBird enrolment.** `services.netbird.clients.default.login` has
  `enable = true` and a `setupKeyFile` pointing at `netbird-setup-key` in
  `secrets/common/netbird.yaml` — common, so every machine's host key decrypts
  it. The key is reusable, non-ephemeral and auto-joins `my-devices`, so the
  policies apply the moment it joins. **A reinstalled zagreus rejoins on first
  boot with nobody at the keyboard.** (`login.enable` is load-bearing:
  `setupKeyFile` alone generates no login unit at all.)
- **Its WireGuard port.** `51821`, already set in `hosts/zagreus/default.nix`.
  Not cosmetic — two peers sharing a port collide under the gateway's
  static-port NAT rule and one silently falls back to a relay.
- **SSH hardening, the firewall scoping, Sunshine, wayvnc, the no-suspend
  policy.** All from `hosts/common` and `modules/nixos/`. Nothing per-host.
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
over the overlay returns **403** — that is the setting working.

Pair only the clients you actually want: a paired client can inject input,
which is a bigger grant than SSH.

## 5. Record its secrets

`zagreus/login-password`, `zagreus/sunshine-web-ui`,
`zagreus/ssh-key-passphrase` — the per-host items in `secrets/README.md`. None
can be recovered from the repo.

## 6. Verify

In this order, because the first one fails silently and invalidates the rest.

```bash
# the capability — checked first, because a working stream can hide its absence
journalctl --user -u sunshine -b | grep -E "effective cap:21|Failed to gain"

# which display KMS picked, and whether encoding is hardware
journalctl --user -u sunshine -b -o cat | grep -E \
  "Start of KMS monitor list|Monitor 0 is|Found monitor for DRM|Found H.264|Found HEVC"
vainfo | grep -c VAEntrypointEncSlice      # want non-zero

# overlay reachability and DNS-by-group
netbird status | grep -iE "nameserver|expire"   # want 1/1 Available
resolvectl query git.datadir.dev                # want an answer on link wt0

# ports open on the overlay interface ONLY
sudo iptables -S nixos-fw | grep -E 'dport (22|5900|4798[0-9]|47990)'
# every line must end in  -i wt0

# the lid, post-switch
grep ^RUNTIME_PM_ON_AC /etc/tlp.conf            # auto
```

Then one real lid-closed stream from Moonlight, and:

```bash
journalctl --user -u sunshine -b | grep -c "drm fb for plane"   # want 0
```

## What is genuinely unverified on this machine

Everything about the KMS switch was validated on hestia's **Intel** iGPU. On
AMD, expect it to work — AMD gets VA-API from Mesa's `radeonsi` and the
black-frame reports against the `wlr` backend are an Nvidia framebuffer-tiling
problem — but treat the first stream as a test, not a formality.

Two specific things that may differ:

- **`output_name` is hardcoded to `eDP-1`** via `my.remote.output`. Check what
  `Monitor 0 is …` actually says. With one display Sunshine has nothing to
  choose between so it works regardless, but the setting would be a lie. Make
  the default per-host if it differs.
- **The lid bind calls `brightnessctl` without naming a device.** On hestia that
  resolves to `intel_backlight`; here it will be `amdgpu_bl*`. It should pick
  the panel automatically — confirm by closing the lid and reading
  `cat /sys/class/backlight/*/brightness` (want `0`), reopening to restore. If
  it never fires, suspect the `switch:on:Lid Switch` polarity.

## One decision to make rather than inherit

`my.power.remoteAccess = true` lives in `hosts/common`, so **zagreus never
suspends on a closed lid either.** That is right for a machine that sits on a
desk being worked into; it is questionable for the laptop you actually carry,
because it will flatten itself in a bag. `my.power.lidBacklightOff` reclaims
the panel's share of that, not the machine being awake.

And unlike hestia, zagreus may be able to do this properly. Hibernation is
blocked on hestia only because its root is plain `ext4`;
`my.power.hibernate.enable` asserts an encrypted root. Check:

```bash
lsblk -o NAME,FSTYPE,MOUNTPOINT
```

If zagreus's root is LUKS, `suspend-then-hibernate` is available there — which
is an actual answer rather than a trade-off, since there is **no remote wake**
on either machine (Wake-on-LAN is Layer 2, the overlay is Layer 3, no mesh peer
shares their LAN, and neither has Ethernet). If so, make `remoteAccess`
per-host instead of shared.
