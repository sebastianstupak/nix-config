# Hyprland Wayland desktop: compositor config, bar, launcher, notifications,
# lock/idle, and supporting utilities. System-level Hyprland (the session) is
# enabled in modules/nixos/desktop.nix; here we own the per-user config.
{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
{
  wayland.windowManager.hyprland = {
    enable = true;
    # Use the Hyprland from the system (programs.hyprland.enable) to avoid
    # installing/most-importantly version-mismatching two copies.
    package = null;
    portalPackage = null;

    # On Hyprland 0.55 the HM module defaults to a Lua config (hyprland.lua), whose
    # serialization mangles bind strings (`hl.bind("SUPER, Return, ...")` is not a
    # valid call). Force the classic hyprlang format (hyprland.conf) — it renders
    # these bind/exec-once/variable settings correctly.
    configType = "hyprlang";

    settings = {
      "$mod" = "SUPER";
      "$terminal" = "ghostty";
      "$menu" = "fuzzel";

      monitor = ",preferred,auto,1";

      # No waybar here: it runs as a systemd user unit (modules/home/waybar.nix),
      # started by graphical-session.target. Launching it here too would give you
      # two bars.
      exec-once = [
        "hypridle"
        # Night light daemon. Started with --identity so it applies NO colour
        # change until asked: hyprsunset's own default is 6000K, which is already
        # slightly warm and would tint the screen from login. It has to run
        # continuously because `hyprctl hyprsunset` talks to its socket
        # (.hyprsunset.sock) — the toggle on waybar's backlight module is a
        # request to this daemon, not a new process.
        "hyprsunset --identity"
        # No nm-applet: it existed only for its tray icon, which duplicated
        # waybar's own `network` module (two network indicators side by side).
        # It was also NetworkManager's secret agent (D-Bus name
        # org.freedesktop.network-manager-applet), so joining a NEW wifi network
        # now goes through nmtui, which registers its own agent and prompts for
        # the password itself. Wired to right-click on the network module.
        # blueman-applet stays, but with its tray icon switched off (see
        # dconf.settings below) — waybar's own `bluetooth` module covers the
        # status, and the two side by side was the duplicate. Unlike nm-applet
        # this one cannot simply be dropped: blueman's pairing agent lives in
        # blueman/main/applet/BluezAgent.py, so killing the applet takes the
        # PIN/confirm dialogs with it and blueman-manager registers no agent.
        "blueman-applet"
        "wl-paste --watch cliphist store" # clipboard history daemon
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
      ];

      input = {
        kb_layout = "us,sk";

        # `caps:none` BECAUSE A CAPS LOCK STATE CANNOT BE KEPT IN SYNC OVER
        # MOONLIGHT, and the symptom was "caps is on every time I connect".
        # Alt+Shift cycles US <-> SK (Windows-style) as before.
        #
        # The lock state is not one state. Hyprland gives EVERY keyboard device
        # its own `xkb_state`, and the state handed to the focused window is the
        # one belonging to the device that sent the key — `onKeyboardMod` copies
        # `pKeyboard->m_modifiersState` and only OR-merges the DEPRESSED field
        # across devices (`shareModsFromAllKBs`); `locked` is never merged, and
        # `getModifiers()` deliberately returns `depressed | latched` only. So
        # the laptop keyboard and Sunshine's virtual one hold independent,
        # invisible caps locks. Reported upstream twice —
        # hyprwm/Hyprland#3897 and #9560 — and BOTH ARE CLOSED AS NOT PLANNED,
        # so there is no fix to wait for.
        #
        # Which makes Moonlight the worst case, for three reasons that compound:
        #
        # 1. Sunshine's uinput keyboard (`libvirtualhid-keyboard` in
        #    `hyprctl devices`) is created once when sunshine.service starts,
        #    not per stream. Measured on zagreus 2026-11-07: one device, alive
        #    3 days, across six CLIENT CONNECTED/DISCONNECTED pairs. Its caps
        #    lock is therefore whatever the LAST session left it as.
        # 2. Moonlight never tells the host otherwise. moonlight-qt's
        #    app/streaming/input/keyboard.cpp forwards Caps Lock as a plain
        #    keypress (VK 0x14) and has no KMOD_CAPS handling at all — it
        #    sends the TOGGLE, never the STATE. The client's own caps lock is
        #    tracked by Windows and resets independently every time you leave
        #    the stream, so the two drift apart by design.
        # 3. The LED cannot tell you which one is on. `updateKeyboardsLeds`
        #    pushes the event-source keyboard's LEDs to every keyboard, so the
        #    laptop's caps light reflects whichever device typed last — and
        #    with nobody at the laptop, it is dark while the virtual keyboard
        #    is locked.
        #
        # Net effect: a sticky toggle you cannot see, cannot query from the
        # client, and can only guess at by typing a letter. Pressing it again
        # from Moonlight fixes it until the next drift.
        #
        # `caps:none` removes the possibility rather than making it less
        # likely, the same move as `my.remote.capture = "kms"`: with no lock
        # action in the keymap, no device can enter a locked state, so there is
        # nothing left to desynchronise. Moonlight may forward VK 0x14 forever
        # and it does nothing. Shift still capitalises; in Neovim `gU`/`~` are
        # the better tools for a run of capitals anyway.
        #
        # If the key is wanted back, `caps:escape_shifted_capslock` keeps a
        # REAL Caps Lock behind Shift+Caps Lock (and makes the bare key Esc),
        # which is deliberate enough that it cannot drift by accident.
        # `numpad:mac` is the num-lock half of the same bug (it is what #9560
        # settled on) — not set here because nothing has complained about it.
        #
        # NOTE THIS DOES NOT CLEAR A LOCK THAT IS ALREADY SET, and afterwards
        # there is no key left that could. Hyprland rebuilds `xkb_state` on a
        # config reload but keeps reporting the stale cached value, and only a
        # NEW device object really starts clean. See docs/REMOTE.md.
        kb_options = "grp:alt_shift_toggle,caps:none";

        follow_mouse = 1;
        touchpad.natural_scroll = true;
      };

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        layout = "dwindle";
      };

      decoration.rounding = 6;

      # Hyprland's built-in defaults are cinematic — ~480ms for `windows` and
      # ~540ms for `border`, which makes focus changes feel laggy even though
      # focus itself is instant. Speeds are in deciseconds (1 unit = 100ms);
      # roughly halved here. `windows`/`border`/`fade`/`layers` are parent nodes,
      # so their children (windowsIn, fadeOut, layersIn, ...) inherit these
      # unless separately overridden.
      # To retune without a rebuild: hyprctl keyword animation "windows,1,1.4,snap"
      animations = {
        enabled = true;
        bezier = [
          "snap, 0.2, 1, 0.2, 1" # hard ease-out: moves immediately, settles fast
          "linear, 0, 0, 1, 1"
        ];
        animation = [
          "windows, 1, 2.2, snap, popin 92%"
          "windowsOut, 1, 1.6, snap, popin 92%"
          "border, 1, 2, linear"
          "fade, 1, 1.6, snap"
          "layers, 1, 1.8, snap, popin 95%"
          "workspaces, 1, 1.8, snap, slidefade 15%"
        ];
      };

      bind = [
        "$mod, Return, exec, $terminal"
        "$mod, Q, killactive"
        "$mod, E, exec, nautilus"
        # Toggle, not just launch: fuzzel has no single-instance lock, so
        # pressing $mod+R twice would stack a second launcher on the first.
        # pkill exits 1 when nothing matched (-> open it), 0 when it killed one
        # (-> stays closed). Hyprland runs exec through sh -c, so `||` works.
        # Substring match rather than `pkill -x`: fuzzel happens to be an
        # unwrapped ELF today (comm is exactly `fuzzel`, so -x would work), but
        # wofi here was `.wofi-wrapped` and an exact match found NOTHING —
        # the toggle silently degraded back to stacking. Not worth re-learning
        # if this ever gains a wrapper. Keep the pattern short: procps matches
        # against comm, which is capped at 15 chars.
        "$mod, R, exec, pkill fuzzel || $menu"
        "$mod, V, togglefloating"
        # Two fullscreen modes: 0 (default) is true fullscreen — covers the bar
        # and gaps. 1 is "maximize": fills the workspace but keeps waybar and
        # the gaps, which is what you usually want for a wide editor/browser.
        "$mod, F, fullscreen, 0"
        "$mod SHIFT, F, fullscreen, 1"
        "$mod, L, exec, hyprlock"
        "$mod SHIFT, X, exec, wlogout" # power menu
        "$mod, C, exec, cliphist list | fuzzel --dmenu | cliphist decode | wl-copy" # clipboard history

        # Waybar signals: USR1 hides/shows the bar (handy for a full-width
        # editor without leaving true fullscreen). USR2 re-reads config + CSS —
        # not needed after a rebuild (the unit reloads itself, see waybar.nix),
        # but it fixes the bar re-laying-out wrong after a monitor hotplug.
        # Plain `pkill waybar`, NOT `pkill -x`: waybar is a wrapped binary, so
        # its comm is `.waybar-wrapped` — an exact match finds nothing. Same
        # trap as fuzzel above; it happens to fit in comm's 15-char cap exactly.
        # Notification centre (swaync). Same toggle semantics as the bar
        # module's click; -sw so it works even if swaync is not up yet.
        "$mod, N, exec, swaync-client -t -sw"

        "$mod, B, exec, pkill -SIGUSR1 waybar"
        "$mod SHIFT, B, exec, pkill -SIGUSR2 waybar"

        # focus movement
        "$mod, left, movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up, movefocus, u"
        "$mod, down, movefocus, d"

        # region screenshot to clipboard
        ", Print, exec, grim -g \"$(slurp)\" - | wl-copy"
        # Windows-style snipping tool: region screenshot -> annotate (swappy)
        "$mod SHIFT, S, exec, grim -g \"$(slurp)\" - | swappy -f -"

        # media keys (Spotify, browsers, ... via MPRIS/playerctl)
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"
      ]
      # Workspaces 1-9: $mod+N focuses it, $mod+SHIFT+N sends the focused window
      # there. Generated rather than written out 18 times — the two lines below
      # are the whole spec. `movetoworkspace` follows the window to the new
      # workspace; swap in `movetoworkspacesilent` to stay put instead.
      ++ builtins.concatMap (n: [
        "$mod, ${n}, workspace, ${n}"
        "$mod SHIFT, ${n}, movetoworkspace, ${n}"
      ]) (builtins.genList (i: toString (i + 1)) 9);

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      # repeatable audio / brightness keys
      #
      # `-l 1.0` caps the result at 100%. Without it wpctl has NO upper bound and
      # happily amplifies past unity — measured: from 0.98, three 5%+ steps land
      # on 1.15, which is software gain and clips. The limit applies to the
      # down-step too, so a sink already left above 100% snaps back to 1.0 on the
      # first press instead of creeping down through 1.10, 1.05, ...
      # The lower end needs nothing: wpctl already clamps at 0.00.
      bindel = [
        ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86AudioLowerVolume, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%-"
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86MonBrightnessUp, exec, brightnessctl set 5%+"
        ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
      ];

      # Lid: blank the LAMP, leave the OUTPUT alone.
      #
      # `bindl` so it fires with the session locked, which is the state a
      # closed lid is normally in. Hyprland reports this switch as "Lid Switch"
      # (`hyprctl devices`); `switch:on` is closed.
      #
      # Why not dpms off, which is what every guide reaches for: KMS capture
      # (modules/nixos/remote.nix) reads the scanout buffer, and dpms off stops
      # scanout — it would trade a lit panel for a dead stream. Zero brightness
      # keeps the framebuffer and only kills the backlight.
      #
      # `-s`/`-r` are brightnessctl's own save and restore, so reopening gives
      # back the brightness you had rather than a hardcoded level.
      bindl = lib.optionals osConfig.my.power.lidBacklightOff [
        ", switch:on:Lid Switch, exec, brightnessctl -s set 0"
        ", switch:off:Lid Switch, exec, brightnessctl -r"
      ];
    };
  };

  # Notifications, launcher, screen lock, idle daemon. The bar lives in
  # modules/home/waybar.nix.
  # Notification daemon lives in modules/home/notifications.nix (swaync).
  # Launcher. fuzzel over wofi: Wayland-native rather than GTK3, renders app
  # icons properly, and has a far richer Stylix target (11 color roles vs
  # wofi's 4) so it actually inherits the scheme instead of looking unstyled.
  # Stylix owns `main.font`, `main.icon-theme` and the whole [colors] section —
  # do NOT set those here. Stylix's mkTarget uses mkIf/mkMerge, not mkDefault,
  # so redefining them is a module-system conflict, not an override.
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        # Compact geometry: `width` is in characters, the pads in pixels.
        # Renders ~416x392 rather than fuzzel's roomier defaults (width 30 but
        # 40px horizontal pad, 15 lines). wofi's stylix target set none of this,
        # which is why it rendered edge-to-edge.
        width = 32;
        lines = 8;
        horizontal-pad = 14;
        vertical-pad = 10;
        inner-pad = 8;
        line-height = 20;
        icons-enabled = true;
        # Match on more than the app name — `gvim` finds "GVim", but this also
        # lets "browser" find LibreWolf via its generic name/keywords.
        fields = "name,generic,keywords";
        # Empty (quoted, so it is an explicit empty value rather than "unset",
        # which would fall back to fuzzel's default "> "). Not `hide-prompt`:
        # that removes the whole input line, taking the placeholder and the
        # echo of what you type with it.
        prompt = ''""'';
        placeholder = "Search";
        # Needed by non-dmenu modes that launch terminal apps.
        terminal = "ghostty -e";
        # Above fullscreen windows, so $mod+R works over a maximized app.
        layer = "overlay";
        # Keyboard focus is left at fuzzel's default (exclusive). Dismissing by
        # clicking outside is not achievable: fuzzel is layer-shell only, and a
        # click outside a layer surface is swallowed by it — Hyprland does not
        # even change activewindow, so nothing can react to it either. Don't
        # reach for keyboard-focus=on-demand or input.follow_mouse to fix this;
        # both were tried and only trade the bug for a worse one (the launcher
        # closing on mere pointer movement). Escape, or $mod+R again, dismisses.
      };
      # Rounded to match decoration.rounding; layer surfaces don't inherit it.
      border = {
        radius = 10;
        width = 2;
      };
    };
  };
  programs.hyprlock = {
    enable = true;

    # WHICH LAYOUT THE PASSWORD IS ABOUT TO BE TYPED IN.
    #
    # `kb_layout = us,sk` with `grp:alt_shift_toggle` above means the active
    # layout is a mode you can leave the machine in — and hyprlock showed no
    # indication of it, while waybar (which does show it) is not drawn on the
    # lock screen. So the one moment the layout matters most was the one moment
    # it was invisible.
    #
    # That is a lockout risk rather than a cosmetic gap: `sk` moves y/z and most
    # of the symbol row, so a password typed in the wrong layout fails with
    # nothing on screen to explain why, and the natural response — retype it
    # more carefully — fails identically. It is worse remotely, where the only
    # other way in is `loginctl unlock-session` over SSH.
    #
    # Stylix owns the colours of `background` and `input-field` (see
    # modules/nixos/stylix.nix); it does not style labels, so this one takes
    # base05 from the same palette rather than hardcoding a colour that would
    # not follow a scheme change.
    settings.label = {
      text = "$LAYOUT";
      color = "rgb(${config.lib.stylix.colors.base05})";
      font_size = 16;
      halign = "center";
      valign = "center";
      # Below the input field. hyprlock does not validate geometry and
      # `nix flake check` only verifies the HYPRLAND config, not this one, so if
      # it ever collides with the field this number is the thing to nudge.
      position = "0, -130";
    };
  };
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";

        # What makes `loginctl unlock-session` actually unlock, and the reason
        # it is here rather than in modules/nixos/remote.nix: hypridle is the
        # thing subscribed to logind's D-Bus lock/unlock signals, so without an
        # unlock_cmd the unlock event arrives and nothing happens. Locking
        # worked and unlocking silently did not.
        #
        # That matters for remote access specifically: the machine locks itself
        # after five minutes whether or not anybody is coming back.
        #
        # THE OTHER WAY IN NOW WORKS TOO, and the old reasoning here was only
        # ever true of the `wlr` capture backend. It said typing the passphrase
        # into hyprlock through the video stream depends on the backend being
        # able to see a session-locked screen, which is exactly what Hyprland's
        # session-lock protocol stops other CLIENTS from doing. But
        # my.remote.capture is `kms` now (modules/nixos/remote.nix), and KMS
        # capture is not a Wayland client — it reads the scanout framebuffer
        # underneath the protocol. Verified 2026-11-02: session locked, Moonlight
        # connected from the Windows machine, the hyprlock screen was visible
        # and typeable, and `grep -c "drm fb for plane"` stayed at zero.
        #
        # Keep unlocking over SSH as the DEFAULT anyway. It is already
        # authenticated by a key, it does not put the passphrase through a video
        # stream and an input path shared with whatever else is paired, and it
        # still works if the capture backend ever changes back.
        #
        # SIGUSR1, not a kill: it is hyprlock's clean-unlock signal. Killing
        # the process while an ext-session-lock is held leaves the compositor
        # locked with no client to draw it — the "lockscreen app died" screen.
        # Absolute path: hypridle runs this through a shell whose PATH is the
        # user unit's, and psmisc is not otherwise installed here.
        unlock_cmd = "${pkgs.psmisc}/bin/killall -q -s SIGUSR1 hyprlock";
      };
      # The LOCK listener is unconditional; the SLEEP one is not.
      #
      # my.power.remoteAccess drops the sleep listener entirely (and
      # modules/nixos/power.nix neutralises the lid alongside it), because a
      # machine that suspends ten minutes after you walk away is a machine you
      # cannot connect to — suspending drops the overlay tunnel and nothing can
      # wake it remotely. Locking still happens on the same five-minute timer,
      # so walking away still secures the screen; it just stays awake behind
      # the lock, and unlock_cmd above is how you get back in.
      listener = [
        {
          timeout = 300; # lock after 5 min idle
          on-timeout = "hyprlock";
        }
      ]
      ++ lib.optional (!osConfig.my.power.remoteAccess || osConfig.my.power.remoteAccessRequiresAC) {
        timeout = 600; # sleep after 10 min idle
        # suspend-then-hibernate once there is a swapfile to hibernate into
        # (my.power.hibernate.enable, modules/nixos/power.nix). Plain suspend
        # keeps drawing power, so a machine left idle on battery eventually
        # dies and loses the session — which is the whole thing hibernation
        # is here to fix, and it is pointless to fix the lid but not the
        # idle timeout. before_sleep_cmd above locks the session either way,
        # so resuming lands on hyprlock rather than in the session.
        #
        # Under my.power.remoteAccessRequiresAC the listener comes BACK but
        # its command is gated: `systemd-ac-power` exits 0 on mains, so the
        # `||` makes this a no-op while plugged in and a real suspend on
        # battery. It has to be a guard inside the command rather than a
        # conditional listener, because hypridle evaluates its config once
        # at start and the power state changes while it runs — unplugging
        # must take effect without restarting the daemon.
        #
        # systemd-ac-power ships with systemd and reads the same power-supply
        # state logind uses for HandleLidSwitchExternalPower, so the lid and the
        # idle timer cannot disagree about whether the machine is on mains.
        #
        # Absolute path, for the same reason unlock_cmd above is absolute: this
        # runs through a shell whose PATH is the user unit's. `systemctl` does
        # resolve there, but a guard that silently failed to execute would exit
        # non-zero and suspend a plugged-in machine — breaking the reachability
        # this option exists to keep, with nothing in the log to explain it.
        on-timeout =
          let
            sleepCmd =
              if osConfig.my.power.hibernate.enable then
                "systemctl suspend-then-hibernate"
              else
                "systemctl suspend";
            acPower = "${pkgs.systemd}/bin/systemd-ac-power";
          in
          if osConfig.my.power.remoteAccessRequiresAC then "${acPower} || ${sleepCmd}" else sleepCmd;
      };
    };
  };

  # Wifi picker for the bar's network module (modules/home/waybar.nix).
  # It shells out to whatever `dmenu_command` says, so pointing it at fuzzel
  # makes joining a network look and behave like every other picker here —
  # `-d` because fuzzel needs telling it is reading a list on stdin rather than
  # launching desktop entries.
  xdg.configFile."networkmanager-dmenu/config.ini".text = ''
    [dmenu]
    # Presented as a dialog rather than a bare list: its own prompt, wide
    # enough for "SSID  WPA2  ***" without truncating, and tall enough to show
    # a room's worth of networks without scrolling.
    dmenu_command = fuzzel -d -p "Wi-Fi  " -w 46 -l 14
    active_chars = ●○
    highlight = True
    compact = True
    list_saved = True

    # Passphrases go through pinentry, not through the picker. Without this the
    # tool falls back to asking fuzzel for the passphrase as ordinary text,
    # which renders it on screen in full. Same pinentry gpg-agent already uses,
    # so it looks like every other secret prompt here. Absolute path because the
    # tool execs this string directly rather than looking it up on PATH.
    pinentry = ${pkgs.pinentry-qt}/bin/pinentry-qt

    [pinentry]
    description = Wi-Fi passphrase
    prompt = Passphrase
  '';

  # Utilities referenced by the binds / exec-once above.
  home.packages = with pkgs; [
    grim # screenshot
    slurp # region selector
    swappy # screenshot annotation (snipping tool)
    wl-clipboard # wl-copy / wl-paste
    cliphist # clipboard history
    wlogout # power menu
    hyprsunset # night light daemon; toggled from waybar's backlight module
    pavucontrol # audio device / volume GUI
    networkmanager_dmenu # the bar's wifi picker: scan, join, enter a passphrase
    networkmanagerapplet # nm-connection-editor, for editing an existing connection
    nautilus # file manager
    polkit_gnome # authentication agent
  ];

  # Drop blueman-applet's tray icon so bluetooth is shown once, by waybar's
  # `bluetooth` module, instead of twice. A leading "!" is how blueman's
  # PersistentPluginManager marks a plugin disabled (main/PluginManager.py:
  # `return "!" + plugin in plugins`).
  #
  # StatusIcon is the plugin that owns the visible icon and StatusNotifierItem is
  # the SNI implementation it uses; both go. This is safe to unload — both
  # inherit BasePlugin's `__unloadable__ = True`, the only plugin depending on
  # StatusIcon is ShowConnected (which merely restyles that same icon), and
  # AuthAgent declares no dependency on it, so pairing prompts keep working.
  dconf.settings."org/blueman/general".plugin-list = [
    "!StatusIcon"
    "!StatusNotifierItem"
  ];

  # Hint Electron/Chromium apps to run natively on Wayland.
  home.sessionVariables.NIXOS_OZONE_WL = "1";
}
