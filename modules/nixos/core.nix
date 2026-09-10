# Core system settings shared by every host: Nix daemon, flakes, GC, secrets, base tools.
{ pkgs, ... }:
{
  nix = {
    # Enable flakes + the new CLI declaratively, so the system agrees with how
    # this repo is built.
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Keep the store from growing without bound.
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    optimise.automatic = true;
  };

  # Compressed swap in RAM. There is no swap DEVICE on this machine —
  # hardware-configuration.nix is still the placeholder and its `swapDevices` is
  # empty — so before this the box had no swap at all, and a link step in a big
  # build (webkitgtk, chromium) could hand the whole session to the OOM killer
  # instead of pushing cold pages out.
  #
  # zram rather than a swapfile because it needs no partitioning and no decision
  # about where to put it: it trades a little CPU for effective capacity, which
  # is the right trade on a machine with cores to spare and 16G of RAM.
  #
  # This deliberately does NOT enable hibernation — you cannot resume from
  # compressed swap that lives in the RAM you just powered down. That needs a
  # real swap device sized to RAM plus a resume kernel arg, which is a per-host
  # disk-layout decision and belongs in hosts/<host>/ once the real hardware
  # config exists.
  zramSwap.enable = true;

  # Some firmware/drivers are unfree. Comment out to stay fully free.
  nixpkgs.config.allowUnfree = true;

  # Make zsh a valid login shell system-wide (configured per-user in home/).
  programs.zsh.enable = true;

  # --- Secrets (sops-nix) -------------------------------------------------
  # The age key used to decrypt secrets is derived from this host's SSH host key.
  # No secrets are declared yet, so this is currently a no-op. To add one, see
  # secrets/README.md. openssh is enabled so the host key exists to derive from.
  services.openssh.enable = true;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  # ------------------------------------------------------------------------

  # Locale / time — adjust to taste.
  time.timeZone = "Europe/Bratislava";
  i18n.defaultLocale = "en_US.UTF-8";

  # Monday-first weeks and a 24h clock, without moving the rest of the system
  # off en_US. Anything that draws a week takes the first weekday from LC_TIME's
  # first_weekday rather than from a setting of its own — GNOME Calendar's week
  # view (modules/home/calendar.nix), waybar's {calendar} tooltip, `cal`. en_US
  # answers Sunday, en_GB answers Monday and keeps the day/month names in
  # English (sk_SK is also Monday-first, but names them in Slovak). Verify with:
  #   LC_ALL=en_US.UTF-8 cal   ->  Su Mo Tu ...
  #   LC_ALL=en_GB.UTF-8 cal   ->  Mo Tu We ...
  # This also swaps %x to 10/09/26 and %X to 14:05:00; formats spelled out in
  # full (waybar's clock) are unaffected.
  i18n.extraLocaleSettings.LC_TIME = "en_GB.UTF-8";

  # supportedLocales is an allowlist of what actually gets built into the locale
  # archive, and its default only covers defaultLocale. A locale missing from it
  # silently degrades to C — which is Sunday-first, i.e. exactly the thing
  # LC_TIME above is meant to fix — so the two options have to move together.
  i18n.supportedLocales = [
    "C.UTF-8/UTF-8"
    "en_US.UTF-8/UTF-8"
    "en_GB.UTF-8/UTF-8"
  ];

  # Minimal base tools available to every host, before any per-user config.
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    curl
  ];
}
