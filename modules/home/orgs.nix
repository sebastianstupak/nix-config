# The organisations this person works under, and where each one's code lives.
#
# This file is only the DECLARATION. The list itself is data about this person
# and lives in home/<user>/default.nix, the same way my.calendars does.
#
# It exists because several unrelated things need the same answer to "which org
# is this?" and were each about to invent their own: commit identity
# (modules/home/git.nix), and — when they land — the Claude Code account a
# terminal should use, and which workspaces an org's apps open on.
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
          };
        }
      )
    );
  };
}
