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
  #
  # THIS MACHINE IS NOW SSHED INTO — see modules/nixos/remote.nix, which opens
  # port 22 on the Netbird interface and nothing else. It used to say the
  # opposite, and the hardening below is what makes that change a small one.
  #
  # openFirewall stays false regardless. Left at the defaults sshd would open
  # port 22 on every interface and accept passwords, which on a laptop that
  # joins café and hotel networks is a password-guessable service offered to
  # every stranger on the LAN. remote.nix opens it per-interface instead, so the
  # physical NICs still see a closed port. The service also has to run for the
  # host key to exist, which is what sops derives this machine's age key from.
  services.openssh = {
    enable = true;
    openFirewall = false;

    settings = {
      # Keys only. The single most important line here.
      PasswordAuthentication = false;

      # And the one people forget: with PAM in the stack, keyboard-interactive
      # is a SECOND password path that PasswordAuthentication = false does not
      # close. Leaving it on makes the line above decorative.
      KbdInteractiveAuthentication = false;

      # "no", not the "prohibit-password" default. There is no reason to reach
      # root directly when the user is a wheel member with sudo, and this way a
      # stolen root-authorized key is not a thing that can exist.
      PermitRootLogin = "no";

      # An allowlist of one. mutableUsers = false means the declared users are
      # the only users, but system accounts still exist and may gain shells as
      # packages come and go; this makes the set of accounts that can log in
      # over the network a deliberate choice rather than a consequence.
      AllowUsers = [ "sebastianstupak" ];

      # Refuse to forward the agent, which matters specifically BECAUSE of
      # modules/home/security.nix: gpg-agent there holds the ed25519 key that
      # signs commits. A forwarded agent is usable by anything with root on the
      # far end for as long as the connection is open — it signs as you without
      # the key ever leaving, which is precisely the problem. Each machine
      # already has its own key, so the alternative costs nothing. Listing all
      # of them in allowed_signers is how commits stay verifiable.
      AllowAgentForwarding = false;

      # TCP forwarding is deliberately LEFT ON (sshd's default). It is how the
      # Sunshine web UI is reached for pairing without exposing it on the
      # overlay at all — see origin_web_ui_allowed in remote.nix and the
      # `ssh -L` command in docs/REMOTE.md.

      X11Forwarding = false;

      # Both are near-irrelevant with passwords off, and both are free.
      MaxAuthTries = 3;
      LoginGraceTime = 30;
    };
  };
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
