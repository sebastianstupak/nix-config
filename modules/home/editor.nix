# Editor: neovim as the default $EDITOR. Kept minimal — extend to taste.
{ ... }:
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };
}
