# Development tooling. Per-project toolchains still come from `nix develop` +
# nix-direnv (the reproducible way); the language packages below are a small
# always-available baseline for quick, throwaway work.
{ osConfig, pkgs, ... }:
let
  # ONE dotnet ROOT HOLDING BOTH SDKs, not two packages. dotnet-sdk_10 and
  # dotnet-sdk_8 each install bin/dotnet, so listing both collides at profile
  # build time and one of them silently wins. combinePackages merges their
  # share/dotnet trees instead, so a single `dotnet` sees sdk 10.0.400 and
  # 8.0.424 side by side and resolves global.json per repository: 10.0.400
  # here, 10 by default where nothing is pinned, 8 only when a project asks.
  #
  # Verified rather than assumed, with this exact derivation: `dotnet
  # --list-sdks` reports both, `dotnet --version` is 10.0.400 inside a repo
  # pinning it AND in a directory with no global.json, and a net8.0 console
  # project builds and runs.
  dotnetSdks = pkgs.dotnetCorePackages.combinePackages [
    pkgs.dotnet-sdk_10
    pkgs.dotnet-sdk_8
  ];

  # GODOT WITH THAT SAME COMBINED ROOT, AND THE OVERRIDE IS THE WHOLE POINT.
  # The stock wrapper prepends a dotnet 8 SDK to PATH, which is where Godot's
  # embedded host looks for a runtime — so an editor opening a net10.0 project
  # builds it and then fails to load the assembly: "Could not load file or
  # assembly 'System.Runtime, Version=10.0.0.0'". Pointing it at a dotnet 10
  # SDK alone fails the other way, because the editor's own build integration
  # (GodotTools) is net8.0 with rollForward LatestMinor and then finds no sdk
  # at all. Both runtimes have to be present: GodotPlugins is LatestMajor and
  # takes the 10, GodotTools takes the 8.
  #
  # overrideAttrs on the wrapper, which is cheap — nixpkgs does the same thing
  # in this package's own `sdk-override` test — so the engine itself still
  # comes from the binary cache rather than a source build.
  #
  # Pinned to 4.7 deliberately: godot_4-mono is 4.6.3 in this nixpkgs, while
  # the platform repo's starter project declares Godot 4.7 and Godot.NET.Sdk
  # 4.7.0. Verified by running this derivation headless over that starter —
  # it builds the solution and loads the net10.0 assembly with no error.
  godot = pkgs.godot_4_7-mono.overrideAttrs { dotnet-sdk = dotnetSdks; };

  # The MONO templates, matching that editor. Exporting a C# game needs the
  # .mono set; the plain one produces "export templates are missing" on a
  # project with an assembly. Same version string as the editor reports
  # (4.7.2.stable.mono) because Godot looks the directory up by that exact
  # name and silently offers to download when it is absent.
  godotTemplates = pkgs.godotPackages_4_7.export-templates-mono-bin;

  # THE WOODPECKER CLI UNDER THE NAME THE TOOLING ACTUALLY CALLS IT. The package
  # installs two names and `woodpecker` prints "calling `woodpecker` is
  # deprecated, use `woodpecker-cli`" on stderr, so exec the latter; every
  # runbook and script in the
  # temnir repo says `wp` — tools/ci/pr-wait.sh resolves it with `command -v wp`
  # and otherwise falls back to a stale `~/bin/wp.exe` from a WSL era. A shell
  # ALIAS cannot fix that: `task ci:watch` runs the script through plain sh,
  # where aliases do not exist. Only a real binary on PATH works from both.
  #
  # The wrapper also supplies the credentials rather than the session exporting
  # them. WOODPECKER_TOKEN in `home.sessionVariables` would sit in the
  # environment of every process on the machine — one `cat /proc/<pid>/environ`
  # from any of them — and would still be the value captured at login, so a
  # rotated token needs a new session. Reading the sops path per invocation
  # costs nothing and has neither problem.
  #
  # Both are overridable: an already-set WOODPECKER_SERVER/TOKEN wins, so a
  # second instance or a short-lived token can be used without editing this.
  wp = pkgs.writeShellScriptBin "wp" ''
    set -eu
    : "''${WOODPECKER_SERVER:=https://ci.datadir.dev}"
    export WOODPECKER_SERVER
    if [ -z "''${WOODPECKER_TOKEN:-}" ]; then
      tokenFile=${osConfig.sops.secrets.woodpecker-token.path}
      if [ -r "$tokenFile" ]; then
        WOODPECKER_TOKEN="$(cat "$tokenFile")"
        export WOODPECKER_TOKEN
      else
        echo "wp: no token at $tokenFile — is the secret declared and the machine rebuilt?" >&2
      fi
    fi
    exec ${pkgs.woodpecker-cli}/bin/woodpecker-cli "$@"
  '';
