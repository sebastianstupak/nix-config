# home-manager configuration for user "sebastianstupak".
#
# `osConfig` is the NixOS-level config of the host this profile is attached to.
# home-manager passes it whenever it runs as a NixOS module, which is how this
# file reads the sops secret paths declared in hosts/zagreus/default.nix
# instead of repeating "/run/secrets/..." literals that nothing would check.
{ osConfig, ... }:
{
  imports = [ ../../modules/home ];

  home = {
    username = "sebastianstupak";
    homeDirectory = "/home/sebastianstupak";

    # The home-manager release this profile was created with. Keep in sync with
    # the host's system.stateVersion; do not bump it casually.
    stateVersion = "26.05";
  };

  # Calendar feeds to mirror locally, keyed by the short name that khal,
  # vdirsyncer and the directory under ~/.local/share/calendars all share. The
  # names are only meaningful on this machine — rename or add freely, but each
  # entry needs its own feed URL at ~/.config/vdirsyncer/<name>-url. Where to get
  # one per provider, and the rest of the setup: modules/home/calendar.nix.
  #
  # `meetings` is what the waybar counter counts. Leave it off for anything that
  # would inflate the number without being something you attend — birthdays,
  # public holidays, a subscribed fixtures feed.
  # The URLs come from sops rather than the default hand-installed
  # ~/.config/vdirsyncer/<name>-url. That default needs a manual step per machine
  # that no rebuild can reproduce, so a reinstall silently loses both feeds and
  # the bar's meeting counter goes quiet. Encrypted in git, they survive it.
  # A new calendar needs a matching secret in hosts/zagreus/default.nix.
  # One group per bar counter, each holding as many feeds as it needs. Feed names
  # are prefixed with where they come from, because that is the thing you need to
  # know when one of them stops updating — and the name is what shows up in
  # `systemctl --user status vdirsyncer`, in ~/.local/share/calendars/, and in
  # the hover when a group has more than one feed.
  #
  # Adding a feed: a key in secrets/common/calendars.yaml, a matching `sops.secrets`
  # entry in hosts/zagreus/default.nix, and a line here. Distinct icons are
  # the point of splitting the counts — two 󰃭 chips would be a puzzle — and both
  # of these are covered by JetBrainsMono NF (`fc-list ':charset=f00d6'`).
  my.calendars = {
    work = {
      icon = "󰃖"; # briefcase
      order = 10;
      feeds = {
        # Outlook/Teams, via Calendar settings ▸ Shared calendars ▸ Publish.
        outlook = {
          # Names the calendar in GNOME Calendar's sidebar, and tags events in
          # the bar tooltip once a group holds more than one feed.
          label = "Work (Outlook)";
          urlFile = osConfig.sops.secrets.calendar-work-url.path;
        };
        # outlook-team = {
        #   label = "Team";
        #   urlFile = osConfig.sops.secrets.calendar-work-team-url.path;
        # };
        # outlook-oncall = {
        #   meetings = false; # mirrored, but not something you attend
        #   urlFile = osConfig.sops.secrets.calendar-work-oncall-url.path;
        # };
      };
    };

    personal = {
      icon = "󰋜"; # house
      order = 20;
      feeds = {
        # Proton, via Calendar ▸ Settings ▸ Share ▸ Share with anyone.
        proton = {
          label = "Personal (Proton)";
          urlFile = osConfig.sops.secrets.calendar-personal-url.path;
        };
        # proton-family = {
        #   label = "Family";
        #   urlFile = osConfig.sops.secrets.calendar-family-url.path;
        # };
      };
    };

    # A group with meetings = false is mirrored for the week view and never gets
    # a counter — birthdays, public holidays, a fixtures feed.
    # holidays = {
    #   meetings = false;
    #   feeds.proton-holidays.urlFile = osConfig.sops.secrets.calendar-holidays-url.path;
    # };
  };

  # nettify runs on a different Claude account and subscription from everything
  # else on this machine. Declaring it here rather than in the module keeps the
  # module about the mechanism and this file about who I am — same split as
  # my.calendars above.
  #
  # No `directory`: the profile is named after the org, so it inherits
  # my.orgs.nettify.directory. That is what stops the Claude account and the
  # commit identity from ending up on two different paths.
  #
  # How the switch is enforced, and why it is a PATH wrapper rather than a
  # direnv .envrc: modules/home/claude-code-profiles.nix.
  my.claude.profiles.nettify = {
    # The addresses `/status` may report in that tree. While this was empty, any
    # account was accepted there — there is nothing to compare against before a
    # login has happened, so the wrapper routed by directory but refused
    # nothing. Set, `claude` refuses to start under ~/dev/nettify signed in as
    # anyone else, which is what stops that work from quietly landing on the
    # personal subscription (or the reverse).
    #
    # Two addresses, not one, and the order is meaningful only to a reader: the
    # dedicated agent account first because that is the canonical one the tree's
    # own bootstrap tells you to log in as, then the operator's own. Both are
    # nettify addresses on the nettify subscription, and both share this one
    # config dir — so this is two accepted identities for the tree, not two
    # profiles. Pinning only the first is what produced `claude: refusing to
    # start` on a tree that was legitimately signed in as the second.
    #
    # The tree's own agent harness checks this independently (its account-lock
    # hook reads the signed-in address out of the profile's own state and holds
    # the same allowlist in tools/nettify-profile.sh), so the two are
    # deliberately redundant: the hook catches a mis-login inside a session,
    # this refuses to start one at all. Keep the two lists in step — this one is
    # the harder lock, and it is outside that repo, so it wins.
    accounts = [
      "sebastian.ai@nettify.com"
      "sebastian.stupak@nettify.com"
    ];

    # Work-only MCP servers. They live in this profile's own .claude.json, so
    # Linear is reachable from every repo under ~/dev/nettify and from nowhere
    # else — no personal session can see the work tracker. Authorise once with
    # `/mcp` inside the profile; the handshake is interactive OAuth.
    mcpServers.linear = {
      type = "http";
      url = "https://mcp.linear.app/mcp";
    };

    # No `instructions`. ~/dev/nettify is now a git checkout of
    # github.com/sebastianstupak/nettify-rules, which tracks that CLAUDE.md
    # itself — along with the tree's hooks, shared skills and bootstrap. Seeding
    # from here would give one path two owners: activation only writes the file
    # when it is absent, so the tracked version wins in practice, but a checkout
    # that had not happened yet (or a deleted file) would silently get the stale
    # nix copy back and shadow the real rules.
    #
    # The Boundaries section that used to live here moved into that repo's
    # CLAUDE.md verbatim, so nothing was lost. Edit the rules there and commit
    # them; this module keeps only what the repo cannot know — which account and
    # which MCP servers the profile gets.
  };

  # The orgs this machine is used for. Directory is the boundary: anything under
  # ~/dev/<org>/ commits as that org (see modules/home/orgs.nix).
  #
  # One address for all of them, deliberately. Each org still pins it explicitly
  # instead of inheriting the global identity below, so that changing the global
  # address later does not silently re-author four orgs' worth of commits — the
  # answer to "who does this org commit as" stays written down per org.
  #
  # If an org ever needs its own address (a GitHub org that enforces a verified
  # company domain, a CLA that checks the author), change that one line; nothing
  # else moves.
  #
  # Each org owns a run of workspaces and wears one glyph in one colour across
  # all of them, so the bar reads as coloured groups: where you are, and which
  # of that org's screens you are on. The FIRST of each run is the org's home —
  # `org <name>` lands there and opens its terminal there; the rest are for
  # whatever wants its own screen, a browser or a running log.
  #
  # personal owns 1-3, and owning 1 is the point: that is where you land at
  # login, so the machine's resting state belongs to an org rather than to a
  # no-man's-land that everything unfiled drifts into. It gets three screens
  # because it is the one that also absorbs the odd jobs — this config, a
  # scratch shell, a browser opened to look one thing up.
  #
  # Work follows behind it, and 1-9 is exactly the range $mod+1..9 already
  # binds. Reordering is one line per org; nothing else depends on the numbers.
  # $mod+O picks an org; see modules/home/org.nix.
  #
  # Icons are checked against the bar's font before being used here (a missing
  # glyph renders as an empty box, which reads as a bug): each was rendered on
  # the real bar and looked at. Colours are base16 KEYS, not hex, so the orgs
  # follow the theme. base08 is deliberately unused — the bar spends it on
  # critical states, and an org permanently wearing the alarm colour would stop
  # the alarm meaning anything.
  my.orgs =
    let
      me = "sebastian.stupak@pm.me";
    in
    {
      datadir = {
        # The one org with an address of its own: datadir s.r.o. is a company,
        # and its commits should say so rather than carrying a personal mailbox
        # into a company history. This is exactly the case the per-org rules in
        # modules/home/git.nix exist for, and turning it on is this one line.
        #
        # THE ADDRESS MUST BE VERIFIED ON THE FORGEJO ACCOUNT at
        # https://git.datadir.dev/user/settings/account, or commits authored
        # with it show as belonging to no user — the avatar and the link go
        # missing, and `tea pr` attribution follows. Signatures are unaffected:
        # allowed_signers is regenerated from my.orgs at activation, so one key
        # keeps verifying for both identities.
        email = "sebastian.stupak@datadir.co";
        workspaces = [
          4
          5
        ];
        icon = "󰒋"; # server rack
        color = "base0D"; # blue
      };
      nettify = {
        email = me;
        workspaces = [
          6
          7
        ];
        icon = "󰖟"; # globe
        color = "base0E"; # mauve
      };
      bunny = {
        email = me;
        workspaces = [
          8
          9
        ];
        icon = "󰤇"; # rabbit
        color = "base0A"; # sand
      };
      personal = {
        email = me;
        workspaces = [
          1
          2
          3
        ];
        icon = ""; # none — personal is labelled with its numbers
        color = "base0B"; # green
      };
    };

  # One cockpit over every org's conversations: `gathr` attaches the TUI, a user
  # service keeps syncing when the terminal closes. Orgs, their glyphs and their
  # colours are generated from my.orgs above — see modules/home/gathr.nix.
  #
  # fixtures stays on until a real platform account exists: with no accounts the
  # daemon starts on an empty database, which looks identical to a broken
  # config. Turn it off in the same commit that adds the first real provider.
  # TEMP(gathr-empty-repo): the module providing these options is not imported
  # while inputs.gathr is commented out in flake.nix.
  # my.gathr = {
  #   enable = true;
  #   fixtures = true;
  # };

  # Per-user git identity (shared git config lives in modules/home/git.nix).
  programs.git.settings.user = {
    name = "sebastianstupak";
    email = "sebastian.stupak@pm.me";
  };
}
