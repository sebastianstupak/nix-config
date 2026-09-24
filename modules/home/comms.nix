# Communication apps.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    element-desktop # Matrix client
    zapzap # WhatsApp client (whatsapp-for-linux isn't in nixpkgs)

    # Microsoft Teams. There is no native Linux client any more — Microsoft
    # retired it in 2022 — so this is the community Electron wrapper around
    # teams.microsoft.com. It buys what the PWA does not have on Hyprland: a
    # tray icon (waybar has a `tray` module, so it is actually visible), real
    # D-Bus notifications, and the msteams:// URL handler for "join in app"
    # links in the Outlook calendar feed (modules/home/calendar.nix).
    #
    # Camera and microphone need nothing configured here, which is worth
    # recording because it is the part people go looking for:
    #
    #   camera  — the HP HD Camera is a plain UVC device at /dev/video0 and the
    #             user is in the `video` group (hosts/workstation/default.nix).
    #             Electron opens it directly through V4L2; no portal involved.
    #             Note the device exposes TWO nodes, /dev/video0 (capture) and
    #             /dev/video1 (metadata) — only the first one produces frames,
    #             which is why a device picker can show two identical cameras.
    #   mic     — PipeWire's PulseAudio interface (modules/nixos/desktop.nix).
    #             Per-app input/output routing is pavucontrol, already installed
    #             and bound to right-click on the waybar volume module.
    #   screen  — the nixpkgs wrapper already passes
    #             --ozone-platform-hint=auto and
    #             --enable-features=WaylandWindowDecorations,WebRTCPipeWireCapturer
    #             whenever NIXOS_OZONE_WL and WAYLAND_DISPLAY are both set, so
    #             sharing goes through xdg-desktop-portal-hyprland and picks up
    #             the Hyprland window chooser. Under X11 or with the variable
    #             unset it would silently fall back to a black screen.
    #
    # Its config lives at ~/.config/teams-for-linux/config.json and is
    # deliberately NOT managed here: the app writes to it from its own settings
    # UI, so a read-only store symlink would make every in-app change fail — the
    # same trap documented in modules/home/claude-code.nix. Two options worth
    # knowing about when you do edit it by hand: `closeAppOnCross` (false keeps
    # it running in the tray when you close the window) and `followSystemTheme`.
    teams-for-linux

    # Camera diagnostics, here rather than in cli.nix because this is the only
    # reason the machine needs them: `v4l2-ctl --list-devices` and
    # `v4l2-ctl -d /dev/video0 --list-formats-ext` answer "is the camera dead or
    # is the app wrong" in one command, which is otherwise a long afternoon.
    v4l-utils
  ];
}
