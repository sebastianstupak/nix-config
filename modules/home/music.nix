# Music notation: MuseScore Studio, and Muse Hub for the MuseSounds libraries.
#
# Split out of media.nix because this is a different job from playing media —
# it is scoring, and it needs a working audio path and a credential store that a
# video player never asks for. Setting it up, and what still needs a human:
# docs/MUSIC.md.
{ pkgs, ... }:
let
  # Muse Hub crashes on startup as packaged:
  #
  #   symbol lookup error: libServiceCore.so: undefined symbol: zlibVersion
  #
  # Its bundled libServiceCore.so calls into zlib but never declares it as a
  # NEEDED library — checked with objdump, the only entries are libstdc++, libm,
  # libgcc_s and libc. On the distro packages it works by accident, because
  # something else in the process has already pulled zlib into the global symbol
  # scope. Nothing does that here.
  #
  # LD_LIBRARY_PATH cannot fix this: with no NEEDED entry the loader never looks
  # for libz at all. The symbol has to be in the global scope before the library
  # is dlopened, which is what LD_PRELOAD does.
  #
  # Verified: preloading it takes the app from an immediate symbol-lookup crash
  # to a full init (`_didFullyInit=True`) and a successful call to the MuseHub
  # API. Worth reporting upstream to nixpkgs; until then it lives here, next to
  # the only thing that uses it, rather than as an overlay for one package.
  muse-hub = pkgs.muse-sounds-manager.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/muse-sounds-manager \
        --prefix LD_PRELOAD : ${pkgs.zlib}/lib/libz.so.1
    '';
  });
in
{
  home.packages = [
    # Notation. Ships the MS Basic soundfont, which is what you get before Muse
    # Hub has installed anything better.
    pkgs.musescore

    # Muse Hub: downloads the MuseSounds libraries and the MuseSampler engine
    # that plays them. MuseScore looks for that engine at
    # ~/.local/share/MuseSampler/lib and quietly falls back to the soundfont
    # when it is absent — the difference is audible, not functional.
    muse-hub
  ];
}
