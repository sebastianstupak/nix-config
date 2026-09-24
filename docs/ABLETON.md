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

Run `ableton-install` from a terminal. Building the prefix has to stop any Wine
process using this runtime first, and it asks before doing so rather than
killing what might be an open Live session — with no tty it refuses instead of
asking. On a genuinely fresh machine nothing is running and it will not ask, but
the requirement is unconditional in the code, so make it a habit. There is no
environment variable to bypass it, and feeding a canned answer does not work
either: it asks two questions with different valid letters.

Close Live before re-running it.

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

**Live is installed outside upstream's staging transaction, on purpose.**
`setup-prefix` can install Live itself, but only inside a transaction whose
commit has to stop the Wine processes the install spawned — and it refuses to do
that without a tty even when one is present for its own prompts. Measured here:
it failed about six minutes in, every time, after unpacking 3.3 GB, and rolled
the whole prefix back.

So `ableton-install` builds the prefix *without* Live (which commits cleanly,
having no installer processes to stop) and then runs the installer directly into
the committed prefix, with the same engine detection and silent flags upstream
would have used. If that ever fails, it keeps the unpacked installer and points
at the log so a retry costs nothing.

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
