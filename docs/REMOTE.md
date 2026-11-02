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

**2. Wait for the encoder probe.** Under `capture = "kms"` this is now about
**1.6 seconds** — measured 2026-11-02, `08:50:20.877` to
`Configuration UI available` at `08:50:21.910`. It was ~54 s under `wlr`,
because each VA-API codec probe had to round-trip a screencopy frame. Still
worth waiting for the line rather than assuming, since nothing works until it
appears:

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

The `CUDA` / `nvenc` errors are expected and harmless. On `zagreus` there is no
Nvidia hardware at all; on `hestia` there *is* a discrete RTX A500, but
`hosts/hestia/default.nix` blacklists nouveau precisely so Sunshine stops
probing a CUDA encoder that can never exist. Either way Sunshine says it
itself: *"Ignore any errors mentioned above, they are not relevant."*

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

**The pairing race is gone under `kms`, but know what it was.** Moonlight's
pair request times out after about 56 seconds. Under `wlr` Sunshine spent
roughly 54 probing encoders, so the two windows overlapped almost exactly and a
pairing attempt against a just-restarted Sunshine failed with
`QNetworkReply::OperationCanceledError` and no clue as to why — confusingly the
web UI answers the PIN with `{"status":true}` throughout, because it runs on a
different thread from the pairing state machine. KMS probing takes ~1.6 s, so
the overlap no longer exists. Wait for `Configuration UI available` anyway; it
costs a second and it is the signal, not the clock.

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

**This also requires `my.remote.capture = "wlr"`**, and an assertion says so
rather than arranging it quietly. A virtual output exists only inside the
compositor, so the KMS backend has nothing to read — and `wlr` is the backend
that crashed the session (see "Streaming killed the whole desktop" below), so
choosing it has to be deliberate.

**One case calls for it:** you want a resolution other than the panel's.

It used to say two, the other being a closed lid, and **that was wrong.**
Measured on hestia 2026-11-02, sampled every second across a 32-second lid
close:

```
001 lid=open    drm=connected enabled=enabled dpms=On hypr_monitors=1 hypr_dpms=1
030 lid=closed  drm=connected enabled=enabled dpms=On hypr_monitors=1 hypr_dpms=1
062 lid=open    drm=connected enabled=enabled dpms=On hypr_monitors=1 hypr_dpms=1
```

The closed-lid samples are byte-identical to the open ones. Nothing turns the
panel off, because nothing is watching the lid: `my.power.remoteAccess` sets
logind to `ignore`, and Hyprland has no `switch:Lid Switch` bind of its own
(the generic advice this came from describes compositors that blank the
built-in panel themselves — Hyprland only does that if you tell it to).

That disproves the old claim, but it only establishes that there is something
*to* capture — the connector, not the plane Sunshine actually reads. The stream
surviving had to be tested separately, because:

- Sunshine's KMS backend captures a **plane**, and its documented failure mode
  is that plane losing its framebuffer — `Couldn't get drm fb for plane [0]`,
  logged roughly sixty times a second behind a black picture.
