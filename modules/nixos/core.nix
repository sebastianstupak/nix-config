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

  # Some firmware/drivers are unfree. Comment out to stay fully free.
  nixpkgs.config.allowUnfree = true;

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

  # Minimal base tools available to every host, before any per-user config.
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    curl
  ];
}
