# GPG / secrets tooling. gpg-agent runs with a graphical pinentry and doubles as
# the SSH agent, holding the ed25519 key git uses for commit signing (see
# modules/home/git.nix).
#
# pinentry-qt, NOT pinentry-gnome3: the gnome3 flavour talks to GNOME's GCR
# System Prompter over D-Bus, which does not exist under Hyprland. It then falls
# back to curses and dies with "Inappropriate ioctl for device" whenever there
# is no TTY, so every graphical passphrase prompt fails silently. Qt is already
# in the closure (49 store paths, via Kvantum/Stylix), whereas pinentry-gtk2
# would pull in a GTK2 stack we otherwise have none of — and GTK2 has no Wayland
# backend, so it would render through XWayland.
{ pkgs, ... }:
let
  # OpenSSH does not use pinentry. `ssh-add` and `ssh-keygen -Y sign` shell out
  # to $SSH_ASKPASS whenever they cannot prompt on a terminal, and with nothing
  # installed they fail outright with:
  #   ssh_askpass: exec(): No such file or directory
  # That blocks loading the key from any non-TTY context, and blocks signing
  # from GUI tools. The packaged options are disproportionate — the only one in
  # nixpkgs shipping an askpass binary is lxqt-openssh-askpass, at a 772 MiB
  # closure — so bridge to the pinentry we already have instead. Costs nothing.
  #
  # Assuan: pinentry replies "D <secret>" then "OK"; we print only the D line.
  # SETDESC is percent-escaped because the protocol is line-based and would
  # otherwise break on spaces/newlines in the prompt text.
  sshAskpass = pkgs.writeShellScriptBin "ssh-askpass-pinentry" ''
    desc=$(printf '%s' "$*" | ${pkgs.gnused}/bin/sed -e 's/%/%25/g' -e 's/ /%20/g' -e 's/\r//g')
    {
      printf 'SETTITLE SSH\n'
      printf 'SETDESC %s\n' "''${desc:-SSH%20key%20passphrase}"
      printf 'SETPROMPT Passphrase:\n'
      printf 'GETPIN\n'
      printf 'BYE\n'
    } | ${pkgs.pinentry-qt}/bin/pinentry 2>/dev/null \
      | ${pkgs.gnused}/bin/sed -n 's/^D //p'
  '';
in
{
  programs.gpg.enable = true;

  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry-qt;
    enableSshSupport = true;
    # Unlock once a day, not once an hour.
    #
    # These two are different clocks and the distinction is the whole reason the
    # old values misbehaved: default-cache-ttl is an IDLE timer reset on every
    # use, while max-cache-ttl is a hard ceiling from when the passphrase was
    # entered. At 3600/86400 a gap of more than an hour between signed commits
    # dropped the key even though the 24h ceiling had hours left — which is
    # exactly the pattern of real work, so it re-prompted constantly.
    #
    # Setting the idle timer equal to the ceiling means one unlock covers a
    # working day regardless of how the gaps fall.
    #
    # The security trade is smaller than it looks. This cache lives in the
    # agent's memory and only matters while the session is unlocked — and
    # hypridle locks the screen after 5 minutes idle and suspends at 10
    # (modules/home/hyprland.nix). It does NOT weaken the key at rest: the file
    # in ~/.ssh stays passphrase-encrypted either way, which is what actually
    # matters on a machine whose disk is not encrypted.
    defaultCacheTtl = 86400;
    maxCacheTtl = 86400;
    defaultCacheTtlSsh = 86400;
    maxCacheTtlSsh = 86400;
  };

  home.packages = [
    pkgs.age # file encryption (also used by sops-nix)
    sshAskpass
  ];

  # `prefer` rather than `force`: use the graphical prompt when there is no
  # usable terminal, but still allow a plain TTY prompt when running in one.
  home.sessionVariables = {
    SSH_ASKPASS = "${sshAskpass}/bin/ssh-askpass-pinentry";
    SSH_ASKPASS_REQUIRE = "prefer";
  };
}
