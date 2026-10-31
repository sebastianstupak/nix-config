# Remote access

Reaching one of these machines from another — or from a Windows or macOS box.
Two separate things, and it is worth keeping them separate in your head:

- **A terminal.** SSH, plus `herdr` sessions that were already running. This is
  what you want for Claude Code, and it is the one that works over a phone
  tether.
- **A desktop.** Sunshine on the host, Moonlight on the client. Needed much
  less often than it feels like it will be.

The mechanism and the reasoning live in `modules/nixos/remote.nix`. This file is
the walkthrough.

## How it is reachable

Netbird (`modules/nixos/netbird.nix`). Every machine gets a stable
`100.64.0.0/10` address and an overlay FQDN no matter which NAT it is behind, so
there is no port forwarding, no dynamic DNS, and no third-party rendezvous
service.

**Every port is opened on `wt0` only.** `modules/nixos/core.nix` deliberately
leaves sshd unreachable, because these are laptops that join café and hotel
networks. Nothing here changes that: the physical NICs still see a closed port.

Find a machine's address with:

```bash
netbird status          # "NetBird IP" and "FQDN"
```

## The firewall trusts the whole overlay — Netbird's policy is the real control

**Read this before adding peers.** `my.remote` opens port 22 on `wt0`, and that
rule does not distinguish between peers: *every* machine on the Netbird network
can reach SSH and Sunshine's control ports. At the time of writing this network
had **seven** peers, not two.

That is a deliberate split of responsibilities, not an oversight. The firewall
answers "which interface", and Netbird answers "which peer" — because peers are
identified by enrolled identity, which is exactly what an access policy should
key on. The thing to **not** do is pin the firewall to peer IPs: Netbird hands
those out from its management plane and a re-enrolled peer gets a new one, so
the rule would silently either stop matching (locking you out) or keep matching
an address that now belongs to something else.

So set the policy in the NetBird dashboard: replace the default
all-peers-to-all-peers rule with one that allows only your own machines, and
narrow it to TCP 22 and Sunshine's ports rather than "all". Group your laptops
and write the policy against the group, so adding a third machine is one
membership change.

What stands between a hostile overlay peer and this machine if you skip that:
key-only SSH with one permitted user, no root login, no keyboard-interactive
fallback, and Sunshine refusing to stream to anything unpaired. That is a real
defence, not a trivial one — but it is one layer where there should be two.

## Terminal

```bash
ssh sebastianstupak@workstation-98-165.netbird.cloud
herdr                   # attach to whatever was left running
```

Keys only — passwords are refused system-wide. To connect from a new machine,
put its public key in `my.remote.authorizedKeys` (`hosts/common/default.nix`)
and rebuild; adding it to `~/.ssh/authorized_keys` by hand works until the next
reinstall and then silently does not.

To add a new machine as a *destination*, collect its host key so there is no
trust-on-first-use prompt:

```bash
# on the new machine
cat /etc/ssh/ssh_host_ed25519_key.pub
# then add it under my.remote.peers in hosts/common/default.nix
```

`zagreus` is not in `peers` yet — its host key has not been collected. Until it
is, connecting to it prompts once.

### Unlocking a locked screen

The machine locks itself after five minutes idle whether or not anybody is
coming back, so this is the normal case, not an edge case:

```bash
ssh sebastianstupak@<host> loginctl unlock-session
```

This works because `modules/home/hyprland.nix` sets hypridle's `unlock_cmd`.
Without it, `loginctl unlock-session` is accepted and does nothing — hypridle is
the thing subscribed to logind's unlock signal, and with no command configured
the event lands nowhere.

Unlocking this way also opens the GNOME keyring, via
`security.pam.services.hyprlock.enableGnomeKeyring`.

## Desktop

### Pairing (once per client)

The web UI is restricted to `origin_web_ui_allowed = "pc"`, so it is not exposed
on the overlay at all. Reach it through the SSH connection you already have:

```bash
ssh -L 47990:localhost:47990 sebastianstupak@<host>
```

