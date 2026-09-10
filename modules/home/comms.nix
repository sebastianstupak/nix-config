# Communication apps.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    element-desktop # Matrix client
    zapzap # WhatsApp client (whatsapp-for-linux isn't in nixpkgs)
  ];
}
