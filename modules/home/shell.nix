# Interactive shell: zsh with the starship prompt, plus fzf and zoxide.
{ ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history = {
      size = 100000;
      save = 100000;
      ignoreDups = true;
      share = true;
    };
    shellAliases = {
      ls = "eza --icons";
      ll = "eza -l --git --icons";
      la = "eza -la --git --icons";
      cat = "bat";
      # Rebuild helpers for this repo (run from the repo root).
      rebuild = "sudo nixos-rebuild switch --flake .#workstation";
      rebuild-boot = "sudo nixos-rebuild boot --flake .#workstation";
    };
  };

  programs.starship.enable = true;

  # Smarter cd + fuzzy finder, wired into zsh.
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };
}
