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
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
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

  # Converge the prefix automatically, so the only manual act is putting the
  # licensed zip somewhere — no command to remember, and a reinstall rebuilds
  # the prefix on its own.
  #
  # A .path unit rather than only running at login: dropping the zip into
  # ~/Proprietary is the event that makes the install possible, so that is what
  # should trigger it. PathExistsGlob re-arms after the service runs, so a later
  # upgrade zip is picked up the same way.
  systemd.user.paths.ableton-install = {
    description = "Watch for an Ableton Live installer";
    wantedBy = [ "default.target" ];
    pathConfig.PathExistsGlob = "%h/Proprietary/ableton_live*.zip";
  };

  systemd.user.services.ableton-install = {
    description = "Create the Ableton wineprefix and install Live";
    # No wantedBy: this is started by the .path unit above, never on its own.
    serviceConfig = {
      Type = "oneshot";
      # Skip silently when Live is already installed, rather than reinstalling
      # every time the path unit re-arms. A condition exits the unit as
      # SUCCESSFUL-but-skipped, so a machine that is already set up does not
      # show a failed unit on the bar.
      ExecCondition = pkgs.writeShellScript "ableton-not-installed" ''
        ! ls "$HOME"/.wine-ableton/drive_c/ProgramData/Ableton/*/Program/"Ableton Live"*.exe >/dev/null 2>&1
      '';
      ExecStart = "${abletonInstall}/bin/ableton-install";
      # Unpacking and running a Windows installer is slow, and killing it
      # half-way leaves a broken prefix.
      TimeoutStartSec = "2h";
    };
  };
}
