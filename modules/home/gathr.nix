# gathr: one cockpit over every org's conversations.
#
# The daemon syncs and stores; `gathr` on its own attaches the TUI. Closing the
# terminal leaves sync running, which is the same reason herdr is a server and a
# client rather than one process — see modules/home/herdr.nix.
#
# Everything it knows about organisations comes from `my.orgs`, generated here
# rather than configured twice. An org that existed in gathr but not in my.orgs
# is exactly the drift that puts a reply in the wrong tenant, so there is one
# declaration and this file renders it.
#
# The source lives in its own repository (github.com/sebastianstupak/gathr) and
# arrives as a flake input, so a broken commit there cannot break this config
# until the lock is bumped deliberately.
#
# Adding a real account — getting a token, collecting channel ids, and what to do
# when a contract ends: docs/GATHR.md. This file is the option contract; that is
# the workflow.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.gathr;

  gathrPkg = inputs.gathr.packages.${pkgs.system}.default;

  # Every org gets a row, whether or not it has an account yet: an org that is
  # declared but unconnected must look different from one that is missing.
  orgs = lib.mapAttrsToList (name: org: {
    id = name;
    inherit name;
    inherit (org) color;
    # my.orgs calls it `icon`, gathr calls it `glyph`. Same glyph, and the
    # rename stays here rather than in either schema.
    glyph = org.icon;
  }) config.my.orgs;

  # Real accounts. The chat list is an allowlist, not a filter: a conversation
  # absent from here is never fetched and never stored, so adding one is a
  # deliberate act recorded in this repository's history.
  realProviders = lib.mapAttrsToList (name: acct: {
    type = acct.platform;
    id = "${acct.platform}:${name}";
    inherit (acct) org;
    token_file = acct.tokenFile;
    chats = map (c: {
      remote_id = c.remoteId;
      name = if c.name != null then c.name else c.remoteId;
      inherit (c) kind language;
      can_post = c.canPost;
    }) acct.chats;
  }) cfg.accounts;

  # Fixture accounts, so the layout can be judged with the real org names,
  # colours and glyphs rather than invented ones. Only for orgs with no real
  # account: once datadir has a Slack, fixture datadir traffic beside it would
  # be actively misleading.
  realOrgs = lib.mapAttrsToList (_: acct: acct.org) cfg.accounts;
  fixtureProviders = lib.optionals cfg.fixtures (
    lib.mapAttrsToList (name: _: {
      type = "fake";
      id = "fake:${name}";
      org = name;
      messages = 8;
    }) (lib.filterAttrs (name: _: !(lib.elem name realOrgs)) config.my.orgs)
  );

  configFile = (pkgs.formats.json { }).generate "gathr-config.json" {
    inherit orgs;
    providers = realProviders ++ fixtureProviders;
  };

  # gathr stores base16 KEYS and resolves them at render time, so the palette
  # comes from stylix here and the TUI re-colours with the system theme instead
  # of pinning one scheme. The same keys already colour the waybar org groups.
  themeFile =
    let
      colors = config.lib.stylix.colors;
      keys = [
        "base00"
        "base01"
        "base02"
        "base03"
        "base04"
        "base05"
        "base06"
        "base07"
        "base08"
        "base09"
        "base0A"
        "base0B"
        "base0C"
        "base0D"
        "base0E"
        "base0F"
      ];
    in
    (pkgs.formats.json { }).generate "gathr-theme.json" {
      palette = lib.genAttrs keys (k: "#${colors.${k}}");
    };

  socket = "%t/gathr/gathr.sock";
