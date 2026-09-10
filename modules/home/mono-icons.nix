# Generates "StylixMono": a single-colour application icon theme with full
# coverage, used by the launcher.
#
# Why generate rather than install a theme: no packaged theme satisfies all
# three of (uniform colour, real glyphs, full coverage). Measured on this
# machine — Adwaita ships exactly 1 application icon, witalihirsch/Mono-icon-
# theme ships 7, and Kanagawa has good coverage but 382 distinct colours.
# Flattening a colour theme with a plain colorize also fails: these icons are a
# background plate plus a glyph, so filling the whole alpha region collapses
# both into an indistinguishable rounded square.
#
# What works is mapping *luminance to alpha*: composite over black, take the
# grey channel, normalise it per-icon (`-auto-level`, so dim icons don't
# vanish), clip the plate away (`-level 40%,100%`), then use that as the alpha
# mask for one flat colour. The glyph survives; the plate drops out.
#
# Icons are resolved from the live icon path, so apps that ship their own
# hicolor icon are covered too — that matters, because those are precisely the
# ones that would otherwise stay full-colour. Anything still unresolved falls
# back to its capital letter.
#
# This runs at activation rather than build time on purpose: the icon set
# depends on which applications are installed, and reading the profile that
# contains this very theme from a derivation would be circular.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  fg = "#${config.lib.stylix.colors.base05}";

  themeName = "StylixMono";

  generator = pkgs.writeShellScript "generate-mono-icons" ''
    set -u
    PATH="${
      lib.makeBinPath [
        pkgs.imagemagick
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnused
        pkgs.gnugrep
        pkgs.gawk
      ]
    }"

    out="$HOME/.local/share/icons/${themeName}"
    icons="$out/apps/64"
    rm -rf "$out"
    mkdir -p "$icons"

    # Search the live icon path. -L is essential: every theme directory here is
    # a symlink into the Nix store, and find will not descend one otherwise.
    search=""
    for d in \
      "$HOME/.local/share/icons" \
      "/etc/profiles/per-user/$USER/share/icons" \
      "/run/current-system/sw/share/icons"; do
      [ -d "$d" ] && search="$search $d"
    done

    # Every application advertised by a .desktop file on XDG_DATA_DIRS.
    names="$(grep -h '^Icon=' \
      /etc/profiles/per-user/"$USER"/share/applications/*.desktop \
      /run/current-system/sw/share/applications/*.desktop 2>/dev/null \
      | sed 's/^Icon=//' | grep -v '^/' | sort -u)"

    converted=0
    lettered=0

    for ic in $names; do
      [ -z "$ic" ] && continue
      # Prefer scalable, else the largest raster (dir names like 256x256).
      src="$(find -L $search -name "$ic.svg" 2>/dev/null | head -1)"
      if [ -z "$src" ]; then
        src="$(find -L $search -name "$ic.png" 2>/dev/null \
          | awk '{ if (match($0, /([0-9]+)x[0-9]+/, m)) print m[1]" "$0; else print 0" "$0 }' \
          | sort -rn | head -1 | cut -d' ' -f2-)"
      fi

      if [ -n "$src" ] && magick -background none "$src" -resize 64x64 \
           -background black -alpha remove -alpha off \
           -colorspace gray -auto-level -level 40%,100% -write mpr:g +delete \
           -size 64x64 xc:'${fg}' mpr:g -alpha off \
           -compose copy_opacity -composite "$icons/$ic.png" 2>/dev/null; then
        converted=$((converted + 1))
        continue
      fi

      # Fallback: capital letter. Strip any reverse-DNS prefix first, so
      # com.mitchellh.ghostty reads as G rather than C.
      letter="$(printf '%s' "''${ic##*.}" | cut -c1 | tr '[:lower:]' '[:upper:]')"
      [ -z "$letter" ] && letter="?"
      magick -size 64x64 xc:none -fill '${fg}' \
        -font ${config.stylix.fonts.monospace.package}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFont-Bold.ttf \
        -pointsize 42 -gravity center -annotate 0 "$letter" \
        "$icons/$ic.png" 2>/dev/null && lettered=$((lettered + 1))
    done

    # Written with printf rather than a heredoc: this is inside a Nix indented
    # string, which only strips the *common* prefix, so heredoc body lines would
    # keep their relative indentation and index.theme would not parse.
    printf '%s\n' \
      '[Icon Theme]' \
      'Name=${themeName}' \
      'Comment=Generated single-colour application icons' \
      'Directories=apps/64' \
      'Inherits=hicolor' \
      "" \
      '[apps/64]' \
      'Size=64' \
      'Context=Applications' \
      'Type=Fixed' > "$out/index.theme"

    echo "${themeName}: $converted converted, $lettered letter fallbacks"
  '';
in
{
  home.activation.monoIcons = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${generator}
  '';

  # Stylix also defines this key (from stylix.icons), and its mkTarget uses
  # mkIf/mkMerge rather than mkDefault — so plain assignment is a conflict and
  # mkForce is the only way to win. Stylix keeps owning the GTK/Qt icon theme;
  # only the launcher uses the generated one.
  programs.fuzzel.settings.main."icon-theme" = lib.mkForce themeName;
}
