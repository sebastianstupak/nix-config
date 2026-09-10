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
    defaultCacheTtl = 3600;
    # Match the SSH cache to the GPG one; otherwise the signing key is dropped
    # on the agent's much shorter SSH default and re-prompts mid-session.
    defaultCacheTtlSsh = 3600;
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
