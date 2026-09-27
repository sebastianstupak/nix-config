# Music notation

MuseScore Studio and Muse Hub, from `modules/home/music.nix`. Not opt-in — they
are small and pull in nothing unusual.

## What is here

- **MuseScore Studio** — notation. Ships the MS Basic soundfont.
- **Muse Hub** (`muse-sounds-manager`) — downloads the MuseSounds libraries and
  the MuseSampler engine that plays them.

## Sound: the part worth doing

Out of the box MuseScore plays through **MS Basic**, its bundled soundfont. It
is fine for proofreading and thin for anything else. MuseSounds are the sampled
libraries that make MuseScore 4 sound like recordings rather than MIDI.

Open **MuseSounds Manager**, pick the libraries you want — Strings, Brass,
Woodwinds, Keys, Choir, Percussion and so on — and hit Download. They are large;
take only what you will score for.

MuseScore finds them on its own afterwards. It looks for the engine at
`~/.local/share/MuseSampler/lib/libMuseSamplerCoreLib.so` and silently falls
back to the soundfont when it is absent, so if a new instrument still sounds
like MIDI, that path is the thing to check:

```bash
ls ~/.local/share/MuseSampler/lib/      # empty until Muse Hub has run
```

MuseScore logs which soundfonts it loaded at startup — run `mscore` from a
terminal and look for `SoundFontRepository::loadSoundFonts`.

## Audio path

Nothing to configure. MuseScore opens the ALSA `default` device, which PipeWire
provides, and PipeWire routes it to the sound card. Confirmed working:

```
$ wpctl status
  71. PipeWire ALSA [mscore]
       output_FL > ALC236 Analog:playback_FL   [active]
```

If playback is silent, check that stream in `wpctl status` before touching
anything in MuseScore — it is usually routing or a muted sink, not the app.

The pro-audio slice (`docs/ABLETON.md`) is independent. MuseScore does not need
JACK, and enabling it in MuseScore's preferences is not an upgrade here.

## Two things that are not bugs

**MuseScore runs on XWayland.** Its own binary calls
`setenv("QT_QPA_PLATFORM", "xcb", 0)` and the package sets the same default, so
`QT_QPA_PLATFORM=wayland` does nothing — verified by trying it. Upstream forces
X11 because its Qt Wayland support is not reliable. On a 1080p screen there is
nothing to gain by fighting it.

**Its theme is its own.** Stylix does not manage MuseScore, so it starts light
while the rest of the desktop is dark. Fix it inside the app: *Edit →
Preferences → Appearance → Dark*. That setting lives in MuseScore's own config,
which the app rewrites at runtime and this repo does not manage.

## Why Muse Hub needs the keyring

Muse Hub stores its login through the **Secret Service** D-Bus API
(`org.freedesktop.secrets`). This machine had no provider at all, and the
failure was not graceful: Muse Hub took an unhandled D-Bus exception mid-startup
and shut itself down with no window and nothing on screen explaining why.

`services.gnome.gnome-keyring.enable` in `modules/nixos/desktop.nix` fixes that,
with PAM unlocking the keyring using the password already typed at greetd — so
no second prompt at login. Verified: with a Secret Service on the bus, Muse Hub
opens its window and stays up; without one it exits during startup.

This benefits more than Muse Hub — it is the API desktop apps use generally
rather than inventing their own credential files.

## Why Muse Hub is wrapped

As packaged it crashes immediately:

```
symbol lookup error: libServiceCore.so: undefined symbol: zlibVersion
```

Its bundled `libServiceCore.so` calls zlib but never declares it as a NEEDED
library — `objdump -p` lists only libstdc++, libm, libgcc_s and libc. On distro
packages this works by accident, because something else in the process has
already pulled zlib into the global symbol scope.

`LD_LIBRARY_PATH` cannot fix it: with no NEEDED entry the loader never looks for
libz at all. The symbol has to be in the global scope before the library is
dlopened, which is what `LD_PRELOAD` does. `modules/home/music.nix` wraps the
binary to do exactly that.

Worth reporting upstream to nixpkgs. If a later version fixes it, the wrapper
becomes a harmless no-op and can be deleted.

## What still needs a human

1. **Download the libraries** in Muse Hub. Some need a free Muse account.
2. **Set the dark theme** in MuseScore's preferences, if you want it.
3. **A first login** in Muse Hub, which is what the keyring is for.
