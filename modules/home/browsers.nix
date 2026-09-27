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
  # Staying logged in to a handful of sites is NOT configured here, and that is
  # deliberate — it cannot be. Recorded because the obvious fix is wrong and
  # costs an hour to find out.
  #
  # LibreWolf ships `privacy.sanitize.sanitizeOnShutdown = true`. It exempts
  # history by default but not cookies and storage, so every session dies on
  # exit. Two ways out:
  #
  #  * Per site, which is usually what you want: Settings > Privacy & Security >
  #    History > "Clear history when LibreWolf closes" > Manage Exceptions (or
  #    Ctrl+I > Permissions on the site itself). Microsoft needs both
  #    outlook.office.com and login.microsoftonline.com — the sign-in redirect
  #    lands on the latter.
  #
  #    This writes to permissions.sqlite, which no enterprise policy and no
  #    home-manager option can set, so it is imperative state: a reinstall loses
  #    it. That is the trade for not dropping the privacy default everywhere.
  #
  #  * Everywhere at once, which IS declarative — add to `settings` below:
  #      "privacy.clearOnShutdown_v2.cookiesAndStorage" = false;
  #
  # The trap: every guide says to add a COOKIE exception, or to use the
  # `Cookies.Allow` policy. That stopped working in Firefox 154 (bug 1767271),
  # and this is 155. Mozilla split the behaviour out into a dedicated
  # `persist-data-on-shutdown` permission, because a cookie ALLOW also disabled
  # Total Cookie Protection for those sites. Set a cookie exception today and
  # you will see the permission stored and still get logged out.
  programs.librewolf = {
    enable = true;
    profiles.default = {
      # uBlock Origin is NOT bundled in this build — checked, the distribution
      # ships no extensions at all, unlike LibreWolf's own binaries. So without
      # this line there is no content blocking beyond the built-in tracking
      # protection, which is a different and much narrower job.
      extensions.packages = [
        addons.ublock-origin
        addons.proton-pass
      ];

      # No fingerprinting overrides here, deliberately.
      #
      # LibreWolf's resistFingerprinting pins prefers-color-scheme to light so
      # the preference cannot be used to identify you, and it wins over every
      # pref that claims to change it. Measured on 155 against a page reporting
      # matchMedia, with RFP on: ui.systemUsesDarkTheme=1 gives light, and
      # layout.css.prefers-color-scheme.content-override=1 gives light. Both are
      # widely recommended and neither works.
      #
      # The only browser-wide way to dark pages is to give RFP up, and that was
      # tried and reverted: a dark website is not worth the strongest
      # anti-fingerprinting setting the browser has.
      #
      # So dark mode is per-site instead, set in each site's own account
      # settings. It costs nothing in fingerprinting, and it looks better than
      # any automatic inversion because the site designed the dark palette. The
      # chrome is already dark via stylix.

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
