# Proton suite (native Linux apps). Proton Drive and Calendar have no native
# Linux client — reach them via the browser (see bookmarks) or rclone for Drive.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    proton-pass # password manager (desktop app; browser extension added separately)
    proton-vpn # official Proton VPN client (was protonvpn-gui)
    protonmail-desktop # official Proton Mail desktop app
    # protonmail-bridge  # alternative: IMAP/SMTP bridge for Thunderbird/neomutt
  ];
}
