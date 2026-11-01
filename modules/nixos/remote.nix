# Reaching this machine from another one: SSH for terminals, Sunshine for pixels.
#
# Inert until `my.remote.enable`. See docs/REMOTE.md for first-time pairing and
# the day-to-day commands.
#
# EVERYTHING HERE IS SCOPED TO THE OVERLAY INTERFACE, which is the whole reason
# this file can exist at all. core.nix deliberately leaves sshd unreachable
# (`openFirewall = false`) because these are laptops that join café and hotel
# networks, and a password-guessable service offered to every stranger on the
# LAN is not a trade worth making. Netbird (modules/nixos/netbird.nix) already
# gives every machine a stable address on an authenticated mesh, so the ports
# below are opened on `wt0` ONLY — the physical NICs still see nothing. That
# keeps core.nix's reasoning intact rather than overriding it.
#
# NOTE THAT THE OVERLAY IS NOT IMPLICITLY TRUSTED by the NixOS firewall. With
# `networking.firewall.allowedTCPPorts` empty, port 22 is blocked on EVERY
# interface including wt0, sshd listening or not — so the per-interface rules
# here are load-bearing, not belt-and-braces. This catches people often enough
# that it is the top answer in every thread about it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.remote;

  # Sunshine derives its whole port family by offsetting one base port, and the
  # nixpkgs module knows the offsets but only applies them via `openFirewall`,
  # which is global. We need the same arithmetic scoped to one interface, so it
  # is repeated here against the same documented offsets.
  basePort = config.services.sunshine.settings.port;
  sunshinePorts = map (offset: basePort + offset);

  # The hyprctl from the package the SESSION runs, not a second Hyprland pulled
  # into the closure for the sake of one binary.
  hyprctl = "${config.programs.hyprland.package}/bin/hyprctl";
