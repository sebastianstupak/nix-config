# treefmt-nix configuration. Drives `nix fmt` and the `formatting` flake check.
{ ... }:
{
  # Formatting is scoped to the directory containing this file (the repo root).
  projectRootFile = "flake.nix";

  # nixfmt = the official Nix formatter (RFC 166), a.k.a. nixfmt-rfc-style.
  programs.nixfmt.enable = true;
}
