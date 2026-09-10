# Browsers: LibreWolf as the daily driver, Chromium for Playwright / cross-browser
# testing.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    librewolf
    chromium
  ];
}
