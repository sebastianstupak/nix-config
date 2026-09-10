# Browsers, managed declaratively so the Proton Pass extension and Proton
# bookmarks are reproducible. LibreWolf is the daily driver; Chromium is for
# Playwright / cross-browser testing. Firefox add-ons come from rycee's NUR set.
{ inputs, pkgs, ... }:
let
  addons = inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system};

  # Proton web apps — Drive and Calendar have no Linux client, so they live here;
  # Mail/Pass/VPN have native apps but the web bookmarks are handy too.
  protonBookmarks = [
    {
      name = "Proton Mail";
      url = "https://mail.proton.me";
    }
    {
      name = "Proton Calendar";
      url = "https://calendar.proton.me";
    }
    {
      name = "Proton Drive";
      url = "https://drive.proton.me";
    }
    {
      name = "Proton Pass";
      url = "https://pass.proton.me";
    }
    {
      name = "Proton VPN";
      url = "https://account.protonvpn.com";
    }
  ];
in
{
  programs.librewolf = {
    enable = true;
    profiles.default = {
      extensions.packages = [ addons.proton-pass ];
      bookmarks = {
        force = true;
        settings = protonBookmarks;
      };
    };
  };

  # Tell Stylix which LibreWolf profile(s) to theme.
  stylix.targets.librewolf.profileNames = [ "default" ];

  programs.chromium = {
    enable = true;
    extensions = [
      { id = "ghmbeldphafepmbegfdlkpapadhbakde"; } # Proton Pass
    ];
  };
}
