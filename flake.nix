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

      # `nix flake check` runs this (verifies everything is formatted).
      checks.${system}.formatting = treefmtEval.config.build.check self;

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
