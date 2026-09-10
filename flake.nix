{
  description = "sebastianstupak's NixOS configuration (flake-based, single-host laptop)";

  inputs = {
    # Track the current stable release. Bump deliberately with `nix flake update`
    # in its own commit (see AGENTS.md). Switch to nixos-unstable for freshness.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management. Encrypted files under secrets/ are committed; they are
    # decrypted at activation time into /run/secrets. See secrets/README.md.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Formatter runner: drives `nix fmt` and the `formatting` flake check.
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # System-wide theming (base16 scheme -> GTK/Qt/terminal/editor/bar/etc).
    # Pin to the release branch matching nixpkgs, or targets drift against
    # option renames (e.g. regreet moving under services.displayManager).
    stylix = {
      url = "github:nix-community/stylix/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative Firefox/LibreWolf add-ons (rycee's NUR firefox-addons set).
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Ableton Live + Push on Linux (patched Wine + PipeASIO + Link). Deliberately
    # NOT following our nixpkgs — its patched Wine is built against its own pinned
    # nixos-unstable; forcing follows would break that build. See modules/nixos/audio.nix.
    ableton-linux.url = "github:shibco/ableton-linux";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      sops-nix,
      treefmt-nix,
      stylix,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # nixfmt-rfc-style via treefmt (see treefmt.nix).
      treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

      # Build a NixOS system from a host module. Shared modules (home-manager,
      # sops-nix) are wired in once here, and `inputs` is threaded to every
      # module via specialArgs. Add a machine by dropping a hosts/<name>/ dir
      # and one line under nixosConfigurations below.
      mkHost =
        hostModule:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            hostModule
            home-manager.nixosModules.home-manager
            sops-nix.nixosModules.sops
            stylix.nixosModules.stylix
          ];
        };
    in
    {
      nixosConfigurations = {
        # nixos-rebuild switch --flake .#workstation
        workstation = mkHost ./hosts/workstation;
        # add more machines here, e.g.:  desktop = mkHost ./hosts/desktop;
      };

      # `nix fmt` — format the whole tree with nixfmt-rfc-style.
      formatter.${system} = treefmtEval.config.build.wrapper;

      # `nix flake check` runs these.
      checks.${system} = {
        # verifies everything is formatted
        formatting = treefmtEval.config.build.check self;

        # Validate the generated Hyprland config with Hyprland's own offline
        # checker — `--verify-config` parses and reports errors (unknown
        # dispatchers, bad binds, unclosed blocks) and exits non-zero on failure,
        # so a broken config fails `nix flake check` before it reaches the machine.
        hyprland-config =
          pkgs.runCommand "hyprland-verify-config" { nativeBuildInputs = [ pkgs.hyprland ]; }
            ''
              export HOME="$TMPDIR"
              export XDG_RUNTIME_DIR="$TMPDIR"
              Hyprland --config ${
                self.nixosConfigurations.workstation.config.home-manager.users.sebastianstupak.xdg.configFile."hypr/hyprland.conf".source
              } --verify-config
              touch $out
            '';

        # Same idea for the launcher: fuzzel rejects unknown keys and malformed
        # colors, so validate the generated fuzzel.ini instead of finding out
        # when $mod+R silently does nothing.
        fuzzel-config = pkgs.runCommand "fuzzel-check-config" { nativeBuildInputs = [ pkgs.fuzzel ]; } ''
          export HOME="$TMPDIR"
          export XDG_RUNTIME_DIR="$TMPDIR"
          fuzzel --config ${
            self.nixosConfigurations.workstation.config.home-manager.users.sebastianstupak.xdg.configFile."fuzzel/fuzzel.ini".source
          } --check-config
          touch $out
        '';

        # The global commit-msg policy (modules/home/git-hooks.nix) rewrites and
        # rejects commit messages, so a regression either mangles real messages
        # or silently lets attribution through. Drive the installed hook via
        # actual `git commit` runs in throwaway repos rather than calling the
        # script directly — that also exercises the dispatcher's delegation.
        git-hook-policy =
          pkgs.runCommand "git-hook-policy-test"
            {
              nativeBuildInputs = [
                pkgs.git
                pkgs.coreutils
              ];
            }
            ''
              export HOME="$TMPDIR"
              hooks="${
                self.nixosConfigurations.workstation.config.home-manager.users.sebastianstupak.xdg.configFile."git/hooks/commit-msg".source
              }"

              git config --global user.email t@example.com
              git config --global user.name tester
              git config --global init.defaultBranch main
              git config --global commit.gpgsign false

              # Install the dispatcher the way it is really used — as a global
              # core.hooksPath — rather than copying it into .git/hooks. Copying it
              # there makes it its own delegation target and it recurses.
              mkdir -p "$TMPDIR/globalhooks"
              install -m755 "$hooks" "$TMPDIR/globalhooks/commit-msg"
              git config --global core.hooksPath "$TMPDIR/globalhooks"

              fresh() {
                rm -rf "$TMPDIR/r"; mkdir -p "$TMPDIR/r"; cd "$TMPDIR/r"
                git init -q .
                echo x > f; git add f
              }

              fail() { echo "FAIL: $1" >&2; exit 1; }

              # --- 1. attribution trailer is stripped, commit still succeeds ---
              fresh
              printf 'feat: thing\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n' > m
              git commit -q -F m || fail "trailer-only message should commit"
              got="$(git log -1 --pretty=%B)"
              case "$got" in *Co-Authored-By*) fail "trailer survived: $got";; esac
              case "$got" in *"feat: thing"*) : ;; *) fail "subject lost: $got";; esac
              echo "  ok: Co-Authored-By stripped, subject preserved"

              # --- 2. Claude-Session and Generated with are stripped too ---
              fresh
              printf 'fix: y\n\n🤖 Generated with [Claude Code](https://claude.com)\nClaude-Session: https://x\n' > m
              git commit -q -F m || fail "generated-with message should commit"
              got="$(git log -1 --pretty=%B)"
              case "$got" in *Generated*|*Claude-Session*) fail "not stripped: $got";; esac
              echo "  ok: Generated-with / Claude-Session stripped"

              # --- 3. a prose mention is REJECTED, not silently rewritten ---
              fresh
              printf 'feat: ask claude about it\n' > m
              if git commit -q -F m 2>/dev/null; then fail "prose mention should be rejected"; fi
              test -z "$(git log --oneline 2>/dev/null)" || fail "commit was created despite rejection"
              echo "  ok: prose mention rejected"

              # --- 4. case-insensitivity ---
              fresh
              printf 'chore: bump ANTHROPIC sdk\n' > m
              if git commit -q -F m 2>/dev/null; then fail "uppercase mention should be rejected"; fi
              echo "  ok: rejection is case-insensitive"

              # --- 5. an ordinary message is untouched, byte for byte ---
              fresh
              printf 'refactor(core): split the parser\n\nBody line.\n\nCo-Authored-By: Ada <ada@example.com>\n' > m
              git commit -q -F m || fail "clean message should commit"
              got="$(git log -1 --pretty=%B)"
              case "$got" in *"Co-Authored-By: Ada"*) : ;; *) fail "human co-author was stripped: $got";; esac
              case "$got" in *"Body line."*) : ;; *) fail "body lost: $got";; esac
              echo "  ok: unrelated message and human co-author preserved"

              # --- 6. dispatcher delegates to a repo-local hook ---
              # printf, not a heredoc: this is inside a Nix indented string,
              # which would keep the body's relative indentation and break the
              # shebang.
              fresh
              mkdir -p .git/hooks
              printf '%s\n' '#!/bin/sh' 'grep -q FORBIDDEN "$1" && exit 1' 'exit 0' \
                > .git/hooks/commit-msg
              chmod +x .git/hooks/commit-msg
              printf 'feat: FORBIDDEN token\n' > m
              if git commit -q -F m 2>/dev/null; then fail "delegated hook should have rejected"; fi
              echo "  ok: dispatcher delegates to a repo-local hook"

              # ...and the delegate still runs for messages the policy allows.
              printf 'feat: allowed token\n' > m
              git commit -q -F m || fail "clean message should pass both policy and delegate"
              echo "  ok: delegation does not block clean commits"

              # --- 7. self-delegation must not recurse ---
              # Put the dispatcher at the repo hook path too; the guard should stop
              # it re-entering itself instead of hanging.
              fresh
              mkdir -p .git/hooks
              install -m755 "$hooks" .git/hooks/commit-msg
              printf 'feat: safe subject\n' > m
              timeout 30 git commit -q -F m || fail "self-delegation recursed or failed"
              echo "  ok: self-delegation guard holds"

              echo "all git-hook policy tests passed"
              touch $out
            '';

        # Waybar has no --verify-config equivalent (see `waybar --help`), and its
        # config is generated from Nix so it is JSON-valid by construction. The
        # part that can actually break is the hand-written CSS in
        # modules/home/waybar.nix: GTK does not abort on a bad rule, it logs to
        # stderr and skips it, so a typo silently drops styling rather than
        # failing. This runs the same GTK3 parser waybar itself uses and treats
        # any parsing-error as fatal.
        #
        # Built as a 20-line C program rather than via PyGObject on purpose: the
        # introspection route needs Gtk-3.0 plus a transitive typelib chain
        # (gdk-pixbuf, pango, atk, and xlib-2.0 from xorgproto) wired through
        # GI_TYPELIB_PATH, while linking gtk3 directly needs nothing but gtk3 —
        # which is already in the closure as a waybar dependency.
        waybar-style =
          pkgs.runCommand "waybar-check-style"
            {
              nativeBuildInputs = [
                pkgs.pkg-config
                pkgs.gcc
              ];
              buildInputs = [ pkgs.gtk3 ];
            }
            ''
              cat > cssck.c <<'EOF'
              #include <gtk/gtk.h>
              static int failed = 0;
              static void on_err(GtkCssProvider *p, GtkCssSection *s, GError *e, gpointer d) {
                (void)p; (void)d;
                g_printerr("CSS error at line %u: %s\n",
                           gtk_css_section_get_start_line(s) + 1, e->message);
                failed = 1;
              }
              int main(int argc, char **argv) {
                if (argc < 2) return 2;
                GtkCssProvider *p = gtk_css_provider_new();
                g_signal_connect(p, "parsing-error", G_CALLBACK(on_err), NULL);
                GError *err = NULL;
                gtk_css_provider_load_from_path(p, argv[1], &err);
                if (err) { g_printerr("load failed: %s\n", err->message); failed = 1; }
                return failed;
              }
              EOF
              gcc cssck.c -o cssck $(pkg-config --cflags --libs gtk+-3.0)

              # Prove the checker has teeth before trusting its verdict — an
              # always-passing check is worse than none.
              echo '#x { color: ; }' > bad.css
              if ./cssck bad.css; then
                echo "cssck accepted invalid CSS; the check is broken" >&2
                exit 1
              fi

              ./cssck ${
                self.nixosConfigurations.workstation.config.home-manager.users.sebastianstupak.xdg.configFile."waybar/style.css".source
              }
              touch $out
            '';
      };

      # `nix develop` (or `direnv allow` via .envrc) — dev tooling for this repo:
      # the Nix linters/formatter, lefthook, and the secrets CLIs. The shellHook
      # activates the committed .githooks/ (idempotent, no-op outside a git repo).
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nixfmt-rfc-style # formatter (matches treefmt.nix / `nix fmt`)
          deadnix # find dead/unused Nix code
          statix # lint Nix antipatterns
          lefthook # git hooks runner (invoked by .githooks/)
          sops # edit encrypted secrets
          ssh-to-age # derive age keys from SSH keys
        ];
        shellHook = ''
          if [ -e .git ]; then
            git config core.hooksPath .githooks
          fi
        '';
      };
    };
}
