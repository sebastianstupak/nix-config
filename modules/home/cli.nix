# Everyday command-line tools.
{ pkgs, ... }:
{
  programs.bat.enable = true;
  programs.eza.enable = true;

  home.packages = with pkgs; [
    ripgrep # fast grep (rg)
    fd # fast find
    jq # JSON
    yq-go # YAML/JSON/XML
    tree
    btop # system monitor
    dust # disk usage
    ncdu # interactive disk usage
    unzip
    file
    wget
    curl
  ];
}
