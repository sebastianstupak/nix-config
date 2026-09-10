# Development tooling. Per-project toolchains still come from `nix develop` +
# nix-direnv (the reproducible way); the language packages below are a small
# always-available baseline for quick, throwaway work.
{ pkgs, ... }:
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  home.packages = with pkgs; [
    # tools
    gh # GitHub CLI
    lazygit # terminal git UI
    gnumake

    # language toolchains (baseline — prefer per-project devshells)
    go
    rustc
    cargo
    nodejs
    python3
    dotnet-sdk
  ];
}
