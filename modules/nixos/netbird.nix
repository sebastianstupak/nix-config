# NetBird mesh VPN client. Run `netbird up` once to authenticate/join a network.
#
# EVERY HOST GETS ITS OWN WIREGUARD PORT, set in hosts/<host>/default.nix:
#
#   hestia   51820   (nixpkgs' default)
#   zagreus  51821
#
# and the reason is NAT, not tidiness. The gateway's automatic outbound NAT
# rewrites source ports, which breaks NetBird's UDP hole punching — every peer
# behind it fell back to a relay in Frankfurt, so two machines on the same
# switch talked to each other via Germany. The fix is an outbound NAT rule with
# static-port, which tells the firewall to leave the source port alone
# (docs/REMOTE.md, and docs/REMOTE-ACCESS.md in the hades repo).
#
# But static-port is exactly what makes a SHARED port a problem. nixpkgs
# defaults every client to 51820, so with the rule in place two peers on one LAN
# would both want to appear as <wan-ip>:51820 — one wins and the other falls
# back to the relay we just escaped. Distinct ports per host is what keeps the
# fix working for more than one machine at a time.
#
# Adding a machine: give it the next port, and add a MATCHING OUTBOUND NAT RULE
# on the gateway — one rule per port, not one rule with a range. That field
# rejects `51820-51829` with "You must supply either a valid port or port
# alias", so the options are a rule each or a port alias to reference; at two
# machines a rule each is the smaller thing. Duplicating the existing rule and
# changing its source port is the whole job.
#
# Measured, not assumed — `netbird status --detail` reports `Connection type:
# P2P` with real ICE candidates when this is right, and `Relayed` with `-/-`
# when it is not.
{ ... }:
{
  services.netbird.enable = true;

  # DNS, AND WHY IT IS HERE RATHER THAN IN A NETWORKING MODULE.
  #
  # NetBird chooses a "DNS manager" at startup: NetworkManager, systemd-resolved,
  # the resolvconf CLI, or — if it finds none of those — editing /etc/resolv.conf
  # directly. That last one is what it was doing here, and it is not a shared
  # arrangement: it replaces the file with a single `nameserver <netbird's own
  # overlay IP>` and keeps the previous servers only as its own upstreams.
  #
  # SO NETBIRD BECAME THE MACHINE'S ONLY RESOLVER. While the daemon is up that
  # works. While it is not — stopped, or running but unauthenticated, which
  # reports as `Daemon status: NeedsLogin` while the unit still looks active —
  # the address in resolv.conf belongs to no interface and EVERY lookup on the
  # machine fails. Not just the overlay: github.com too. It presents as "DNS is
  # broken" rather than "the VPN is down", which is why it kept being diagnosed
  # as the wrong thing.
  #
  # THE SPLIT-DNS CONFIG ALSO NEEDED THIS. The network serves a nameserver with
  # a MATCH DOMAIN (`… for [datadir.dev]`), and NetBird documents match domains
  # as supported on macOS, Windows 10+, and "Linux with systemd-resolved" —
  # nowhere else. Under the file manager there is nothing to attach a match
  # domain to, so the only way to honour it is to take the whole resolver.
  #
  # With resolved enabled, NixOS points /etc/resolv.conf at
  # /run/systemd/resolve/stub-resolv.conf, which is the symlink target NetBird's
  # detection keys on (netbirdio/netbird#5199 is the same bug from the other
  # side: a NetworkManager-GENERATED file holding 127.0.0.53 is not that
  # symlink, so detection fails and it falls back to the file manager anyway).
  # NetBird then registers its nameserver against its own link with the match
  # domain, every other name keeps resolving through the link it arrived on, and
  # the VPN going down costs the overlay rather than the machine.
  services.resolved.enable = true;

  # AND NETWORKMANAGER HAS TO AGREE. Left at "default" it writes its own
  # resolv.conf, which is exactly the file that defeats the detection above —
  # the bug report's symptom rather than its cause. This hands DNS to resolved
  # so there is one writer and one stub.
  networking.networkmanager.dns = "systemd-resolved";
}
