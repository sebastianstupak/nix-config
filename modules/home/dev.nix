# Development tooling. Language toolchains come from per-project `nix develop`
# shells (nix-direnv auto-loads them); this is the always-available baseline.
{ pkgs, ... }:
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  home.packages = with pkgs; [
    gh # GitHub CLI
    lazygit # terminal git UI
    gnumake
  ];
}
