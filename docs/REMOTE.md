# Remote access

Reaching one of these machines from another — or from a Windows or macOS box.
Two separate things, and it is worth keeping them separate in your head:

- **A terminal.** SSH, plus `herdr` sessions that were already running. This is
  what you want for Claude Code, and it is the one that works over a phone
  tether.
- **A desktop.** Two protocols, deliberately — Sunshine where it is good,
  VNC where it is the only thing that works. See "Desktop across three
  operating systems" below for why that is not redundancy.

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

### Peer names are not hostnames

The overlay FQDN is `<peer name>.netbird.cloud`, and the peer name is whatever
the machine was called **when it enrolled** — NetBird never updates it when the
hostname changes. Both NixOS machines enrolled while they still shared the name
`workstation`, so NetBird disambiguated them by appending part of the overlay
IP, giving the memorable `workstation-98-165.netbird.cloud`. Renamed in the
dashboard to `hestia` / `zagreus`; the FQDN follows immediately. Rename there,
not in this repo.

### Re-enrolling a peer drops it from its groups — and DNS rides on groups

Deleting a peer and letting it re-enrol gives it a **new overlay IP** and only
the groups its setup key auto-assigns. The FQDN survives, because that follows
the peer *name*, which comes from the hostname.

The part that bites: **NetBird distributes DNS nameservers by group, not to
everyone.** The `datadir dev` nameserver — the one that resolves
`git.datadir.dev` and friends — is distributed to `dev` and `ops`. A
re-enrolled peer landing only in `my-devices` therefore came up with
`Nameservers: 0/0 Available` and could not resolve a single `datadir.dev`
name, while SSH by overlay address kept working perfectly. It reads like a
DNS outage rather than a group-membership change.

Fixed by adding `my-devices` to that nameserver's distribution groups. Check
after any re-enrolment:

```bash
netbird status | grep -i nameserver     # want 1/1 Available, not 0/0
resolvectl query git.datadir.dev        # want an answer on link wt0
```

Worth knowing too: `dev` and `ops` look vestigial because no *policy*
references them — but they are what the DNS distribution keys on. Do not
delete them on the strength of the policy list alone.

### Why you kept having to run `netbird up`

Because the personal machines were enrolled **interactively via SSO**, and the
account has `peer_login_expiration_enabled` with a 24-hour window — so every
day the login expires and the peer demands a browser round-trip. The servers
never did this because they were enrolled with **setup keys**, which are exempt.

Fixed per-peer (`login_expiration_enabled: false`) on `my-devices` rather than
account-wide, deliberately: the account-wide default should stay ON so that a
collaborator's device still expires. Check with:

```bash
netbird status | grep -i expire   # or the Peers table in the dashboard
```

The durable alternative, if you ever want hands-off enrolment of a new machine,
is `services.netbird.clients.default.login.setupKeyFile` pointing at a sops
secret — that is how the servers were done.

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
narrow it to the ports below rather than "all". Group your machines and write
the policy against the group, so adding a fourth is one membership change.

Policies are **port-scoped and one-way**, which is what makes mesh membership a
small grant rather than a large one. Access controls, groups, networks and
routes are all in NetBird's **free tier** (5 users / 100 machines); only device
approval and posture checks are paid.

What is deployed today — groups `my-devices` (both laptops, the Windows box,
the phone) and `infra` (forge, grafana, maethril-app, soul-siet):

| policy | source → destination | protocol / ports |
| --- | --- | --- |
| my-devices: remote access | `my-devices ↔ my-devices` | TCP 22, 3389, 5900, 47984, 47989, 47990, 48010 · UDP 47998-48002, 48010 · ICMP |
| my-devices to infra | `my-devices → infra`, **one-way** | ALL |
| infra internal | `infra ↔ infra` | ALL |
| ~~Default~~ | ~~All ↔ All~~ | **disabled** |

**There is deliberately no policy granting `infra → my-devices`,** and none
granting collaborators anything yet. That absence is the access split: these
machines are not merely firewalled from the rest of the overlay, they are
unreachable — and NetBird enforces it *in the data path*, by programming
nftables on each host, not as a dashboard preference. The proof when this was
switched over: ICMP to forge went from 100% packet loss to 0% the moment the
rule naming it was added.

