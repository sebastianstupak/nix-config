# Editors: neovim as the terminal $EDITOR (git commits, quick edits), Zed as the
# GUI editor.
{ ... }:
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  programs.zed-editor = {
    enable = true;
    userSettings = {
      telemetry = {
        metrics = false;
        diagnostics = false;
      };
    };
  };
}
