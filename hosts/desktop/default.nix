# desktop — the Intel machine (SK hynix PC801).
#
# Was the second machine booting hosts/workstation/, which is why its host key
# is a recipient on every secret and why `.sops.yaml` called it
# `workstation_intel`. It has its own host entry now so it can carry its own
# hostname and its own password.
#
# Everything shared with the laptop is in ../common.
{ ... }:
{
  imports = [ ../common ];

  # A NAME OF ITS OWN, and the reason is not cosmetic. Both machines answered
  # to `workstation`, and restic's `forget --group-by host` groups snapshots by
  # hostname — so two machines' histories were one history, and each was
  # ageing out the other's snapshots. ../common claims each machine keeps its
  # own history; this is what makes that true.
  #
  # Renaming a machine is not free: netbird identifies a peer by hostname, so
  # this re-registers, and this host's existing snapshots stay under the old
  # `workstation` group rather than following it.
  networking.hostName = "desktop";

  # No `my.backup.prune` — the laptop prunes. See ../common.

  # This host's login password. Still the shared file; see the note in
  # ../workstation/default.nix and "Splitting a host's password" in
  # secrets/README.md for the two-step that separates them safely.
  sops.secrets.sebastianstupak-hash = {
    sopsFile = ../../secrets/common/passwords.yaml;
    key = "sebastianstupak-hash";
    neededForUsers = true;
  };
}
