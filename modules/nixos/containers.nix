# Containers: Docker (used across dev repos). The user is granted the `docker`
# group in hosts/<host>/default.nix. Rootless podman is an alternative if you
# ever want daemonless containers.
{ ... }:
{
  virtualisation.docker.enable = true;
}
