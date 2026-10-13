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
    # No claude-code here on purpose. The `claude` on PATH is the profile
    # wrapper from modules/home/claude-code-profiles.nix, which execs this same
    # package; installing the package as well would collide on bin/claude and
    # let a bare binary bypass the per-directory account enforcement.
    opentofu # infrastructure-as-code (FOSS Terraform fork; the `tofu` CLI)

    # language toolchains (baseline — prefer per-project devshells)
    go
    rustc
    cargo
    nodejs
    python3

    # dotnet-sdk_10, NOT the unversioned alias. The alias is 8.x in this
    # nixpkgs, and every maethril .NET repo pins 10.0.400 in global.json — so
    # with the alias on PATH, `dotnet` cannot build them AND the pre-commit
    # hook's `dotnet format` fails, which aborts the commit with no useful
    # message. Measured: the alias reports 8.0.424 and global.json resolution
    # refuses it.
    dotnet-sdk_10
  ];
}