Then open <https://localhost:47990> on the client, accept the self-signed
certificate, and set a username and password on first visit. In Moonlight, add
the host by its **overlay IP** (`100.94.98.165`, not the LAN address), and enter
the PIN Moonlight shows into the web UI's PIN page.

Pairing state lives in `~/.config/sunshine/`, not in the Nix-generated config,
so it survives rebuilds.

### Connecting

Moonlight, on the overlay IP. You get the real session: the actual workspaces,
the actual window layout, the same screen someone standing at the machine would
see. `my.remote.output` defaults to `eDP-1`, the laptop panel.

That is a deliberate departure from most Sunshine-on-Hyprland guides, which
create a virtual output and pin workspaces 1–10 to the physical display so the
remote gets a dedicated empty one. Here workspaces 1–9 *are* the orgs
(`modules/home/orgs.nix`), so an empty remote workspace is the opposite of
useful.

### When the panel is not capturable

Set `my.remote.headlessOutput = true` and rebuild. This creates a virtual output
named `remote` and streams that instead.

Two cases call for it:

- **The lid is closed.** That switches the physical output off, and Hyprland
  will not create clients with no monitor at all. Note this is a *second*,
  independent reason the lid must not suspend — see below.
- **You want a resolution other than the panel's.**

It is still the same session and the same compositor — an extra monitor, not a
second login. The output is created by a user unit ordered `before
sunshine.service`, and that ordering is load-bearing: Sunshine's `wlr` backend
reads `output_name` once at startup and caches it, so an output that shows up
later is ignored and it streams the first display it finds instead. The fixed
name matters for the same reason — Hyprland otherwise increments
`HEADLESS-2`, `HEADLESS-3`, … on every create.

## Staying reachable

`my.power.remoteAccess = true` (`modules/nixos/power.nix`) is what keeps the
machine answering while nobody is at it. It stops the two things that suspend it
unattended: the lid, and hypridle's ten-minute idle timer.

This is not optional for remote access. **A suspended machine cannot be woken.**
Suspending drops the WireGuard tunnel, and Wake-on-LAN does not traverse an
overlay network, so there is nothing left listening. Whatever was running is
gone until somebody physically touches the laptop.

The five-minute *lock* is deliberately untouched — walking away still secures
the screen. The machine just stays awake behind it.

**Verify it actually took effect**, because the file saying so is not enough:

```bash
busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
  org.freedesktop.login1.Manager HandleLidSwitch      # want: s "ignore"
```

nixpkgs ships systemd-logind with `restartIfChanged = false` (restarting it
would tear down the session) and leaves `reloadIfChanged` at the global default
of false — so a switch used to write the new `logind.conf` while the running
daemon kept the old values until the next reboot. `modules/nixos/power.nix` now
sets `reloadIfChanged = true`; logind advertises `CanReload=yes` and re-reads
its config in place without dropping sessions. If `busctl` disagrees with
`/etc/systemd/logind.conf`, run `sudo systemctl reload systemd-logind`.

**The cost:** a laptop that will flatten its battery if left closed in a bag.
That is exactly the failure hibernation exists to fix (`docs/POWER.md`), and
turning this on gives it up. Leave it off on a machine you only carry.

## Things that went wrong, or nearly did

- **The overlay is not implicitly trusted by the firewall.** With
  `networking.firewall.allowedTCPPorts` empty, port 22 is blocked on *every*
  interface including `wt0`, sshd listening or not. The per-interface rules are
  mandatory, not belt-and-braces. This is the single most common way this setup
  appears broken.
- **`hardware.graphics.enable` does not give you VA-API on Intel**, and this is
  the one thing that actually was broken. Mesa ships Gallium's VA-API drivers,
  so the AMD machine had working hardware video all along; Intel's lives in a
  separate package nothing was pulling in, so `iHD_drv_video.so` was simply
  absent and libva failed with "unknown libva error". Sunshine then failed
  *every* encoder — nvenc, vulkan, vaapi — which leaves nothing but a software
  encoder, i.e. the one thing it exists to avoid. Fixed by
  `hardware.graphics.extraPackages = [ pkgs.intel-media-driver ]` in
  `modules/nixos/desktop.nix`. Check with `vainfo`: you want
  `VAEntrypointEncSlice` lines, not just `VAEntrypointVLD`.
