# Reusable home-manager module: settings shared across every user this repo manages.
# Per-user specifics live in home/<user>/.
{ ... }:
{
  # Let home-manager manage itself.
  programs.home-manager.enable = true;
}