in
{
  options.my.remote = {
    enable = lib.mkEnableOption ''
      remote access to this machine over the Netbird overlay: SSH on
      {option}`my.remote.interface`, plus Sunshine for desktop streaming
    '';

    interface = lib.mkOption {
      type = lib.types.str;
      default = "wt0";
      description = ''
        The interface every port below is opened on, and nothing else. `wt0` is
        Netbird's kernel WireGuard interface — check with `ip link` if a future
        version renames it, because a wrong name here fails CLOSED: the ports
        simply stay shut everywhere, which is confusing but safe.
      '';
    };

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "ssh-ed25519 AAAAC3Nz... me@laptop" ];
      description = ''
        Public keys allowed to log in as the primary user. One entry per CLIENT
        machine you connect FROM — including the Windows and macOS ones, which
        is the point of declaring them here rather than appending to
        ~/.ssh/authorized_keys by hand on each host.

        Passwords are already refused system-wide (core.nix sets
        `PasswordAuthentication = false`), so an empty list means nobody can
        log in at all.
      '';
    };

    peers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            hostNames = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Addresses this peer answers on — its overlay FQDN and IP.";
            };
            publicKey = lib.mkOption {
              type = lib.types.str;
              description = "Contents of the peer's /etc/ssh/ssh_host_ed25519_key.pub.";
            };
          };
        }
      );
      default = { };
      description = ''
        The other machines, by SSH HOST key. Declaring these removes the
        trust-on-first-use prompt and replaces it with a real guarantee: a
        man-in-the-middle on the overlay gets rejected instead of asking you to
        type "yes".

        Host keys are already load-bearing in this config — sops derives each
        machine's age key from exactly this key (core.nix), so these are the
        same identities that decrypt secrets. The PUBLIC halves are safe to
        commit.
      '';
    };

    output = lib.mkOption {
      type = lib.types.str;
      default = "eDP-1";
      description = ''
        Which Hyprland output Sunshine streams.

        Defaults to the laptop panel, so connecting shows THE SESSION THAT IS
        ACTUALLY ON THE COMPUTER — the real workspaces, the real window layout,
        the same thing someone standing at the machine would see. That is the
        reason this is the default rather than the virtual-output arrangement
        most guides reach for: those pin workspaces 1-10 to the physical
        display and give the remote a dedicated empty one, which is the
        opposite of what is wanted here, where workspaces 1-9 ARE the orgs
        (see modules/home/orgs.nix).

        Overridden automatically when {option}`my.remote.headlessOutput` is on.
      '';
    };

    headlessOutput = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Stream a virtual output instead of the panel.

        Turn this on when the panel is not a usable capture source — a closed
        lid switches the physical output off, and Hyprland "will not exec
        anything/create any clients" with no monitors at all — or when the
        remote screen should not be stuck at the panel's resolution.

        The output is created by a user unit named deliberately `remote`,
        BEFORE Sunshine starts, and both of those matter: Sunshine's `wlr`
        backend reads `output_name` once at startup and caches it for the
        process lifetime, so an output that appears later is silently ignored
        and it captures the first display it finds instead. A fixed name also
        avoids Hyprland's default of incrementing HEADLESS-2, HEADLESS-3, …
        on every create, which no static config could follow.

        This is still the same session and the same compositor — an extra
        monitor, not a second login.
      '';
    };

    vnc.enable = lib.mkEnableOption ''
      wayvnc alongside Sunshine, as the protocol that works EVERYWHERE.

      Sunshine is better on every axis that matters for a desktop — hardware
      encode, audio, latency — and it is the right default. But it only has a
      good host on Linux and Windows. A fleet that also has a Mac as a TARGET
      cannot be served by it: Sunshine's macOS host is marked Experimental
      upstream, forwards no Command key (Right-Option substitutes), and cannot
      create a virtual display, so a lid-closed Mac has nothing to capture.

      VNC is the only protocol with a first-class host on all three: wayvnc
      here, a third-party server on Windows, and Apple's BUILT-IN Screen
      Sharing on macOS — which is the strongest support story available, since
      it is already installed and handles Command natively.

      So this is not a second-rate duplicate of Sunshine. It is the lowest
      common denominator that lets one client reach every machine, and the
      thing to fall back on when Sunshine will not come up — the Hyprland
      forum's standing advice for exactly that ("if you really need to see
      what's on your desktop, wayvnc for the host is really useful").

      See docs/REMOTE.md for the protocol matrix and the per-OS host setup.
    '';
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.authorizedKeys != [ ];
        message = ''
          my.remote.enable opens SSH but my.remote.authorizedKeys is empty, and
          passwords are refused — so nothing could log in. Add the public key
          of a machine you connect from, or turn my.remote.enable off.
        '';
      }
    ];

    # --- SSH ---------------------------------------------------------------
    # core.nix already has the hardening (keys only, no password auth); all
    # that is missing is a route to it. Note this does NOT touch
    # services.openssh.openFirewall, which stays false — the global firewall
    # keeps rejecting 22 on wlp0s20f3 and friends.
    # One definition rather than two: `interfaces.${cfg.interface}` is a dynamic
    # attribute name, and Nix will not merge two nested definitions that use one.
    networking.firewall.interfaces.${cfg.interface} = {
      allowedTCPPorts = [
        22
      ]
      ++ sunshinePorts [
        (-5)
        0
        1
        21
      ]
      ++ lib.optional cfg.vnc.enable 5900;
      allowedUDPPorts = sunshinePorts [
        9
        10
        11
        13
        21
      ];
    };

    # Hardcoded to the primary user, like the rest of this config — the user is
    # declared by name in hosts/common/default.nix too.
    users.users.sebastianstupak.openssh.authorizedKeys.keys = cfg.authorizedKeys;

    programs.ssh.knownHosts = lib.mapAttrs (_: peer: {
      inherit (peer) hostNames publicKey;
    }) cfg.peers;

    # --- Sunshine ----------------------------------------------------------
    # Sunshine rather than wayvnc, RustDesk or an RDP server, and the reasoning
    # is not just performance. RustDesk is structurally blocked on this
    # compositor: it needs portal protocols xdg-desktop-portal-hyprland does
    # not implement. xrdp is X11-only. wayvnc works and is genuinely useful for
    # looking at what went wrong, but it is software-encoded. Sunshine is
    # hardware-encoded game-streaming machinery with clients (Moonlight) on
    # Linux, Windows, macOS, iOS and Android, which is the cross-platform half
    # of the requirement.
    services.sunshine = {
      enable = true;

      # Starts with graphical-session.target, which on this machine is a target
      # that actually gets reached: `programs.hyprland.withUWSM` puts the
      # compositor in a real systemd user session (modules/nixos/desktop.nix).
      # The usual complaint about Sunshine on Wayland window managers is that
      # the user unit never launches because nothing ever starts that target —
      # UWSM is why that does not apply here.
      autoStart = true;

      # NOT opened globally — see the per-interface rules above.
      openFirewall = false;

      # CAP_SYS_ADMIN is for DRM/KMS capture, and `capture = "wlr"` below means
      # we do not do DRM/KMS capture. Leaving it off is not just tidiness: the
      # capability applies to the whole binary, and it breaks launching
      # applications as the ordinary user. We only ever want desktop capture,
      # so there is nothing to trade away. If capture ever fails outright, the
      # fallback is kms + this flag — docs/REMOTE.md.
      capSysAdmin = false;

      settings = {
        sunshine_name = config.networking.hostName;

        # wlroots capture, the native path for Hyprland. Also the only backend
        # that can see a virtual output, so my.remote.headlessOutput depends on
        # it. (The black-frame reports against this backend are Nvidia's tiled
        # framebuffer layout, which neither of these machines has — one is AMD,
        # the other Intel.)
        capture = "wlr";

        output_name = if cfg.headlessOutput then "remote" else cfg.output;

        # Pair over an SSH tunnel, not over the network.
        #
        # "pc" restricts the web UI to requests originating on this machine,
        # and pairing is the only thing it is needed for. The alternative,
        # "lan", is a worse fit than it looks: Sunshine decides what counts as
        # LAN from the private address ranges, and the overlay lives in
        # 100.64.0.0/10 — carrier-grade NAT space, not RFC1918 — so it is not
        # reliably classified as local anyway. Forwarding the port over the SSH
        # connection that already exists sidesteps the question and keeps the
        # admin interface off the wire entirely. docs/REMOTE.md has the command.
        origin_web_ui_allowed = "pc";
      };
    };

    # mDNS: SUPPRESSED, not left at the module's default.
    #
    # The Sunshine module turns `services.avahi.publish` on (mkDefault), which
    # makes this host advertise a Sunshine service record — its hostname and the
    # fact that it runs a remote-desktop server — on every network it joins,
    # café and hotel ones included. That is pure cost here, because NOTHING IN
    # THIS SETUP USES DISCOVERY: pairing happens over an SSH tunnel to localhost
    # (origin_web_ui_allowed below) and Moonlight connects by overlay IP, which
    # is typed in by hand once. Broadcasting to strangers buys a convenience we
    # deliberately do not use.
    #
    # This does NOT affect printing. Avahi stays enabled with nssmdns4
    # (modules/nixos/desktop.nix) and printer discovery is BROWSING — asking
    # what else is on the network. Publishing is the opposite direction:
    # advertising our own services. Only the latter is turned off, and only
    # CUPS printer SHARING would have wanted it, which we do not do.
    #
    # The cost is one benign log line at startup,
    # `avahi::entry_group_new() failed: Not permitted`, which is Sunshine
    # noticing it cannot advertise and carrying on.
    services.avahi.publish.enable = false;

    # The virtual output, created before Sunshine looks for it.
    #
    # `before`/`Type=oneshot` is the entire point of this unit existing instead
    # of an exec-once in the Hyprland config: an exec-once races the
    # sunshine.service start, and losing that race is silent — Sunshine caches
    # the first output it finds and streams the wrong display.
    systemd.user.services.remote-headless-output = lib.mkIf cfg.headlessOutput {
      description = "Create the headless Hyprland output Sunshine streams";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      before = [ "sunshine.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Idempotent on purpose: restarting the unit (or the whole graphical
        # session) must not stack up `remote-2`, `remote-3`. hyprctl exits
        # non-zero when the name is taken, which is success for us.
        ExecStart = "${pkgs.writeShellScript "create-remote-output" ''
          ${hyprctl} monitors all \
            | ${pkgs.gnugrep}/bin/grep -q '^Monitor remote ' && exit 0
          exec ${hyprctl} output create headless remote
        ''}";
        ExecStop = "${hyprctl} output remove remote";
      };
    };

    # --- wayvnc -------------------------------------------------------------
    # The cross-platform fallback. See my.remote.vnc.enable for why it exists
    # at all when Sunshine is better, and docs/REMOTE.md for the matrix.
    #
    # AUTHENTICATION IS PAM, which is the whole reason this needs no secret.
    # wayvnc's `enable_auth` otherwise demands a literal `password` in its
    # config file — and this config file is generated into the Nix store, which
    # is WORLD-READABLE, so a password there would be a password published to
    # every user and every process on the machine. `enable_pam` overrides
    # username/password entirely and authenticates against the real account
    # instead, so the credential is the one already managed via
    # hashedPasswordFile (secrets/README.md) and nothing new is stored anywhere.
    #
    # Without authentication wayvnc hands the desktop to anyone who can open
    # the port, with no credential at all. The port is overlay-only, but the
    # overlay is exactly where collaborators live, so "the network is the
    # auth" is not a position this can take.
    security.pam.services.wayvnc = lib.mkIf cfg.vnc.enable { };

    # For `wayvncctl`, not for wayvnc itself — the service runs the binary from
    # the store by absolute path. wayvncctl is how the running server is
    # inspected and steered (`output-list`, `output-set`, `attach`), which is
    # exactly what you need when the stream shows the wrong screen, so having
    # it only inside the unit's closure is useless.
    environment.systemPackages = lib.mkIf cfg.vnc.enable [ pkgs.wayvnc ];

    systemd.user.services.wayvnc = lib.mkIf cfg.vnc.enable {
      description = "wayvnc — VNC server for the running Hyprland session";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];

      serviceConfig = {
        # TLS material is generated here rather than declared, because a private
        # key in the Nix store is a published private key. Self-signed: there is
        # no CA that could meaningfully vouch for a laptop, and the client is
        # always one of ours, so the certificate is a transport key rather than
        # an identity claim. Clients will warn on first connect — expected.
        ExecStartPre = "${pkgs.writeShellScript "wayvnc-setup" ''
          set -eu
          dir="''${XDG_CONFIG_HOME:-$HOME/.config}/wayvnc"
          mkdir -p "$dir"

          if [ ! -s "$dir/key.pem" ] || [ ! -s "$dir/cert.pem" ]; then
            ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:4096 -nodes \
              -days 3650 -subj "/CN=${config.networking.hostName}" \
              -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null
          fi
          chmod 600 "$dir/key.pem"

          # Written here rather than shipped as a store path so the file paths
          # can follow $HOME instead of being hardcoded. Rewritten every start,
          # so this file is ours and hand edits do not survive — which is the
          # point, it should match this module.
          cat > "$dir/config" <<EOF
          address=0.0.0.0
          port=5900
          enable_auth=true
          enable_pam=true
          certificate_file=$dir/cert.pem
          private_key_file=$dir/key.pem
          EOF
          ${pkgs.gnused}/bin/sed -i 's/^[[:space:]]*//' "$dir/config"
        ''}";

        # --gpu enables the H.264 path (wayvnc 0.5+ speaks the OpenH264 RFB
        # extension). Worth knowing it only helps with a client that negotiates
        # it — TigerVNC and noVNC do; Apple's built-in viewer and most others
        # fall back to Tight, which still works, just software-encoded.
        #
        # Binds 0.0.0.0 and relies on the per-interface firewall rule above,
        # the same arrangement Sunshine ends up with. Binding the overlay
        # address directly would be tighter but it is assigned by NetBird at
        # runtime, so the service would fail to start whenever it came up
        # before the tunnel.
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.wayvnc}/bin/wayvnc"
          "--gpu"
          "--max-fps=60"
          "--output=${if cfg.headlessOutput then "remote" else cfg.output}"
          "0.0.0.0"
        ];
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

  };
}
