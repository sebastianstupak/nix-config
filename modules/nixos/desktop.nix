# Graphical session: Hyprland (Wayland) + login manager, portals, audio, fonts.
# The per-user Hyprland/waybar/etc. config lives in home/ (modules/home/hyprland.nix).
{ pkgs, ... }:
{
  # Hyprland compositor. Provides the Wayland session and pulls in the
  # hyprland xdg-desktop-portal automatically.
  programs.hyprland = {
    enable = true;

    # Launch through UWSM rather than exec'ing the Hyprland binary directly.
    # UWSM puts the compositor inside a real systemd user session and starts
    # graphical-session.target / wayland-session@Hyprland.target itself. Without
    # it the session is stitched together by hand — the home-manager module has
    # to exec-once a dbus-update-activation-environment and manually start
    # hyprland-session.target — which leaves user units depending on that target
    # (waybar here) starting on a best-effort basis and never stopping cleanly
    # on logout. NixOS documents this as recommended for most users.
    withUWSM = true;
  };

  # GPU/OpenGL stack — needed for Ghostty's desktop-launch GL path and general
  # Wayland acceleration.
  hardware.graphics.enable = true;

  # VA-API, which `hardware.graphics.enable` does NOT give you on Intel.
  #
  # Mesa ships Gallium's VA-API drivers, so the AMD machine already had working
  # hardware video (radeonsi_drv_video.so). Intel's lives in a separate package
  # that nothing was pulling in, so /run/opengl-driver/lib/dri/ held no
  # iHD_drv_video.so at all and libva fell over with "unknown libva error" on
  # this machine only. The symptom that found it: Sunshine
  # (modules/nixos/remote.nix) probing encoders and failing EVERY one — nvenc
  # (no Nvidia, expected), vulkan, then vaapi — which leaves desktop streaming
  # with nothing but a software encoder, i.e. the one thing it exists to avoid.
  #
  # Not remote-specific, which is why it lives here rather than in remote.nix:
  # the same driver is what lets a browser or mpv decode h264/HEVC on the GPU
  # instead of the CPU, and on a laptop that is battery life.
  #
  # Installed on BOTH machines on purpose, the same union trade
  # hosts/common/hardware-configuration.nix makes for microcode: these hosts
  # share this file and Nix cannot branch on which one is evaluating, so the
  # alternative is the Intel machine silently keeping the broken behaviour.
  # The AMD machine carries some unused store paths; libva picks its driver
  # from the kernel driver in use, so the idle one is never loaded.
  #
  # iHD (intel-media-driver) rather than the older i965: this is a Raptor Lake
  # part, and i965 only covers up to Gen9. Verify with `vainfo` after a switch.
  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];

  # Login manager: greetd + tuigreet, offering the installed Wayland sessions.
  #
  # `--sessions` rather than `--cmd Hyprland`: with UWSM the session has to be
  # started via its desktop entry (hyprland-uwsm.desktop) so UWSM can set up the
  # systemd units — exec'ing the bare binary silently bypasses all of that.
  # Listing the directory also keeps the plain hyprland.desktop entry selectable,
  # which is the escape hatch if a UWSM session ever fails to come up: pick the
  # other entry at the greeter instead of editing config from a TTY.
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = builtins.concatStringsSep " " [
        "${pkgs.tuigreet}/bin/tuigreet"
        "--time"
        "--remember" # prefill the last username
        "--remember-session" # and the session it was used with
        "--sessions /run/current-system/sw/share/wayland-sessions"
      ];
      user = "greeter";
    };
  };

  # Extra XDG portal for GTK file pickers / settings (screencast portal comes
  # from Hyprland).
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # Virtual filesystem layer for Nautilus ($mod+E). udisks2 (on by default) is
  # what lets a USB stick mount at all; gvfs is what makes the file manager
  # actually complete. Without it there is no Trash — Nautilus has no
  # gvfsd-trash to move files into, so deleting is permanent-or-nothing — no
  # MTP, so a plugged-in phone does nothing, and no SMB/SFTP in the sidebar.
  # Secret Service (org.freedesktop.secrets) — the D-Bus API desktop apps use to
  # store a login rather than inventing their own credential file. There was no
  # provider on this machine at all, which is not a missing nicety: an app that
  # asks for it and finds nothing does not fall back politely. Muse Hub, for
  # one, took an unhandled D-Bus exception and shut itself down mid-login, with
  # nothing on screen to say why. See docs/MUSIC.md.
  #
  # PAM unlocks the keyring with the password already typed at greetd, so there
  # is no second prompt at login. Without that line the daemon runs but the
  # keyring stays locked, which fails in a more confusing way than not having it.
  #
  # hyprlock gets the same line, for the session that is NOT a fresh login.
  # greetd only unlocks the keyring at the start of a session; when the screen
  # locks later and is unlocked again — including remotely, over SSH, with
  # `loginctl unlock-session` (modules/nixos/remote.nix) — PAM runs for
  # hyprlock, not for greetd. Without this the keyring that greetd opened stays
  # open, which is fine, but a session whose keyring was never opened by a typed
  # password has no second chance to open it. Cheap, and it makes unlocking the
  # screen and unlocking the keyring the same act however you arrived.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;
  security.pam.services.hyprlock.enableGnomeKeyring = true;

  # A system Chrome, where tools that hardcode the FHS path expect to find one.
  #
  # Playwright — and the browser-automation MCP server built on it — defaults to
  # the "chrome" channel, which is not a package lookup but a literal check for
  # /opt/google/chrome/chrome. On a distro with an FHS that path exists; here
  # nothing does, so automation fails with "Chromium distribution 'chrome' is
  # not found" and no hint that the browser is in fact installed.
  #
  # The obvious fix is one `ln -s` into /opt, and that is exactly the kind of
  # undeclared drift this config exists to avoid: it survives reboots, is
  # invisible to `nixos-rebuild`, and silently pins a store path that the next
  # Chromium update invalidates. As a tmpfiles rule it is declared, reproduced
  # on a new machine, and re-pointed automatically when the package changes.
  #
  # Chromium rather than Google Chrome: it is the browser already installed
  # here, and automation does not need the proprietary build. Anything that
  # genuinely requires Chrome-only behaviour should ask for it explicitly.
  systemd.tmpfiles.rules = [
    "d /opt/google/chrome 0755 root root -"
    "L+ /opt/google/chrome/chrome - - - - ${pkgs.chromium}/bin/chromium"
  ];

  services.gvfs.enable = true;

  # Printing. CUPS alone only reaches printers you can name; avahi is what makes
  # a network printer show up by itself, which is the only mode that matters on
  # a laptop that visits other people's networks.
  #
  # nssmdns4 wires mDNS into NSS so .local names resolve for everything, not
  # just CUPS. openFirewall opens UDP 5353 — required, since discovery is
  # inbound multicast and the firewall is on.
  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # Calendar/contacts backend for GNOME Calendar (modules/home/calendar.nix).
  # The app itself is a home package, but everything it reads goes through
  # D-Bus-activated evolution-data-server services — without this option there
  # is no source registry to activate and it opens with no calendars at all.
  #
  # `plugins` is left at its default [], which keeps this to EDS alone: the
  # option installs `evolutionWithPlugins` and that is a symlinkJoin of
  # evolution-data-server plus whatever is listed, so the Evolution mail client
  # only appears if you ask for it (or set programs.evolution.enable).
  #
  # Don't be alarmed by the toolkit mismatch — gnome-calendar builds against
  # evolution-data-server-gtk4 while this ships the gtk3 build. Same EDS
  # version and same D-Bus interfaces; the toolkit only decides what draws
  # credential prompts, and the module offers no way to select the gtk4 one.
  services.gnome.evolution-data-server.enable = true;

  # Audio via PipeWire (replaces PulseAudio).
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # System fonts, including a Nerd Font for terminal/bar glyphs.
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-color-emoji
      nerd-fonts.jetbrains-mono
    ];
  };
}
