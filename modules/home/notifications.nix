# Notifications: SwayNotificationCenter (swaync).
#
# Replaces mako rather than joining it. Only one process may own the
# org.freedesktop.Notifications D-Bus name; with two installed the winner is
# whichever activates first, so notifications would land in an arbitrary daemon
# between reboots. mako is removed in the same commit — see hyprland.nix.
#
# swaync over mako/dunst for one reason: it is the only one of the three with a
# control centre, i.e. a panel that lists past notifications. mako has
# `makoctl history` but that only replays the most recent one to the screen,
# and dunst's history is a keybind-driven redisplay — neither gives you a list
# you can read and dismiss individually, which is the whole point here.
{ lib, ... }:
{
  services.swaync = {
    enable = true;

    settings = {
      # --- popups (the transient toast) ---
      # Top-right, under the bar. positionY=top with the bar at layer top means
      # the toast would otherwise overlap it; the margin clears the bar plus the
      # 10px gaps_out from hyprland.nix.
      positionX = "right";
      positionY = "top";
      control-center-margin-top = 6;
      notification-window-width = 380;

      # Defaults are 10s for everything, which is long enough that toasts stack
      # up and hide the bar. Low-priority notifications get less; critical ones
      # never auto-dismiss, so nothing important disappears while you look away.
      timeout = 6;
      timeout-low = 3;
      timeout-critical = 0;

      # --- control centre (the list) ---
      # Opens on the LEFT, deliberately away from the toasts on the right, so
      # reviewing history never sits under an incoming popup.
      control-center-positionX = "left";
      control-center-positionY = "top";
      control-center-width = 420;
      control-center-margin-left = 8;
      control-center-margin-bottom = 8;
      # `top`, not `overlay`: overlay layers cannot be clicked away under
      # Hyprland (the same trap the launcher hit — see programs.fuzzel in
      # hyprland.nix), which for a panel you dismiss by clicking elsewhere
      # would be actively broken.
      control-center-layer = "top";
      layer = "top";

      # Group repeats from the same app instead of stacking N copies.
      notification-grouping = true;
      # Keep enough history to be useful without the panel becoming a scroll
      # marathon; swaync prunes oldest-first.
      keyboard-shortcuts = true;
      image-visibility = "when-available";
      transition-time = 150; # match the compositor's snappier animations

      widgets = [
        "title"
        "dnd"
        "notifications"
      ];
      widget-config = {
        title = {
          text = "Notifications";
          clear-all-button = true;
          button-text = "Clear all";
        };
        dnd.text = "Do not disturb";
      };
    };

    # Stylix declares `style` as types.lines across two blocks (font, then the
    # base00-base0F @define-color set plus its base.css), so this MERGES rather
    # than conflicting — same as waybar, and unlike fuzzel's [colors].
    # mkAfter to land last and win the cascade.
    style = lib.mkAfter ''
      /* Panel chrome. Stylix colours the widgets but sets no geometry. */
      .control-center {
        background: @base00;
        border: 2px solid @base02;
        border-radius: 12px;
        padding: 8px;
      }

      .control-center .notification-row {
        background: transparent;
      }

      /* Each notification reads as a card, so a list of them is scannable. */
      .notification {
        background: @base01;
        border: 1px solid @base02;
        border-radius: 8px;
        margin: 4px 2px;
        padding: 4px;
      }
      .notification:hover {
        background: @base02;
      }

      /* Critical notifications carry the scheme's red on the edge that the eye
         hits first, rather than recolouring the whole card. */
      .notification.critical {
        border-left: 3px solid @base08;
      }
      .notification.low {
        color: @base04;
      }

      .summary {
        font-weight: bold;
        color: @base05;
      }
      .body {
        color: @base04;
      }
      .time {
        color: @base03;
        font-size: 0.85em;
      }

      /* Title row: "Notifications" + Clear all. */
      .widget-title {
        color: @base05;
        margin: 4px 8px 8px 8px;
        font-size: 1.1em;
      }
      .widget-title > button,
      .notification-action,
      .widget-dnd > switch {
        background: @base01;
        border: 1px solid @base02;
        border-radius: 6px;
        color: @base05;
        padding: 2px 8px;
      }
      .widget-title > button:hover,
      .notification-action:hover {
        background: @base02;
      }

      .widget-dnd {
        color: @base05;
        margin: 4px 8px;
      }
      .widget-dnd > switch:checked {
        background: @base0D;
      }

      /* The floating toast — deliberately quieter than the panel cards. */
      .floating-notifications .notification {
        background: @base00;
        border: 2px solid @base02;
        border-radius: 10px;
      }
      .floating-notifications .notification.critical {
        border-color: @base08;
      }
    '';
  };
}
