# One keyboard state for the whole machine, by giving the compositor one
# keyboard.
#
# Inert until `my.keyboard.mergeIds` is non-empty.
#
# THE PROBLEM IS NOT CAPS LOCK, it is that Hyprland keeps caps lock, num lock
# AND the active layout PER KEYBOARD DEVICE, and this machine has more than one
# keyboard whether you like it or not: the built-in one, and the uinput keyboard
# Sunshine creates for Moonlight (modules/nixos/remote.nix). Measured on zagreus
# 2026-11-07 — Alt+Shift on one device moved that device from
# `active layout index: 0` to `1` and left every other device on `0`; a Caps
# Lock tap locked one device and no other.
#
# In the source: `onKeyboardMod` copies `pKeyboard->m_modifiersState` from the
# keyboard that sent the event and OR-merges only the DEPRESSED field across
# devices (`shareModsFromAllKBs`, and `getModifiers()` returns
# `depressed | latched` deliberately). `locked` and `group` are never merged. So
# you can be caps-locked over Moonlight and not at the laptop, or on SK at the
# laptop and US over Moonlight, at the same time. Reported upstream twice —
# hyprwm/Hyprland#3897 and #9560 — BOTH CLOSED AS NOT PLANNED, and still
# unfixed in 0.56/0.57, so there is no release to wait for.
#
# There is also no lever to fix it from outside: Hyprland has no dispatcher that
# can set a keyboard's lock state. `hyprctl switchxkblayout all <index>` exists
# and does converge the LAYOUT (note `all next` does NOT — it advances each
# device's own index and so preserves the divergence), but nothing equivalent
# exists for locks.
#
# SO THE FIX IS TO STOP HAVING MORE THAN ONE KEYBOARD. keyd grabs the devices
# listed below and re-emits everything through a single virtual keyboard, and
# its man page is explicit that this is a supported use: "All keyboards defined
# within a given config file will share the same state." The compositor then
# sees one keyboard, so there is one caps lock, one num lock and one layout —
# shared by the laptop and by Moonlight, because both now arrive through the
# same device.
#
# This is deliberately NOT a remapping config. keyd is here purely as a
# multiplexer; `[main]` is empty and every keycode passes through untouched, so
# xkb still owns the layout (`kb_layout`/`kb_options` in
# modules/home/hyprland.nix) exactly as before.
#
# WHY AN EXPLICIT ID LIST AND NOT `*`. keyd decides a device is a keyboard if it
# carries all of 1-0/Q-Y *or any one of* KEY_BRIGHTNESSUP, KEY_VOLUMEUP,
# KEY_TOUCHPAD_TOGGLE, KEY_TOUCHPAD_OFF, KEY_MICMUTE — and its own source
# comments warn that this "will subsume anything that can emit these keys and
# may produce false positives". On this machine that wildcard would also grab
# `HP WMI hotkeys`, `Video Bus`, `Wireless hotkeys` and plausibly the ELAN
# touchpad, which would route the touchpad through keyd's virtual pointer and
# cost every libinput gesture. The two IDs below are the only devices anyone
# actually types on. Power and Sleep buttons are untouched either way: they
# carry neither a full keymap nor a media key, so keyd does not consider them
# keyboards and logind keeps seeing them directly.
#
# THE FAILURE MODE IS SAFE, which is the reason this is acceptable on a machine
# that is sometimes only reachable remotely. keyd grabs devices only once it is
# running with a valid config; if it fails to start, nothing is grabbed and both
# keyboards behave exactly as they do today. If it starts but misbehaves, SSH
# over the Netbird overlay (modules/nixos/remote.nix) does not pass through
# keyd at all, so `nixos-rebuild switch --rollback` is always reachable.
#
# Residual quirk, cosmetic only: `updateKeyboardsLeds` still pushes the
# event-source keyboard's LEDs to every keyboard, and the hotkey devices above
# are not merged, so pressing brightness while caps lock is on briefly blanks
# the caps LED until the next letter. The STATE is correct throughout; only the
# light flickers. Merging the hotkey devices too would fix it and widen the
# blast radius to the brightness/volume/rfkill path, which is not a trade worth
# making for an LED.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.keyboard;
in
{
  options.my.keyboard.mergeIds = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [
      "0001:0001"
      "1209:0002"
    ];
    description = ''
      `vendor:product` of every keyboard that should share ONE caps lock, num
      lock and layout. Empty disables keyd entirely.

      Read them from `/proc/bus/input/devices` (`I: Bus=.. Vendor=xxxx
      Product=xxxx`) or `keyd monitor`, and list ONLY devices that are really
      typed on — see the header comment for why `*` is the wrong answer here.

      A keyboard left off this list keeps its own independent caps lock and
      layout, which is the bug this module exists to remove. So when a new
      keyboard joins the machine, add it here; nothing will warn you.
    '';
  };

  config = lib.mkIf (cfg.mergeIds != [ ]) {
    services.keyd = {
      enable = true;

      keyboards.merged = {
        ids = cfg.mergeIds;

        # Empty on purpose — see the header. An empty `main` layer is identity:
        # every key is re-emitted as itself, and the only observable change is
        # that the devices above now present to the compositor as one keyboard.
        settings.main = { };
      };
    };
  };
}
