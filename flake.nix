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
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      sops-nix,
      treefmt-nix,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # nixfmt-rfc-style via treefmt (see treefmt.nix).
      treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
    in
    {
      # One machine for now. Add more hosts under hosts/<name>/ and give each its
      # own attribute here. Build with: nixos-rebuild switch --flake .#workstation
      nixosConfigurations.workstation = nixpkgs.lib.nixosSystem {
        inherit system;
        # `inputs` is threaded to every module via specialArgs so modules can
        # reference flake inputs without importing the flake.
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/workstation
          home-manager.nixosModules.home-manager
          sops-nix.nixosModules.sops
        ];
      };

      # `nix fmt` — format the whole tree with nixfmt-rfc-style.
      formatter.${system} = treefmtEval.config.build.wrapper;

      # `nix flake check` runs this (verifies everything is formatted).
      checks.${system}.formatting = treefmtEval.config.build.check self;

      # `nix develop` (or `direnv allow` via .envrc) — dev tooling for this repo:
      # the Nix linters/formatter, lefthook, and the secrets CLIs. The shellHook
      # wires the git hooks on this machine (idempotent, no-op without git/lefthook).
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nixfmt-rfc-style # formatter (matches treefmt.nix / `nix fmt`)
          deadnix # find dead/unused Nix code
          statix # lint Nix antipatterns
          lefthook # git hooks runner
          sops # edit encrypted secrets
          ssh-to-age # derive age keys from SSH keys
        ];
        shellHook = ''
          if command -v lefthook >/dev/null 2>&1 && [ -e .git ]; then
            lefthook install >/dev/null 2>&1 || true
          fi
        '';
      };
    };
}
