# Pro-audio profile: low-latency PipeWire (JACK), realtime scheduling for the
# audio group, NTSync, and the Wine-based Ableton Live runtime
# (shibco/ableton-linux).
#
# OPT-IN. Importing this module does nothing; a host must set
# `my.ableton.enable = true`. See the option below for why.
#
# Full documentation — what it sets up, the reproducible/derived split that the
# backup config depends on, plugin handling, and the known rough edges — lives
# in docs/ABLETON.md. Kept there rather than here because it is a workflow
# people follow on a new machine, not a rationale for a line of Nix.
#
# The short version:
#
#   ableton-install   build the prefix and install Live (FROM A TERMINAL)
#   ableton-live      launch; also applies a .auz authorisation file
#   ableton-wine      plain wine bound to this prefix, for plugin installers
#
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.ableton;

  abletonPkgs = inputs.ableton-linux.packages.${pkgs.stdenv.hostPlatform.system};

  # The upstream prefix script, taken from the LOCKED input rather than invoked
  # as `nix run github:shibco/ableton-linux#setup-prefix`. That form re-resolves
  # the flake over the network every time and can drift from flake.lock — this
  # one is the exact revision this system was built against, and works offline.
  setupPrefix = "${abletonPkgs.ableton-wine}/share/ableton-wine/scripts/setup-prefix.sh";

  # wine bound to the Ableton prefix (it exports WINEPREFIX itself).
  abletonWine = "${abletonPkgs.ableton-wine}/bin/ableton-wine";

  # One command for "make the prefix and put Live in it".
  #
  # setup-prefix already knows how to install Live, but only opts in when
  # ABLETON_LIVE_AUTOINSTALL=1 and it finds an installer zip — which is a pair of
  # undocumented-at-the-call-site environment variables that are easy to get
  # wrong once and then never remember. This wrapper is that knowledge, written
  # down and on PATH.
  #
  # Idempotent, because setup-prefix checks for an installed Live
  # (drive_c/ProgramData/Ableton/*/Program/Ableton Live*.exe) before doing
  # anything, so re-running it to refresh the prefix will not reinstall.
  abletonInstall = pkgs.writeShellApplication {
    name = "ableton-install";
    # setup-prefix.sh is a third-party script written for an interactive shell,
    # so it reaches for whatever a normal PATH provides. That is invisible until
    # it runs somewhere PATH is minimal — as a systemd service it failed on
    # `flock is required to change this installation` — and cabextract and 7z
    # were not installed at all, so the vcredist path would have failed later
    # even from a terminal.
    #
    # Enumerated from the commands the script and its lib/ actually invoke,
    # rather than added one crash at a time.
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
      pkgs.util-linux # flock
      pkgs.file
      pkgs.unzip
      pkgs.cabextract # unpacking the bundled VC++ redistributable
      pkgs.p7zip
      pkgs.procps # ps/pgrep, used to wait on wine processes
      pkgs.diffutils # cmp, in lib/pipeasio.sh's alias consistency check
      pkgs.bash # scripts re-invoke bash by name
      pkgs.which
      pkgs.glibc.bin # getent / ldd / getconf
      abletonPkgs.default # wine, wineboot, wineserver
    ];
    text = ''
      # ~/proprietary is the restore unit: licensed artifacts that cannot live in
      # git or the Nix store, but that a fresh machine genuinely needs. Sliced
      # per product so it stays navigable when something other than Ableton
      # lands there. Lowercase, unlike upstream's $HOME/Proprietary — nothing
      # else in this home directory is capitalised, and exporting
      # ABLETON_INSTALLER_DIR is precisely what makes the location ours to pick.
      slice="''${ABLETON_SLICE_DIR:-$HOME/proprietary/ableton}"
      dir="''${ABLETON_INSTALLER_DIR:-$slice}"
      mkdir -p "$dir" "$slice/vst3" "$slice/installers"

      if [ -z "$(find "$dir" -maxdepth 1 -type f -iname 'ableton_live*.zip' -print -quit)" ]; then
        cat >&2 <<MSG
      No Ableton Live installer found in:  $dir

      This is the one step that genuinely cannot be automated. Live is licensed
      software behind an account login, with no public download URL to fetch from
      a derivation. Get the installer .zip from:

          https://www.ableton.com/en/account/

      and drop it in that directory, then run this again.

      Keep Ableton's own filename (ableton_live_<edition>_<version>_64.zip): the
      version is parsed out of it to pick the newest when several are present.
      MSG
        exit 1
      fi

      # ABLETON_LIVE_AUTOINSTALL is deliberately NOT set, which is the whole
      # point of this wrapper.
      #
      # With it on, setup-prefix installs Live inside its staging transaction,
      # and promoting that prefix requires stopping the Wine processes the
      # install spawned — which it refuses to do without a tty even when it has
      # one for its own prompts. Measured here: it failed ~6 minutes in, every
      # single time, after unpacking 3.3 GB, and rolled the whole prefix back.
      #
      # Building the prefix WITHOUT Live commits cleanly (no installer processes
      # to stop), so Live is installed afterwards, directly into the committed
      # prefix. Same installer, same flags upstream would have used, just
      # outside a transaction that cannot close over it.
      export ABLETON_INSTALLER_DIR="$dir"

      # Always leave a log. Upstream's is opt-in via ABLETON_INSTALLER_LOG and
      # unset by default, so a failed run's output dies with the terminal that
      # showed it — which is exactly what happened the first several times this
      # broke, leaving nothing to read afterwards. An install that unpacks 3.3 GB
      # and can fail twenty minutes in should not be diagnosed from memory.
      : "''${XDG_STATE_HOME:=$HOME/.local/state}"
      mkdir -p "$XDG_STATE_HOME"
      export ABLETON_INSTALLER_LOG="''${ABLETON_INSTALLER_LOG:-$XDG_STATE_HOME/ableton-install.log}"
      printf 'log: %s\n' "$ABLETON_INSTALLER_LOG"

      # Not exec: Live and the VST3 link both come after the prefix exists.
      ${setupPrefix} "$@"
      rc=$?
      [ "$rc" -eq 0 ] || exit "$rc"

      prefix="''${ABLETON_WINEPREFIX:-$HOME/.wine-ableton}"
      live_installed() {
        ls "$prefix"/drive_c/ProgramData/Ableton/*/Program/"Ableton Live"*.exe \
          >/dev/null 2>&1
      }

      if ! live_installed; then
        # Newest by the version in the filename, matching how setup-prefix picks
        # among several: the edition sorts before the version otherwise, so a
        # plain sort ranks "trial 11" above "suite 12".
        zip="$(find "$dir" -maxdepth 1 -type f -iname 'ableton_live*.zip' -print \
          | awk '{ n = $0; sub(/.*\//, "", n)
                   print (match(n, /[0-9]+(\.[0-9]+)+/) ? substr(n, RSTART, RLENGTH) : "0") "\t" $0 }' \
          | sort -V | tail -n 1 | cut -f2-)"

        unpack="''${XDG_CACHE_HOME:-$HOME/.cache}/ableton-wine-setup/live-installer"
        mkdir -p "$unpack"
        printf 'unpacking %s\n' "$(basename "$zip")"
        unzip -o -q "$zip" -d "$unpack"

        exe="$(find "$unpack" -maxdepth 1 -type f -iname '*Installer*.exe' -print -quit)"
        [ -n "$exe" ] || { printf '!! no installer .exe inside %s\n' "$zip" >&2; exit 1; }

        # Two engines ship under the same name and neither acts on the other's
        # switches; the wixburn marker in the header is how upstream tells them
        # apart.
        if head -c 4096 -- "$exe" | grep -qaF '.wixburn'; then
          flags=(/passive /norestart)
        else
          flags=(/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-)
        fi

        # From the installer's own directory: its payload lookups for
        # Installer-N.bin are relative, and 5 GB of .bin sits beside the .exe.
        #
        # The display must stay attached. Upstream's note is explicit that these
        # engines need a window connection even when told to be silent — a
        # headless run installs nothing at all and still exits 0.
        printf 'installing Live (several minutes)\n'
        ( cd "$(dirname -- "$exe")" \
          && timeout "''${ABLETON_LIVE_INSTALL_TIMEOUT:-3600}" \
             ${abletonWine} "./$(basename -- "$exe")" "''${flags[@]}" ) || true

        if ! live_installed; then
          printf '!! Live did not install. See %s\n' "$ABLETON_INSTALLER_LOG" >&2
          printf '!! The unpacked installer was kept at %s for a retry.\n' "$unpack" >&2
          exit 1
        fi

        # ~5 GB of extracted payload, and the zip it came from is still in the
        # slice, so this is pure duplication once the install succeeded.
        rm -rf "$unpack"
        printf 'Live installed\n'
      fi

      # Point the prefix's VST3 folder at the slice, so plugins stop being
      # prefix state. The prefix is 14 GB of regenerable churn that should never
      # be backed up; the plugins in it are neither. With this link you can
      # delete the prefix, rebuild it, and the plugins are still there — and
      # they ride along in the ~/proprietary backup for free.
      #
      # Verified against Wine rather than assumed: `winepath -u 'C:\Program
      # Files\Common Files\VST3'` resolves through the symlink to the slice, so
      # Live's scan of the Windows path reads the real directory.
      #
      # These are WINDOWS VST3s — only loadable by a Windows host in this
      # prefix, which is why they belong to the Ableton slice rather than beside
      # it, even though VST3 is a cross-DAW format in general.
      vst3_win="$HOME/.wine-ableton/drive_c/Program Files/Common Files/VST3"
      if [ ! -L "$vst3_win" ]; then
        # An existing real directory is only safe to replace when empty —
        # anything in it was installed there and would vanish from Live.
        if [ -d "$vst3_win" ] && [ -n "$(ls -A "$vst3_win" 2>/dev/null)" ]; then
          printf 'note: %s has plugins in it; move them to %s and re-run to link it\n' \
            "$vst3_win" "$slice/vst3" >&2
        else
          rmdir "$vst3_win" 2>/dev/null || true
          mkdir -p "$(dirname "$vst3_win")"
          ln -sfn "$slice/vst3" "$vst3_win"
        fi
      fi
    '';
  };
in
{
  # Opt-in, like my.backup.repository. Importing this module is NOT enough —
  # the whole slice stays inert until a host asks for it.
  #
  # It is gated because it is expensive and specific in a way the rest of the
  # modules are not: it pulls a patched Wine from a flake that deliberately does
  # not follow this nixpkgs, adds realtime scheduling limits for the audio
  # group, and changes the KERNEL COMMAND LINE (threadirqs) plus a boot-time
  # module (ntsync). None of that belongs on a host that is not making music,
  # and threadirqs in particular is a system-wide latency/throughput trade that
  # should never arrive as a side effect of importing a file.
  #
  # See docs/ABLETON.md for what it sets up and how to restore it on a new
  # machine.
  options.my.ableton.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Pro-audio profile and the Wine-based Ableton Live runtime.

      Off by default. Enabling changes kernel parameters, so it needs a reboot
      rather than just a switch.
    '';
  };

  config = lib.mkIf cfg.enable {
    # Route JACK clients through PipeWire   (pipewire itself is enabled in desktop.nix).
    services.pipewire.jack.enable = true;

    # A low-latency clock profile for production work.
    services.pipewire.extraConfig.pipewire."92-low-latency" = {
      "context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.quantum" = 256;
        "default.clock.min-quantum" = 64;
        "default.clock.max-quantum" = 1024;
      };
    };

    # Realtime scheduling limits for the audio group (rtkit is enabled in
    # desktop.nix; the user is in the `audio` group via the host config).
    security.pam.loginLimits = [
      {
        domain = "@audio";
        type = "-";
        item = "memlock";
        value = "unlimited";
      }
      {
        domain = "@audio";
        type = "-";
        item = "rtprio";
        value = "99";
      }
      {
        domain = "@audio";
        type = "-";
        item = "nice";
        value = "-19";
      }
    ];

    # Threaded IRQs reduce audio latency/xruns.
    boot.kernelParams = [ "threadirqs" ];

    # NTSync (mainlined in Linux 6.14; the default 26.05 kernel is 6.18) is required
    # by the patched Wine that shibco/ableton-linux ships.
    boot.kernelModules = [ "ntsync" ];

    # Note: performance CPU governor helps latency but is left to TLP on this
    # laptop (see laptop.nix) to preserve battery — switch it per-session if needed.

    # The Ableton Live + Push runtime (patched Wine + PipeASIO + Link daemon),
    # plus the prefix+install wrapper defined above.
    environment.systemPackages = [
      abletonPkgs.default
      abletonInstall
    ];

    # There is deliberately NO systemd unit installing this automatically.
    #
    # It was tried and it cannot work. setup-prefix.sh must stop the Wine
    # processes it spawned before swapping the finished prefix into place, and it
    # refuses to do that unasked (lib/lifecycle.sh):
    #
    #     if [ ! -t 0 ]; then
    #         echo "!! Wine is running. Run the installer in a terminal so it can
    #               ask before stopping Wine." >&2
    #         return 1
    #
    # With no tty it never even reaches the question, so the service failed about
    # six minutes in, every time, after unpacking 3.3 GB.
    #
    # No env var bypasses it: lifecycle.sh honours only ABLETON_{DATA_HOME,
    # LEFTOVER_AGENTS,SESSION_LABEL,STATE_HOME,WINEPREFIX,WINE_ROOT}. Faking a pty
    # and feeding a canned "y" is the obvious next move and is a trap — the script
    # asks two questions with different valid letters (q_stop_wine takes y/n,
    # q_overwrite takes o/k/a), so a stream of "y" answers the first and then
    # loops forever on the second until the timeout.
    #
    # So this stays `ableton-install`, run from a terminal. That is what upstream
    # supports, and the gate is there for a good reason: it is asking permission
    # to kill a Wine process that might be a running Live session.
  };
}