`infra internal` is the loose one. It exists only so that retiring the old
all-to-all `Default` could not break server-to-server traffic (Woodpecker
deploys) that rule had been carrying invisibly. Tighten it once those flows
are enumerated.

**Never disable NetBird's client firewall management.** With it off, no policy
is applied at all and any peer on the tunnel is unfiltered.

### What this does NOT protect

Worth writing down, because it is the gap that survives everything above:
**none of the desktop protocols have a strong credential story.** Sunshine
pairing is a certificate on disk, VNC is the login password, RDP is a Windows
password, Screen Sharing is a macOS password. A compromised machine that is
paired with another can read its screen and inject input.

So keep the set of machines paired for *desktop* access deliberately smaller
than the set that can SSH. Desktop control is the more powerful grant and it has
the weaker credential.

What stands between a hostile overlay peer and this machine if you skip that:
key-only SSH with one permitted user, no root login, no keyboard-interactive
fallback, and Sunshine refusing to stream to anything unpaired. That is a real
defence, not a trivial one — but it is one layer where there should be two.

## Terminal

```bash
ssh sebastianstupak@hestia.netbird.cloud
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

## Desktop across three operating systems

The fleet has NixOS, Windows and macOS machines, and **every one of them is both
a client and a target**. No single remote-desktop protocol has a good host on
all three, so there are two. This section is the decision record — the reasoning
is more useful than the conclusion, because the conclusion will change when the
tooling does.

### The matrix

| protocol | Hyprland host | Windows host | macOS host |
| --- | --- | --- | --- |
| **Sunshine / Moonlight** | ✅ excellent | ✅ its best platform | ⚠️ Experimental |
| **VNC** | ✅ wayvnc (wlroots-native) | ✅ UltraVNC / TightVNC | ✅ **built in** |
| **RDP** | ⚠️ nothing mature | ✅ native | ❌ no server exists |

So: **Sunshine for NixOS and Windows, VNC for the Mac**, with VNC also serving
as the universal fallback when Sunshine will not come up.

### Why not one protocol

**Hyprland is the constraint, not the tooling.** It implements the `wlr-*`
protocols but not the full `xdg-desktop-portal` surface that general-purpose
remote desktop software expects. What works on it is wlroots-native: Sunshine's
`wlr` capture backend, and wayvnc.

Checked and rejected:

- **RustDesk** — the obvious "one tool everywhere" candidate, and structurally
  blocked here: it needs portal protocols `xdg-desktop-portal-hyprland` does
  not implement. There is a PR, described upstream as mostly dead.
- **NoMachine 10** — EU company, excellent performance, would have been ideal.
  Officially KDE/GNOME only; users report **blank screens on Hyprland, Sway and
  Niri**. Also discontinued its free edition in v10.
- **Sunshine on macOS** — marked *Experimental* upstream. It is not hopeless:
  hardware encode works via VideoToolbox, and the missing Command key has a
  documented workaround (**Right-Option maps to CMD**). The disqualifier is
  that **Sunshine cannot create a virtual display on macOS** — there is no
  `hyprctl output create headless` equivalent — so a lid-closed Mac has nothing
  to capture. Apple's Screen Sharing works headless and handles ⌘ natively.
- **RDP everywhere** — appealing because every OS ships a client, and RDP is a
  perfectly good protocol when it is not exposed to the internet (its
  reputation is about public exposure, not design). Dead because macOS cannot
  host RDP at all. Worth watching:
  [`lamco-rdp-server`](https://github.com/lamco-admin/lamco-rdp-server), a
  Rust/IronRDP Wayland-native server that explicitly supports Hyprland — but at
  ~34 commits it is far too young for this path, and it would not cover macOS
  anyway.
- **VNC only, everywhere** — genuinely uniform and a legitimate choice. Rejected
  as the default because it would make the two machines we care about most
  worse: no hardware encode on the Windows/macOS legs, no audio, higher latency.
  It is kept as the fallback rather than the primary.

### What to install, per machine

| machine | as a target | as a client |
| --- | --- | --- |
| **NixOS** | nothing — Sunshine + wayvnc are in this config | `moonlight-qt`, plus a VNC client |
| **Windows** | Sunshine, **or** enable native RDP (Pro/Enterprise only) | Moonlight; Microsoft Remote Desktop for RDP targets |
| **macOS** | **System Settings → General → Sharing → Screen Sharing.** Nothing to install | Moonlight; Screen Sharing app or any VNC client |

Netbird's client is the one mandatory install everywhere — without it there is
no route at all.

### wayvnc specifics

Enabled by `my.remote.vnc.enable`. Three things worth knowing:

**Authentication is your normal login password.** The config sets
`enable_pam=true`, which makes wayvnc authenticate against the real account via
PAM. This is deliberate and not just convenience: wayvnc's `enable_auth`
otherwise requires a literal `password=` in its config file, and that file is
generated into the Nix store, which is world-readable. PAM means no new
credential exists anywhere. Username is `sebastianstupak`, password is the one
from `secrets/README.md`.

**It is encrypted, and unauthenticated connections are refused.** The server
offers VeNCrypt (TLS) and RSA-AES and does *not* offer RFB security type 1
("None"). A self-signed certificate is generated on first start into
`~/.config/wayvnc/` (key at 0600) — self-signed because no CA can meaningfully
vouch for a laptop, and the client is always one of ours, so it is a transport
key rather than an identity claim. Clients warn on first connect; that is
expected.

**H.264 only helps with some clients.** `--gpu` enables the OpenH264 RFB
extension, but only **TigerVNC and noVNC** negotiate it. Apple's built-in
viewer and most others fall back to Tight — still works, just software-encoded.
So use TigerVNC when connecting *to* a Nix box if you want the accelerated path.

### Connecting

```bash
# Sunshine (NixOS/Windows targets) — Moonlight, host = overlay IP
# VNC (any target)
vncviewer hestia.netbird.cloud:5900          # TigerVNC; asks for your login password
```

## Desktop (Sunshine)

### First run on a new machine

Sunshine arrives configured by Nix but **unprovisioned** — it has no admin
credentials until someone visits it once. Four steps, in this order, because
two of them have timing traps.

**1. Start it.** Sunshine and wayvnc are both
`wantedBy=graphical-session.target`, and systemd does not retroactively pull a
newly-added unit into an already-running target — so straight after the switch
that first enables them, they are inactive. Log out and back in, or:

```bash
systemctl --user start sunshine wayvnc
systemctl --user is-active sunshine wayvnc     # both: active
```

**2. Wait for the encoder probe.** It takes about 54 seconds and nothing works
until it finishes:

```bash
journalctl --user -u sunshine -f | grep -m1 "Configuration UI available"
```

**3. Set admin credentials** at <https://localhost:47990> — accept the
self-signed certificate, then fill in the welcome screen. Localhost only by
design, so the same URL over the overlay returns **403**; that is the setting
working, not a fault.

The password is only for this admin UI. It is regenerable: delete
`~/.config/sunshine/sunshine_state.json` and revisit the page.

**4. Confirm hardware encoding.** Sunshine falls back to a software encoder
silently, so check rather than assume:

```bash
vainfo | grep -c VAEntrypointEncSlice     # want non-zero
journalctl --user -u sunshine | grep -E "va_openDriver|Selected monitor"
#   want:  va_openDriver() returns 0      and  Selected monitor [...]
```

On Intel this needs `intel-media-driver` — `hardware.graphics.enable` does not
provide it, and its absence is exactly how a silent software fallback happens
(see "Things that went wrong"). AMD gets VA-API from Mesa and needs nothing.

The `CUDA` / `nvenc` errors are expected on both machines — no Nvidia GPU.
Sunshine says so itself: *"Ignore any errors mentioned above, they are not
relevant."*

### Pairing (once per client)

The web UI is restricted to `origin_web_ui_allowed = "pc"`, so it is not exposed
on the overlay at all. Reach it through the SSH connection you already have:

```bash
ssh -L 47990:localhost:47990 sebastianstupak@<host>
```

Then open <https://localhost:47990> on the client, accept the self-signed
certificate, and set a username and password on first visit. In Moonlight, add
the host by its **overlay name** (`hestia.netbird.cloud`, not the LAN address), and enter
the PIN Moonlight shows into the web UI's PIN page.

Pairing state lives in `~/.config/sunshine/`, not in the Nix-generated config,
so it survives rebuilds.

**Do not try to pair within a minute of Sunshine starting.** Moonlight's pair
request times out after about 56 seconds, and Sunshine spends roughly 54
probing encoders on startup — the two windows overlap almost exactly, so a
pairing attempt against a just-restarted Sunshine fails with
`QNetworkReply::OperationCanceledError` and no clue as to why. Confusingly the
web UI answers the PIN with `{"status":true}` throughout, because it runs on a
different thread from the pairing state machine. Wait for
`Configuration UI available` in the journal, then pair.

Verified end to end on 2026-11-01: Moonlight paired against the overlay
address, `named_certs` showed the client, and it was then unpaired cleanly.

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

## Adding a machine

The bare-metal install is `docs/INSTALL.md`. This is only the remote-access
wiring, and it assumes the machine already boots this config.

Most of it is automatic now. **NetBird enrolment needs nothing**: the setup key
is in sops, `services.netbird.clients.default.login.setupKeyFile` hands it to
the daemon, the key auto-joins `my-devices`, and the policies apply the moment
it does. A reinstalled machine rejoins on first boot with nobody at the
keyboard. What follows is the part that still needs a decision or a key.

**Before the first boot** — from the password manager you need
`netbird/setup-key` only if the machine is being installed from scratch and
cannot yet decrypt sops (its host key is not a recipient until you enrol it,
which is `docs/INSTALL.md` step 6 and the lockout it warns about).

**1. Give it a WireGuard port.** In `hosts/<name>/default.nix`:

```nix
services.netbird.clients.default.port = 51822;   # next free; see modules/nixos/netbird.nix
```

Not cosmetic — two peers sharing a port collide under the gateway's
static-port NAT rule and one falls back to a relay. The allocation table lives
in `modules/nixos/netbird.nix`.

**2. Add a matching outbound NAT rule** on the gateway (Firewall → NAT →
Outbound): duplicate an existing NetBird rule and change its source port.

> Worth doing once, at machine #3: replace the per-machine rules with a single
> rule pointing at a **port alias** (Firewall → Aliases → type `Port`, content
> `51820-51829`). The source-port field rejects a literal range but accepts an
> alias, so after that a new machine needs no firewall change at all — just the
> next port in `hosts/<name>/`.

**3. Trust it, and let it trust you.** In `hosts/common/default.nix`:

```bash
# ON the new machine
cat /etc/ssh/ssh_host_ed25519_key.pub   # -> my.remote.peers.<name>.publicKey
cat ~/.ssh/id_ed25519.pub               # -> my.remote.authorizedKeys
netbird status                          # -> its FQDN, for peers.<name>.hostNames
```

Agent forwarding is off, so each machine needs its own key rather than
borrowing one over the wire. List them all in `allowed_signers` so commits stay
verifiable.

**4. Pair desktops, selectively.** Sunshine pairing is per direction and cannot
be declared — see "Pairing" above, and wait a minute after any Sunshine restart
or the pair request times out. Pair only the pairs you actually want: a paired
client can inject input, which is a bigger grant than SSH.

**5. Record its secrets.** `<host>/login-password`, `<host>/sunshine-web-ui`,
`<host>/ssh-key-passphrase` — the per-host items in `secrets/README.md`. None
of them can be recovered from the repo.

Nothing else is per-machine. The firewall scoping, SSH hardening, Sunshine,
wayvnc, the no-suspend policy and the NetBird group membership all come from
`hosts/common` and apply the moment the machine boots this config.

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
