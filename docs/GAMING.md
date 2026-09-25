# Gaming

An opt-in slice: `my.gaming.enable = true` in `hosts/workstation/default.nix`,
implemented in `modules/nixos/gaming.nix`. Importing the module does nothing on
its own.

What it turns on: Steam with Proton, Lutris for everything outside Steam,
gamemode and MangoHud, and Prism Launcher for Minecraft.

## The hardware you are working with

This machine has **AMD Cezanne integrated graphics** (Radeon Vega, sharing
system memory). Mesa is in-tree, so there is no driver to install and nothing
proprietary to enable — but it is an iGPU on a laptop. Expect older or
lightweight titles at 1080p, and expect to turn settings down. Minecraft is
comfortable; a current AAA title is not.

Two knobs matter more than graphics settings here:

- **Thermals.** The chassis throttles before the GPU runs out of capacity. If
  frame times get choppy after ten minutes, that is heat, not the GPU.
- **Memory.** An iGPU takes its VRAM from system RAM. Closing a browser with
  forty tabs does more for a game than dropping a setting.

Check both with MangoHud rather than guessing:

```bash
mangohud %command%        # in Steam: right-click a game > Properties > Launch Options
mangohud <some-game>      # anything else
```

## Steam

First run asks you to log in; that is the only manual step.

**Proton** turns a Windows game into something that runs here. Steam picks a
version per game:

*Right-click a game → Properties → Compatibility → Force a specific tool*

Valve's `Proton Experimental` is the right first try. If a game shows black
cutscenes, silent audio, or refuses to start, switch to **GE-Proton** — it is
installed alongside Valve's builds and carries media codecs and per-game fixes
Valve cannot ship for licensing reasons. That single swap fixes most of it.

To see whether a specific game works before buying it, check
[ProtonDB](https://www.protondb.com/) — it is community reports per title.

**gamemode** is on. Steam applies it automatically; elsewhere run
`gamemoderun <game>`. It asks the CPU governor for performance while the game
runs and puts it back afterwards, rather than pinning the laptop to a
performance profile and eating the battery.

**Ports stay closed.** Steam Remote Play and the dedicated-server firewall holes
are both disabled. Turn one on deliberately in `modules/nixos/gaming.nix` if you
actually stream to another device — a laptop on café Wi-Fi should not be
listening by default.

## Minecraft

**Prism Launcher**, open source and packaged here. It carries JDK 8, 17, 21 and
25 inside its own closure, so every Minecraft version has the Java it expects
and nothing is installed system-wide.

First run:

1. **Add your account** — *Accounts → Manage Accounts → Add Microsoft*. It opens
   a browser, you sign in, done. This is the account that owns the game.
2. **Make an instance** — *Add Instance*, pick a version.
3. **Mods, if you want them** — pick Fabric, Forge, Quilt or NeoForge while
   creating the instance, then *Edit → Mods* to add them. Prism installs the
   loader itself; you do not download one.

Each instance is independent: its own version, its own mods, its own saves. A
modpack that breaks does not touch anything else.

To give an instance more memory (the usual fix for a heavy modpack):
*Edit → Settings → Memory*. Do not give it more than about half the system RAM —
this machine shares memory with the GPU, and starving that makes things worse,
not better.

### A note on launchers

TLauncher is the one you will find first if you search. It is not set up here
and is not in nixpkgs. Its main draw is playing without owning the game, and it
has a documented history of bundling adware. Prism does everything it does —
multiple versions, mod loaders, offline play once your account is added — from
source that can be read.

Offline play works in Prism: add your Microsoft account once while online, and
it will launch without a connection afterwards.

## Non-Steam games

**Lutris** covers GOG, itch.io, standalone Windows games and emulators. It
manages its own per-game Wine prefixes, so nothing collides with the Ableton
prefix (see [ABLETON.md](./ABLETON.md), which is a separate, hand-managed
prefix — do not point Lutris at it).

**protonup-qt** manages Proton-GE versions *for Lutris and Heroic*. Steam gets
its copy from the Nix config instead, so there is nothing to do there.

For Epic or GOG storefront integration, add `heroic` to the package list in
`modules/nixos/gaming.nix` — one line.

## Turning it off

```nix
my.gaming.enable = false;   # hosts/workstation/default.nix
```

That removes Steam, the 32-bit graphics stack and the rest on the next rebuild.
Verified: with the flag off, none of it is in the built system. Your Steam
library and Prism instances live in `~/.local/share` and `~/.steam`, so they
survive — turning the flag back on picks them up again.