- Every indicator in that table can stay green while that happens.
- The upstream fix that reinitialises capture after a plane has been empty for
  250 ms ([Sunshine #5885](https://github.com/LizardByte/Sunshine/pull/5885))
  is **not** in the version packaged here, so a black stream would not recover.

**Tested 2026-11-02 and it works.** Lid shut, Moonlight connected from the
Windows machine, interacted with for a stretch, real picture throughout, and
over the whole window:

```bash
journalctl --user -u sunshine | grep -c "drm fb for plane"   # returned 0
```

So lid-closed streaming is confirmed and `headlessOutput` is not needed for it.
Re-run that grep after any Sunshine or Hyprland update — it is the cheap canary
for the plane going empty.

What a closed lid *does* cost is the backlight, which stays at full brightness
(`intel_backlight` 96000/96000) lighting the inside of a shut lid.
`my.power.lidBacklightOff` turns the lamp off and deliberately leaves the
output alone — `dpms off` would stop scanout, which is precisely what KMS
capture reads, so it would trade a lit panel for a dead stream.

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

This is not optional for remote access. **A suspended machine cannot be woken**,
and on these machines that is a dead end rather than an inconvenience worth
engineering around. Three separate reasons, all checked on hestia:

1. **Wake-on-LAN is a Layer-2 broadcast and the overlay is Layer 3.** The two
   ends of a WireGuard tunnel sit in unconnected broadcast domains, so a magic
   packet cannot cross it. Structural, not a NetBird limitation.
2. **The standard workaround does not exist here.** It is an always-on device on
   the target's LAN that takes your request over the tunnel and emits the magic
   packet locally. hestia is on `192.168.1.0/24`; no mesh peer shares that
   subnet — forge's NetBird endpoint is the public `159.195.202.232`. Only the
   gateway and two unidentified hosts are on the LAN.
3. **hestia has no Ethernet at all.** `wlp0s20f3` is the only interface, so even
   a relay would need WoWLAN — firmware-dependent on iwlwifi, and still
   requiring the sender to be on the same L2.

And a laptop that visits café and hotel networks has no relay there by
definition. So whatever was running is gone until somebody physically touches
the laptop. Plan around "awake or unreachable", not around waking it.

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

`my.power.lidBacklightOff` takes back the easy part of that cost — the panel
was staying lit behind the closed lid at full brightness — but not the hard
part, which is the machine being awake at all.

**On hestia there is no middle ground available.** `suspend-then-hibernate`
would be the right answer, and `my.power.hibernate.enable` asserts an encrypted
root; hestia's is plain `ext4` on `nvme0n1p2` with no LUKS device declared. So
the realistic choice there is "awake and reachable" or "plain suspend and
unreachable, losing the session if the battery runs out". Encrypting the root is
the prerequisite for anything better — see `docs/POWER.md`.

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

### Streaming killed the whole desktop (2026-11-02)

The first real Moonlight connection from `apollo` took `hestia`'s session down
with it, and the reason the symptom was unrecognisable is that it surfaced four
layers from the cause. Written out in full because every layer is misleading on
its own.

What was actually seen: *"Hyprland is in safe mode and says it is using an
autogenerated config."* That is neither a config problem nor something you fix
by editing config.

Working backwards:

1. `02:24:04` Moonlight connects. Sunshine picks `h264_vaapi` on the Intel
   iGPU, the vaapi vendor line reads `Intel iHD driver` — everything correct.
2. `02:24:14` `Error: Couldn't import RGB Image: 0000300C`, then
   `Error: Could not convert image`. `0x300C` is `EGL_BAD_PARAMETER` (not
   `EGL_CONTEXT_LOST`, which is `0x300E` — several forum threads get this
   wrong). Sunshine allocates the screencopy buffer itself, and neither side
   could import it.
3. Sunshine recreates the encoder and re-issues the capture. Hyprland fails the
   same import: `[EGL] Command eglCreateImageKHR errored out with
   EGL_BAD_PARAMETER (0x12300): plane attribute(s) missing`.
4. `02:24:16` Hyprland 0.55.4 **does not survive that failure.** It destroys a
   partially-constructed `CGLRenderbuffer` and segfaults:
   `Screenshare::CScreenshareFrame::copyDmabuf` →
   `IHyprRenderer::beginRender` → `getOrCreateRenderbuffer` →
   `~CGLRenderbuffer` → SIGSEGV. The crash report is in
   `~/.cache/hyprland/`; `coredumpctl` shows pipewire, waybar, swaync, the
   portal, hyprpaper and every open window going down in the same second.
5. Hyprland restarts, notices the previous session crashed, and enters **safe
   mode** — which by design refuses to load your config and falls back to an
   autogenerated one. Hence the message. Safe mode is not sticky: the next
   clean session loads the real config again, so there is nothing to undo.

**Fixed by `my.remote.capture = "kms"`** (the default now), which removes the
possibility rather than reducing it: Sunshine reads the framebuffer through
DRM/KMS and Hyprland's screenshare code is never entered at all, so an
unimportable buffer fails inside Sunshine where it belongs. The cost is
`capSysAdmin`, above.

Worth knowing if you are tempted back to `wlr`:

- **There is no upstream fix to wait for.** No issue is filed against Hyprland
  for this null-deref; the closest tracked relatives are a
  [SIGBUS in screencopy shm capture](https://github.com/hyprwm/Hyprland/issues/16388)
  and a [crash-on-monitor-change discussion](https://github.com/hyprwm/Hyprland/discussions/14857)
  with the same partially-constructed-renderbuffer shape.
- **The import failure itself looks size-dependent.** The nearest report
  ([jaehho/dotfiles#44](https://github.com/jaehho/dotfiles/issues/44)) hit the
  identical `0000300C` on a large native-mode output and had it import cleanly
  at `1920x1080@60` scale 1. `hestia`'s panel is `2560x1600@120`. So
  `my.remote.headlessOutput` with a modest pinned mode is the plausible way to
  make `wlr` work — at the price of streaming an empty workspace instead of the
  real session, which is the arrangement this setup deliberately rejects.
- Sunshine knows about this class of problem on its own side: it has a
  `[wayland] GBM buffer has unsupported plane count` error string for exactly
  the buffers it dislikes.

### Sunshine's config file is read-only, so its web UI cannot save

The unit runs `sunshine /nix/store/…-sunshine.conf`. That path is in the Nix
store, so **anything you change in the Settings pages of the web UI cannot be
written back**. Every setting has to come from `services.sunshine.settings` in
`modules/nixos/remote.nix`. There may also be a leftover zero-byte
`~/.config/sunshine/sunshine.conf`; it is not read and can be deleted.

Pairing state is different and does persist — it lives in
`~/.config/sunshine/sunshine_state.json`, not in the config file.

### The rest

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
- **`capSysAdmin` follows the capture backend, and is now ON.** It is what
  DRM/KMS capture needs, and `my.remote.capture` defaults to `kms` since the
  wlroots path segfaulted the compositor (see "Streaming killed the whole
  desktop" below). The capability applies to the whole binary and breaks
  launching applications as the ordinary user — affordable only because nothing
  here asks Sunshine to launch anything; Moonlight streams the session that is
  already running. Setting `my.remote.capture = "wlr"` turns it back off and
  re-arms that crash.

  **Do not be talked out of it by the monitor list.** KMS capture is *not*
  optional about this capability, but the obvious check says it is: without the
  capability Sunshine still enumerates displays perfectly —
  `Monitor 0 is eDP-1: AU Optronics 0x6DA8` — so the one line you would read to
  confirm KMS works looks fine. Capture fails one step later, and totally:

  ```
  Error: Couldn't get handle for DRM Framebuffer [330]: Probably not permitted
  Error: Unable to initialize capture method
  Error: Platform failed to initialize
  Error: Video failed to find working encoder     # every encoder, software included
  ```

  Measured 2026-11-02 by running the unwrapped binary against the same config.
  With the wrapper in place the log instead reads
  `has_elevated_privileges found effective cap:21` (21 is `CAP_SYS_ADMIN`),
  followed by `Found monitor for DRM screencasting` and
  `Found H.264 encoder: h264_vaapi [vaapi]`. Those last two are the lines that
  actually mean capture works.

  **Open problem — the grant stops working after a switch.** Straight after a
  boot the unit logs `effective cap:21`. After the rebuilds of 2026-11-02 the
  same unit logged `Failed to gain CAP_SYS_ADMIN` instead — with the same
  `ExecStart`, `/run/wrappers/bin/sunshine` still carrying
  `cap_setpcap,cap_sys_admin=p`, `NoNewPrivileges=no`, `cap_sys_admin` in the
  bounding set and `/run/wrappers` not `nosuid` — **and KMS capture streamed
  anyway.** So there is a second route to the DRM framebuffer that sometimes
  works without the capability, and it is not dependable: the unwrapped test
  above failed outright on the same machine the same day.

  A reboot restored the grant. Don't let a working stream reassure you — check:

  ```bash
  journalctl --user -u sunshine -b | grep -E "effective cap:21|Failed to gain"
  ```

  If it needs chasing, suspect the wrapper's capabilities being lost across the
  second exec into `bin/.sunshine-wrapped` (ambient vs permitted), not this
  config.

### Log noise that is expected, not broken

Sunshine probes every encoder at startup and says so itself — "Ignore any errors
mentioned above, they are not relevant." Specifically:

- **`Failed to create a CUDA device` / `Cannot load libcuda.so.1`** — the nvenc
  probe. `zagreus` has no Nvidia GPU; `hestia` has an RTX A500 whose driver is
  blacklisted (`hosts/hestia/default.nix`), which is what stops the probe
  finding a device to fail against. The probe is left in place rather than
  pinning `encoder = "vaapi"`, because auto-detection is self-healing if the
  hardware ever changes and the cost is about two seconds of benign log at
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
- **Startup used to take around a minute, and no longer does.** Under `wlr`
  each VA-API codec probe cost ~14 s because it round-tripped a screencopy
  frame; under `kms` the whole probe is ~1.6 s, so Sunshine is connectable
  almost immediately after login. If you ever see minute-long startups again,
  that is a sign something put the capture backend back to `wlr`.
- **`avahi::entry_group_new() failed: Not permitted`** is Sunshine noticing it
  may not advertise itself over mDNS, and carrying on. That is the intended
  state — see the mDNS note above.
- **Black frames are an Nvidia problem**, not a Hyprland one: the `wlr` backend
  cannot read Nvidia's tiled framebuffer layout. Neither machine *renders* on
  one — `hestia`'s RTX A500 has no display outputs wired to it and its driver
  is blacklisted, so Hyprland renders on the Intel iGPU and encodes with iHD.
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
