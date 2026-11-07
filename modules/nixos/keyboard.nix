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
# AND THERE IS A SECOND BUG, which is the one that actually produces "caps lock
# is on every time I connect" and "I set caps on in one pane and it is off in
# this one". It is NOT the per-device divergence above, and merging the devices
# does not fix it by itself.
#
# `CSeatManager::setKeyboardFocus` ORs EVERY keyboard's CACHED locked state into
# the modifiers it hands the newly focused surface:
#
#   uint32_t locked = m_keyboard->m_modifiersState.locked;
#   for (auto const& kb : g_pInputManager->m_keyboards) { ... locked |= kb->m_modifiersState.locked; }
#   k->sendMods(depressed, latched, locked, m_keyboard->m_modifiersState.group);
#
# So one keyboard with a stale cache tells EVERY window, every time it takes
# focus, that Caps Lock is down. The window then believes that until a real
# modifier event arrives, because `sendKeyboardKey` does not resend mods and
# `onKeyboardMod` only fires when modifiers actually change. Which is exactly
# "it doesn't work right away" — you type capitals until you happen to press a
# modifier — and exactly why two windows disagree: each holds whatever it was
# last told.
#
# Measured on zagreus 2026-11-07 with `wev` focused: on enter it received
# `locked: 00000012: Lock Mod2` while `keyd-virtual-keyboard` reported
# `capsLock: no, numLock: no`. Mod2 is Num Lock, and nothing else on the machine
# had it set, so it can only have come from `at-translated-set-2-keyboard`'s
# frozen `caps=True num=True`.
#
# WHAT MAKES A CACHE STALE IS THIS MODULE. `m_modifiersState` is refreshed only
# by `updateModifiersState()`, which runs on events FROM that device. Once keyd
# grabs a keyboard, Hyprland never receives another event from it, so whatever
# was in that cache at the moment of the grab is frozen there permanently. A
# laptop keyboard that had Caps Lock on when keyd first started will inject a
# phantom Caps Lock into every window, forever.
#
# It is therefore self-correcting ONLY from a clean start: with keyd already
# running, Hyprland builds each grabbed keyboard with `m_modifiersState` zeroed
# and nothing can ever change it, so no phantom can form. The order matters, not
# the config.
#
# CLEARING ONE THAT IS ALREADY FROZEN NEEDS A NEW DEVICE OBJECT. A keymap change
# does NOT do it — `updateXKBTranslationState` builds a fresh `xkb_state` but
# never touches `m_modifiersState`, and the block that would re-derive it is
# gated behind `input:numlock_by_default` (0 here). So `hyprctl keyword
# input:kb_options ...` clears the live state and leaves the cache lying, which
# is a trap worth knowing: the live state and the reported state disagree.
# What works is a fresh login, or destroying and re-creating the device node,
# which keeps the session:
#
#   echo -n serio0 | sudo tee /sys/bus/serio/drivers/atkbd/unbind
#   echo -n serio0 | sudo tee /sys/bus/serio/drivers/atkbd/bind
#
# NOT FIXED with `device { name = ...; enabled = false; }` on the grabbed
# keyboards, though that would make the phantom structurally impossible — the
# enter loop skips `!kb->m_enabled`. `onKeyboardKey` also drops events from a
# disabled keyboard, so a keyd that failed to start would leave this machine
# with NO working built-in keyboard rather than a working un-merged one. That
# trades a cosmetic-but-maddening bug for a lockout on a machine that is
# sometimes only reachable over the network. Not worth it; the clean-start
# property above covers it.
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
