# Interactive shell: zsh with the starship prompt, plus fzf and zoxide.
{ lib, ... }:
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

    # Tab accepts the grey zsh-autosuggestions ghost text (upstream only binds
    # forward-char / End for that), and otherwise behaves like plain Tab.
    # POSTDISPLAY is where zsh-autosuggestions parks the pending suggestion, so
    # an empty one means "nothing to accept". Delegate via `zle` rather than
    # reimplementing: both target widgets are already wrapped by the plugin, so
    # the next suggestion is refetched for us. Ordered late so the plugin is
    # sourced before we reference its widget.
    initContent = lib.mkOrder 1500 ''
      _accept-autosuggestion-or-complete() {
        if [[ -n "$POSTDISPLAY" ]]; then
          zle autosuggest-accept
        else
          zle expand-or-complete
        fi
      }
      zle -N _accept-autosuggestion-or-complete
      bindkey '^I' _accept-autosuggestion-or-complete
    '';
  };

  programs.starship = {
    enable = true;

    # Otherwise starship runs on its stock config — Stylix only writes the
    # colour palette into starship.toml, never a `format` — and the stock
    # config includes a battery module that appears below 10% and shows a
    # coloured glyph plus the percentage in the prompt.
    #
    # Off rather than restyled: the bar already has a battery module with
    # warning/critical colours, and a prompt that changes shape when the
    # laptop is low is exactly when you least want the line you are typing on
    # to move.
    settings.battery.disabled = true;
  };

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