- **`capSysAdmin` is deliberately off.** It is for DRM/KMS capture, and we use
  `capture = "wlr"` — the native wlroots path, and the only backend that can see
  a virtual output. The capability applies to the whole binary and breaks
  launching applications as the ordinary user, so there is no reason to pay for
  it. **If capture fails outright**, the fallback is `capture = "kms"` plus
  `capSysAdmin = true`.

### Log noise that is expected, not broken

Sunshine probes every encoder at startup and says so itself — "Ignore any errors
mentioned above, they are not relevant." Specifically:

- **`Failed to create a CUDA device` / `Cannot load libcuda.so.1`** — the nvenc
  probe. Neither machine has an Nvidia GPU. The probe is left in place rather
  than pinning `encoder = "vaapi"`, because auto-detection is self-healing if
  the hardware ever changes and the cost is about two seconds of benign log at
  session start.
- **`No usable encoding entrypoint found for profile VAProfileAV1Profile0`** —
  Raptor Lake decodes AV1 but does not encode it. Sunshine falls back to
  `hevc_vaapi`, which is what you want anyway.
- **`EGL: context priority set to HIGH but CAP_SYS_NICE capability is
  missing`** — Sunshine asks for a high-priority GL context and does not get
  one. Capture works regardless; it may matter for smoothness under heavy load.
  Not granted because the capability cannot be given to a *user* systemd unit
  via `AmbientCapabilities`, and the alternative is overriding the module's
  `ExecStart` to point at a hand-rolled wrapper. Revisit if the stream stutters
  while the CPU is busy.
- **Startup takes around a minute.** Each VA-API codec probe costs ~14s. It is
  a one-time cost in a background user service at session start, so nothing
  waits on it — but it does mean Sunshine is not connectable the instant you
  log in.
- **`avahi::entry_group_new() failed: Not permitted`** is Sunshine noticing it
  may not advertise itself over mDNS, and carrying on. That is the intended
  state — see the mDNS note above.
- **Black frames are an Nvidia problem**, not a Hyprland one: the `wlr` backend
  cannot read Nvidia's tiled framebuffer layout. Neither machine here has one.
- **Sunshine's user unit needs `graphical-session.target` to actually be
  reached.** The usual complaint on Wayland window managers is that it never
  starts because nothing starts that target. `programs.hyprland.withUWSM`
  (`modules/nixos/desktop.nix`) is why that does not apply here — if Sunshine
  ever silently fails to start, check that first.
- **mDNS publishing is off on purpose.** The Sunshine module would turn it on,
  advertising this host's name and the fact that it runs a remote-desktop
  server on every network it joins. Nothing here uses discovery — pairing goes
  through an SSH tunnel to localhost and Moonlight connects by overlay IP — so
  it was pure cost. Printing is unaffected: that needs avahi *browsing*, which
  stays on; only *publishing* is disabled.
- **`nixpkgs`' Sunshine module is a moving target** —
  [#433058](https://github.com/NixOS/nixpkgs/issues/433058) tracks module and
  settings limitations, and [#475181](https://github.com/NixOS/nixpkgs/issues/475181)
  was a release-to-release breakage. Worth checking before blaming this config.

## Not used, and why

- **RustDesk** is structurally blocked here, not merely immature: it needs
  portal protocols `xdg-desktop-portal-hyprland` does not implement.
- **xrdp** is X11-only.
- **wayvnc** works and is genuinely useful for *looking* at a session that has
  gone wrong, but it is software-encoded and not pleasant for real use.
- **Netbird's own SSH server** (`netbird up --allow-server-ssh`, native OpenSSH
  integration since 0.60) would remove key management entirely — identity-aware
  auth through the IdP, mapped to local users. Genuinely attractive for three
  machines. Not used because it moves authorization from this repo's
  `authorized_keys` to the management plane, which is a different trust model
  from the one `core.nix` argues for. Reconsider if client key distribution
  across three operating systems becomes the annoying part.
