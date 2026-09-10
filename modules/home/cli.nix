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
    pandoc # document converter (PDF output needs a LaTeX engine, e.g. texliveSmall)
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
