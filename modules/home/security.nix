# GPG / secrets tooling. gpg-agent runs with a graphical pinentry (works under
# Hyprland/Wayland) and doubles as the SSH agent. Set a signing key in git via
# programs.git.settings.user.signingKey + commit.gpgsign when you have one.
{ pkgs, ... }:
{
  programs.gpg.enable = true;

  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry-gnome3;
    enableSshSupport = true;
    defaultCacheTtl = 3600;
  };

  home.packages = with pkgs; [
    age # file encryption (also used by sops-nix)
  ];
}
