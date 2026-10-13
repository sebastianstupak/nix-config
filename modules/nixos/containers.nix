# Containers: rootless podman, with the Docker API socket Testcontainers needs.
#
# Switched from docker because the dev repos already assume podman —
# platform/Taskfile.yml defaults COMPOSE to `podman compose`, so `task up` only
# ever worked there via MAETHRIL_CONTAINER=docker. The `docker` CLI still works
# through dockerCompat, so nothing that calls docker by name had to change.
{ pkgs, ... }:
{
  virtualisation.podman = {
    enable = true;

    # `docker` as a command alias, and the rootful socket at /run/docker.sock.
    # Keeps anything that shells out to `docker` or reads that path working.
    dockerCompat = true;
    dockerSocket.enable = true;

    # Container DNS, and compose does not work without it.
    #
    # The option really does default to false — checked in this nixpkgs, not
    # assumed. With it off a container cannot resolve a sibling by service
    # name, so every compose `depends_on` comes up and immediately fails to
    # connect, and the symptom reads like a startup race rather than DNS.
    #
    # It carries a second effect worth knowing: the module only opens UDP 53 on
    # the podman interface when this is true, because containers cannot reach
    # aardvark-dns otherwise. So this one line is both the fix and its firewall
    # rule.
    defaultNetwork.settings.dns_enabled = true;

    autoPrune = {
      enable = true;
      dates = "weekly";
      # Images untouched for a week, deliberately not --all. Pruning every
      # stopped container would take its named volumes with it, and a weekly
      # job that can delete the database you were halfway through debugging is
      # not a convenience.
      flags = [
        "--filter"
        "until=168h"
      ];
    };
  };

  # Socket-activate podman in the user session.
  #
  # The unit ships with the package but nothing wants it, so without this the
  # rootless socket only exists after a manual `systemctl --user start
  # podman.socket`. Testcontainers would fail on the first test run after every
  # login, which reads as flakiness rather than as missing configuration.
  systemd.user.sockets.podman.wantedBy = [ "sockets.target" ];

  environment.sessionVariables = {
    # Testcontainers probes DOCKER_HOST first. Pointing it at the ROOTLESS
    # socket is the point of running podman at all: a test suite must not need
    # a socket that is effectively root.
    #
    # uid 1000 is written out rather than derived from $XDG_RUNTIME_DIR because
    # session variables are not reliably shell-expanded on the way into a
    # Wayland session. It is safe to hardcode here for the reason the host
    # entry gives: uid 1000 is pinned in /var/lib/nixos/uid-map.
    DOCKER_HOST = "unix:///run/user/1000/podman/podman.sock";

    # Ryuk does not work rootless.
    #
    # Testcontainers' reaper is a privileged sidecar that bind-mounts the
    # container socket to clean up after a crashed run. Rootless, the path it
    # needs is not the path it gets, and it fails at container start — which
    # surfaces as every fixture timing out, not as a reaper error.
    #
    # The cost is real and worth stating: a run killed with SIGKILL leaves its
    # containers behind, and `podman ps` plus `podman rm` is the cleanup.
    # autoPrune above is the backstop.
    TESTCONTAINERS_RYUK_DISABLED = "true";
  };

  # No registries.search here on purpose. Upstream podman has no implicit
  # Docker Hub, which is a real trap for the unqualified image names the
  # compose files use — but nixpkgs already defaults
  # virtualisation.containers.registries.search to docker.io and quay.io.
  # Declaring it would be redundant, and the obvious spelling of it
  # (just docker.io) silently drops quay.io.

  environment.systemPackages = with pkgs; [
    # `podman compose` delegates to whatever provider it finds; installing this
    # makes that deterministic instead of dependent on a stray docker-compose
    # on PATH.
    podman-compose
    podman-tui
  ];
}
