# The organisations this person works under, and where each one's code lives.
#
# This file is only the DECLARATION. The list itself is data about this person
# and lives in home/<user>/default.nix, the same way my.calendars does.
#
# It exists because several unrelated things need the same answer to "which org
# is this?" and would otherwise each invent their own: commit identity
# (modules/home/git.nix), the Claude Code account and MCP servers a terminal
# gets (modules/home/claude-code-profiles.nix), and which workspace the org's
# apps open on (modules/home/org.nix).
#
# What an org gets, how to add one, and what still has to be done by hand on a
# new machine: docs/ORGS.md. This file is the option contract; that is the
# workflow.
#
# The boundary is a DIRECTORY, not a mode you switch into. Mode-switching setups
# fail the same way every time: you forget which mode you are in, and find out
# after pushing a commit authored by the wrong identity. A path cannot be
# forgotten — `git` and `direnv` both already resolve behaviour from it.
{
  config,
  lib,
  ...
}:
{
  options.my.orgs = lib.mkOption {
    default = { };
    example = lib.literalExpression ''
      {
        personal = { email = "me@example.com"; };
        acme = {
          email = "me@acme.example";
          directory = "/home/me/work/acme";
        };
      }
    '';
    description = ''
      Organisations keyed by short name. The name is used for the default
      directory, so keep it filesystem-friendly.
    '';
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            email = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Commit identity for repositories under this org's directory.

                Null means "not known yet": the org is listed, but repos under
                it keep the global identity rather than being attributed to a
                guess. Deliberate — a wrong address on a signed commit is worse
                than a generic one, and only shows up after it is pushed.

                Every address set here is also added to git's allowed_signers,
                or git reports its own commits as signed by an unknown signer.
              '';
            };

            directory = lib.mkOption {
              type = lib.types.str;
              default = "${config.home.homeDirectory}/dev/${name}";
              defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/dev/‹name›"'';
              description = ''
                Root of this org's checkouts. Everything beneath it is treated
                as belonging to the org, via git's `includeIf gitdir:`.
              '';
            };

            workspaces = lib.mkOption {
              type = lib.types.listOf lib.types.ints.positive;
              default = [ ];
              example = [
                2
                3
              ];
              description = ''
                Hyprland workspaces this org owns, in order. They are created at
                startup and named after the org, so the bar shows which org you
                are looking at rather than a number.

                The FIRST is the org's home: `org <name>` lands there and starts
                the terminal there. The rest are that org's other screens — a
                browser, docs, a long-running log — reachable with the ordinary
                $mod+N binds.

                An empty list keeps the org off the workspace layout entirely:
                it still gets a commit identity, a directory and its own
                assistant profile, it just has no screen of its own and does not
                appear in the `org` launcher.
              '';
            };

            icon = lib.mkOption {
              type = lib.types.str;
              default = "";
              example = "󰆼";
              description = ''
                Glyph shown on each of this org's workspaces in the bar, in
                place of the workspace number.

                Must exist in the bar's font — check before choosing, with
                `fc-list ':charset=<codepoint>' family`. A glyph the font does
                not have renders as an empty box, which looks like a bug rather
                than a missing icon.
              '';
            };

            color = lib.mkOption {
              type = lib.types.str;
              default = "base05";
              example = "base0D";
              description = ''
                base16 slot used to colour this org's workspace glyphs, as a
                scheme KEY rather than a hex value, so the orgs re-colour with
                the theme instead of pinning four colours from one scheme.

                base08-base0F are the accents. Avoid base08: the bar already
                uses it for critical states, and an org permanently wearing the
                alarm colour stops the alarm from meaning anything.
              '';
            };

            claudeProfile = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Give this org its own Claude Code profile: its own login and
                subscription, its own MCP servers, its own history and project
                state, used automatically by `claude` anywhere under
                `directory`.

                On by default because the failure it prevents is silent — work
                landing on a personal subscription, or a personal session
                holding a work tracker's OAuth token — and because nothing
                signals it at the time. The cost is one `/login` per org, once.

                Turn it off for an org that should just use the default account;
                repos under it then behave like any other directory. Details of
                the mechanism: modules/home/claude-code-profiles.nix.
              '';
            };

            apps = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = lib.literalExpression ''[ "chromium --profile-directory=Acme" ]'';
              description = ''
                Extra commands `org <name>` starts on the org's HOME workspace,
                alongside the terminal it opens there in `directory`.

                They run only when that workspace has none of our terminals on
                it yet, so running `org` again to switch back to a running org
                does not pile up a second copy of everything. A window that
                belongs to something else — a browser you opened there — does
                not count, and does not stop the org being set up.
              '';
            };
          };
        }
      )
    );
  };
}
