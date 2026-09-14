# Pro-audio profile: low-latency PipeWire (JACK), realtime scheduling for the
# audio group, NTSync + the Wine-based Ableton runtime (shibco/ableton-linux).
#
# This is the declarative system groundwork. The wineprefix itself is imperative
# state in $HOME — Nix cannot own a 4 GB directory that a Windows installer
# writes to — so the goal here is not to make it declarative but to make
# recreating it one command that needs nothing remembered:
#
#   ableton-install        # creates/refreshes the prefix AND installs Live
#   ableton-live           # launch
#
# Run `ableton-install` FROM A TERMINAL. It asks before stopping Wine and
# refuses when it has no tty, so it cannot be driven from a systemd unit — see
# the note further down where that automation used to live.
#
# `ableton-install` is defined below. The only step it cannot do for you is
# supply the installer: Live is licensed software behind an account login with
# no public URL, so the .zip has to be downloaded by hand into ~/Proprietary.
# Run the command once with the directory empty and it tells you exactly that.
#
# Authorising Live (offline, with your licence) stays manual for the same
# reason. Windows VSTs install into the same prefix.
#
# See the project README for plugin/DRM caveats.
{ inputs, pkgs, ... }:
let
  abletonPkgs = inputs.ableton-linux.packages.${pkgs.stdenv.hostPlatform.system};

  # The upstream prefix script, taken from the LOCKED input rather than invoked
  # as `nix run github:shibco/ableton-linux#setup-prefix`. That form re-resolves
  # the flake over the network every time and can drift from flake.lock — this
  # one is the exact revision this system was built against, and works offline.
  setupPrefix = "${abletonPkgs.ableton-wine}/share/ableton-wine/scripts/setup-prefix.sh";

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
      dir="''${ABLETON_INSTALLER_DIR:-$HOME/Proprietary}"
      mkdir -p "$dir"

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

      # Deliberately NOT setting ABLETON_LIVE_VERSION. Pinning a major makes
      # setup-prefix skip autoinstall altogether — it then only accepts an
      # exactly-matching installer rather than installing the newest found.
      export ABLETON_LIVE_AUTOINSTALL=1
      export ABLETON_INSTALLER_DIR="$dir"
      exec ${setupPrefix} "$@"
    '';
  };
in
{
  # Route JACK clients through PipeWire (pipewire itself is enabled in desktop.nix).
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
}
