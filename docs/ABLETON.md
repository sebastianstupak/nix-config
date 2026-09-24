# Ableton Live on NixOS

Ableton Live is a Windows application. There is no Linux build and there will
not be one. This runs the Windows binary under a patched Wine
([shibco/ableton-linux][upstream]), with PipeWire providing the audio device
through an ASIO shim.

Everything here is **opt-in**. `modules/nixos/audio.nix` does nothing until a
host sets `my.ableton.enable = true`, because enabling it is not a neutral act:
it adds `threadirqs` to the kernel command line, loads `ntsync` at boot, and
grants the `audio` group realtime scheduling. Those are system-wide latency and
scheduling trades that should never arrive as a side effect of importing a file.

[upstream]: https://github.com/shibco/ableton-linux

## Enabling it

```nix
# hosts/<host>/default.nix
imports = [ ../../modules/nixos/audio.nix ];
my.ableton.enable = true;
```

Then:

```bash
sudo nixos-rebuild boot --flake .#<host> && sudo reboot
```

`boot` and a reboot, not `switch`. `threadirqs` is a kernel parameter and
`ntsync` a boot-time module; a plain switch leaves both inactive and Wine then
fails in a way that does not mention either.

Verify after reboot:

```bash
grep -o threadirqs /proc/cmdline && lsmod | grep ntsync
```

## What the module sets up

| | |
|---|---|
| `services.pipewire.jack` | JACK clients routed through PipeWire |
| low-latency profile | 48 kHz, quantum 64–1024, negotiated at 256 |
| `security.pam.loginLimits` | `@audio`: `memlock unlimited`, `rtprio 99`, `nice -19` |
| `boot.kernelParams` | `threadirqs` — threaded IRQs, fewer xruns |
| `boot.kernelModules` | `ntsync` — required by the patched Wine |
| packages | the Ableton runtime, plus `ableton-install` |

Realtime limits need the user in the `audio` group, and `security.rtkit.enable`
(set in `desktop.nix`). Both are already true on `workstation`.

## The two halves: what is reproducible and what is not

This is the important idea, and the backup configuration depends on it.

```
~/proprietary/ableton/     licensed, irreplaceable   -> BACKED UP
~/.wine-ableton/           derived, ~14 GB, churns   -> EXCLUDED
```

`~/.wine-ableton` is a Wine prefix: a multi-gigabyte directory a Windows
installer writes into. Nix cannot own it, and there is no point backing it up —
it is fully regenerable, and Live writes `analytics.db`, crash logs and caches
inside it, so every backup run would push new blobs forever. It is excluded in
`modules/nixos/backup.nix`.

`~/proprietary/ableton` is the restore unit. A new machine needs exactly this
directory plus the flake.

```
~/proprietary/ableton/
├── ableton_live_<edition>_<version>_64.zip   the installer
├── Authorize_<code>.auz                      the offline authorisation
├── installers/                               plugin installers, run once
└── vst3/                                     plugin bundles
```

`vst3/` is symlinked into the prefix at
`C:\Program Files\Common Files\VST3`, so plugins live on the backed-up side of
the line. Delete the prefix, rebuild it, and the plugins are still there.

## Setting it up on a new machine

1. Install NixOS from this flake, with `my.ableton.enable = true`, and reboot.
2. Restore `~/proprietary` from backup. If there is no backup, download Live
   again from <https://www.ableton.com/en/account/> — the **Windows 64-bit**
   build, not macOS, and keep Ableton's filename.
3. Run the installer **from a terminal**:

   ```bash
   ableton-install
   ```

4. Authorise:

   ```bash
   ableton-live ~/proprietary/ableton/Authorize_*.auz
   ```

   If you have no `.auz`, launch `ableton-live`, take the Challenge Code to
   <https://www.ableton.com/en/account/authorize/offline/>, and apply the file
   it returns with the command above.

5. In Live: **Preferences > Audio**, Driver Type `ASIO`, Device `PipeASIO`.
   Without this Live uses a default backend and none of the low-latency work
   above is doing anything.

`ableton-install` must run from a terminal. It stops the Wine processes it
spawned before swapping the finished prefix into place, and refuses to do that
without a tty — it is asking permission to kill what might be a running Live
session. There is no environment variable to bypass it, and feeding a canned
answer does not work either: it asks two questions with different valid letters.

It logs to `$XDG_STATE_HOME/ableton-install.log` on every run. Read that first
when something fails; upstream's own logging is off by default, so without this
a failure twenty minutes into a 3.3 GB unpack leaves nothing behind.

## Plugins

**They must be Windows VSTs.** Live is a Windows binary under Wine, so a
Linux-native `.so` VST3 cannot load into it wherever it is placed. This is the
counterintuitive part on a Linux machine and the easiest way to lose an evening.
Download the Windows build.

Installer-based:

```bash
ableton-wine ~/proprietary/ableton/installers/SomePlugin-Setup.exe
```

`ableton-wine` is plain `wine` bound to this prefix, so any Windows installer
runs through it. Afterwards, move the resulting `.vst3` into
`~/proprietary/ableton/vst3/` so it survives a prefix rebuild.

Bundles that need no installer go straight into `~/proprietary/ableton/vst3/`.
VST2 `.dll` files go to `~/.wine-ableton/drive_c/Program Files/VstPlugins`,
which is not symlinked and so is lost on a prefix rebuild — prefer VST3.

Then in Live: **Preferences > Plug-Ins**, enable the VST3 system folder, Rescan.

Copy-protected plugins (iLok, eLicenser) are the usual casualty under Wine.
Their runtimes often will not install or cannot see the dongle. Nothing in this
config changes that; worth knowing before buying rather than after.

## Known rough edges

**The scripted Live install fails.** `ableton-install` installs Live through
upstream's staging transaction, which has to stop Wine before promoting the
prefix — the same tty gate as above, but reached mid-run. On this machine it
failed roughly six minutes in, every time, after unpacking 3.3 GB, and rolled
back. The workaround was installing Live directly into the prefix:

```bash
cd ~/.cache/ableton-wine-setup/live-installer
WINEPREFIX=$HOME/.wine-ableton ableton-wine \
  "./Ableton Live 12 Standard Installer.exe" \
  /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-
```

That bypasses the transaction and works. It is not yet wired into
`ableton-install`, so a genuinely fresh machine still needs this step by hand.

**Keyboard input appears dead right after launch.** Live's splash window can
hold focus. Click the main window. Verified working afterwards: X input focus
lands on Live and it acts on keys.

## Uninstalling

```nix
my.ableton.enable = false;
```

Then `sudo nixos-rebuild boot --flake .#<host> && sudo reboot` — the reboot
matters, since `threadirqs` only leaves the command line on one. The prefix is
imperative state and is not removed; delete `~/.wine-ableton` yourself
(~14 GB). Leave `~/proprietary` alone unless you mean it.
