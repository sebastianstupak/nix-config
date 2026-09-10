# Pro-audio profile: low-latency PipeWire (JACK), realtime scheduling for the
# audio group, NTSync + the Wine-based Ableton runtime (shibco/ableton-linux).
#
# This is the declarative system groundwork. The Ableton wineprefix itself is
# imperative state. After switching, create it and configure realtime via the
# flake's apps (verified names):
#   nix run github:shibco/ableton-linux#setup-prefix
#   nix run github:shibco/ableton-linux#setup-realtime
#   nix run github:shibco/ableton-linux#default      # launch Ableton Live
# then authorize Ableton offline. Install Windows VSTs into the same wineprefix.
# The `ableton-wine` runtime package is also installed system-wide (below).
# See the project README for details and plugin/DRM caveats.
{ inputs, pkgs, ... }:
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

  # The Ableton Live + Push runtime (patched Wine + PipeASIO + Link daemon).
  environment.systemPackages = [
    inputs.ableton-linux.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