in
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # WHERE GODOT LOOKS, WHICH IS NOT A PATH IT CAN BE TOLD. The editor reads
  # $XDG_DATA_HOME/godot/export_templates/<version>/ and has no setting for it,
  # so the templates are linked into place rather than installed as a package.
  # Without this the first export opens the download dialog and writes an
  # unmanaged copy into the home directory — which then survives every rebuild
  # and ages out of step with the editor.
  xdg.dataFile."godot/export_templates/4.7.2.stable.mono".source =
    "${godotTemplates}/share/godot/export_templates/4.7.2.stable.mono";

  home.packages = with pkgs; [
    # tools
    gh # GitHub CLI
    lazygit # terminal git UI

    # Forgejo CLI — `tea`, how pull requests on git.datadir.dev are managed.
    # The instance has SSH disabled and no web access worth scripting, so
    # `tea pr create/list/merge` is the only PR path; see the temnir repo's
    # CLAUDE.md, which mandates it over a browser.
    #
    # UNLIKE EVERY OTHER CREDENTIAL HERE, tea's cannot be made declarative.
    # `tea logins add` VALIDATES the token against the live server before it
    # writes ~/.config/tea/config.yml, so it cannot run at activation (NetBird
    # may be down, and a rejected token writes nothing) — and tea ignores
    # GITEA_SERVER_URL/TOKEN unless a stored login already exists, so a wrapper
    # like `wp` below would not work either. Both verified against tea 0.14.
    # It is therefore a one-time manual step per machine: docs/ORGS.md.
    tea
    wp # the Woodpecker CLI, renamed + credentialed — see above
    gnumake
    # No claude-code here on purpose. The `claude` on PATH is the profile
    # wrapper from modules/home/claude-code-profiles.nix, which execs this same
    # package; installing the package as well would collide on bin/claude and
    # let a bare binary bypass the per-directory account enforcement.
    opentofu # infrastructure-as-code (FOSS Terraform fork; the `tofu` CLI)

    # Azure CLI — read-only estate inspection (role assignments, container apps,
    # log-analytics queries) that `tofu` cannot answer because it only ever sees
    # what is in state. Here rather than in a devshell because `az` keeps its
    # login, subscription and extensions in ~/.azure: a per-repository shell
    # would re-authenticate on every entry and still write to that same home.
    #
    # EXTENSIONS ARE NOT PART OF THIS PACKAGE and cannot be. `az containerapp`,
    # which is what the Container Apps estate actually needs, is an extension az
    # installs at runtime into ~/.azure/cliextensions — the nix store is
    # read-only, so it lands in the home directory either way:
    #   az extension add --name containerapp
    azure-cli

    # Teleport client — `tsh`, the bastion the estate is reached through. Here
    # rather than in a devshell for the same reason as azure-cli: `tsh` keeps
    # its cluster profile and short-lived certificates in ~/.tsh, so a
    # per-repository shell would re-login on every entry and still write to
    # that same home.
    #
    # THE UNVERSIONED ATTR IS A MOVING MAJOR — it is teleport_18 (18.10.0) in
    # this nixpkgs, alongside teleport_16/_17. A Teleport client must be no
    # older than the cluster's advertised `min_client_version` and no newer
    # than its major; so when a `tsh login` starts refusing on version, read
    # the real numbers from the cluster rather than guessing:
    #   curl -s https://<proxy>/webapi/ping | jq '{server_version, min_client_version}'
    # and pin `teleport_<major>` here if the alias has drifted past it.
    teleport

    # language toolchains (baseline — prefer per-project devshells)
    go
    rustc
    cargo
    nodejs
    python3

    # NEVER the unversioned `dotnet-sdk` alias. It is 8.x in this nixpkgs, and
    # every maethril .NET repo pins 10.0.400 in global.json — so with the alias
    # on PATH, `dotnet` cannot build them AND the pre-commit hook's `dotnet
    # format` fails, which aborts the commit with no useful message. Measured:
    # the alias reports 8.0.424 and global.json resolution refuses it. The
    # combined root above names both versions explicitly for that reason.
    dotnetSdks

    # game engines — the client half of the maethril platform. Both are here
    # rather than in a devshell because an editor is a desktop application
    # with its own state directory, not something a repository enters.
    godot
    # UNITY HUB ONLY; THE EDITOR IS NOT A NIX PACKAGE. The hub is an FHS
    # environment, so editors it installs under ~/Unity run inside it. Install
    # the version a project names — the platform repo's starter says
    # 6000.0.58f1 in ProjectVersion.txt — with
    #   unityhub --headless install --version <v> --changeset <hash>
    # or from the GUI, which is also where signing in for a licence happens.
    # Unity will not open a project without one, and no amount of packaging
    # changes that. Unfree; allowUnfree is already set in modules/nixos/core.nix.
    unityhub
  ];
}