in
{
  options.my.gathr = {
    enable = lib.mkEnableOption "gathr, the multi-org chat cockpit";

    fixtures = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Give every org WITHOUT a real account a fixture one.

        On by default because otherwise a fresh install starts on an empty
        database, which is indistinguishable from a misconfiguration. Orgs that
        do have a real account never get fixtures, so real and invented
        conversations are never mixed in the same list.
      '';
    };

    accounts = lib.mkOption {
      default = { };
      description = ''
        Platform accounts, keyed by a short name that becomes part of the
        account id (`slack:<name>`).

        Adding one is the moment gathr starts holding a client's messages on
        this machine. The chat list below is an allowlist rather than a filter —
        anything not listed is never fetched and never written to disk — so the
        scope of that is decided here, in version control, rather than at
        runtime.
      '';
      example = lib.literalExpression ''
        {
          datadir = {
            org = "datadir";
            tokenFile = config.sops.secrets."gathr/datadir".path;
            chats = [
              { remoteId = "C01ABCDEF"; name = "platform-eng"; language = "en"; }
            ];
          };
        }
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            org = lib.mkOption {
              type = lib.types.str;
              description = ''
                Which org in `my.orgs` this account belongs to. The daemon
                refuses to start if it names an org that does not exist, rather
                than storing messages with no tenant.
              '';
            };

            platform = lib.mkOption {
              type = lib.types.enum [ "slack" ];
              default = "slack";
              description = ''
                Which provider implements this account. Only slack so far;
                teams and matrix are the intended next ones.
              '';
            };

            tokenFile = lib.mkOption {
              type = lib.types.str;
              description = ''
                Path to a file holding the user token (`xoxp-…`), read by the
                daemon at startup.

                A PATH, not a value: the token must never enter the generated
                config, which is world-readable in the Nix store. Point this at
                a sops-nix secret. Rotating it means restarting the service,
                not rebuilding.
              '';
            };

            chats = lib.mkOption {
              default = [ ];
              description = "The allowlisted conversations for this account.";
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    remoteId = lib.mkOption {
                      type = lib.types.str;
                      example = "C01ABCDEF";
                      description = ''
                        The platform's own id. For Slack, the channel id — open
                        the channel, "Copy link", and take the trailing segment.
                        A channel NAME is not stable; the id is.
                      '';
                    };

                    name = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = ''
                        Label shown in the UI. Null falls back to the id, which
                        is ugly but never wrong.
                      '';
                    };

                    kind = lib.mkOption {
                      type = lib.types.enum [
                        "channel"
                        "group"
                        "dm"
                      ];
                      default = "channel";
                      description = ''
                        Normalised shape, used for the glyph in the chat list.
                      '';
                    };

                    language = lib.mkOption {
                      type = lib.types.str;
                      default = "en";
                      description = ''
                        Language a drafted reply should be written in. Per chat
                        rather than per org: the same client can have an English
                        engineering channel and a Slovak DM.
                      '';
                    };

                    canPost = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      description = ''
                        Whether posting is permitted here at all.

                        False is not merely a default — no provider implements
                        the write interface yet, so nothing can post regardless.
                        Setting it true records the intent and shows it in the
                        assistant pane; it does not grant anything.
                      '';
                    };
                  };
                }
              );
            };
          };
        }
      );
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "15s";
      description = ''
        Poll period for accounts whose provider has no push channel. Providers
        that support streaming ignore this entirely.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Catch the mismatch at build time rather than at daemon startup: an account
    # naming an org that does not exist is a typo, and finding out from a failed
    # systemd unit after activation is a worse place to learn it.
    assertions = lib.mapAttrsToList (name: acct: {
      assertion = config.my.orgs ? ${acct.org};
      message =
        "my.gathr.accounts.${name}.org = \"${acct.org}\" is not declared in my.orgs "
        + "(have: ${lib.concatStringsSep ", " (lib.attrNames config.my.orgs)})";
    }) cfg.accounts;

    home.packages = [ gathrPkg ];

    # Config and theme are read-only store symlinks on purpose: both are
    # generated, and a writable copy would drift from my.orgs without saying so.
    xdg.configFile."gathr/config.json".source = configFile;
    xdg.configFile."gathr/theme.json".source = themeFile;

    systemd.user.services.gathr = {
      Unit = {
        Description = "gathr daemon (multi-org chat sync and API)";
        Documentation = "https://github.com/sebastianstupak/gathr";
        # The socket lives under $XDG_RUNTIME_DIR, so there is nothing to wait
        # for beyond the session itself.
        PartOf = [ "graphical-session.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = lib.concatStringsSep " " [
          "${gathrPkg}/bin/gathr daemon"
          "--config ${configFile}"
          "--socket ${socket}"
          "--interval ${cfg.interval}"
        ];

        # Restart on failure but not in a tight loop: a bad config fails
        # immediately every time, and a restart storm buries the real error in
        # the journal.
        Restart = "on-failure";
        RestartSec = "5s";

        # State lives under ~/.local/share/gathr by default; RuntimeDirectory
        # gives the socket a 0700 parent that systemd cleans up on exit, so a
        # stale socket never survives a crash.
        RuntimeDirectory = "gathr";
        RuntimeDirectoryMode = "0700";

        # This process holds other people's messages. Nothing here needs new
        # privileges, a writable /home beyond its own state, or a device.
        NoNewPrivileges = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        MemoryDenyWriteExecute = true;
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
