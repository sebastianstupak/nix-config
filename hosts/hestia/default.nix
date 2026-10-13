# hestia — HP ZBook Firefly 14 G10, Intel i7-1355U.
#
# Was the second machine booting the shared `workstation` entry, which is why
# its host key is a recipient on every secret and why `.sops.yaml` called that
# recipient `workstation_intel`. It has its own host entry now, so it carries
# its own hostname and its own password.
#
# Everything shared with the other laptop is in ../common.
{ ... }:
{
  imports = [ ../common ];

  # A NAME OF ITS OWN, and the reason is not cosmetic. Both machines answered to
  # `workstation`, and restic's `forget --group-by host` groups snapshots by
  # hostname — so two machines' histories were one history and each was ageing
  # out the other's snapshots. ../common claims each machine keeps its own
  # history; separate hostnames are what make that true.
  #
  # Renaming is not free at switch time: netbird identifies a peer by hostname,
  # so this re-registers as a new one, and every snapshot either machine wrote
  # under `workstation` stays in that group — no longer covered by either
  # machine's retention. Forget those by hand once the new groups look right.
  networking.hostName = "hestia";

  # No `my.backup.prune` — zagreus prunes. See ../common.

  # This host's login password. Still the shared file; see the note in
  # ../zagreus/default.nix and "Splitting a host's password" in
  # secrets/README.md for the two-step that separates them safely.
  sops.secrets.sebastianstupak-hash = {
    sopsFile = ../../secrets/common/passwords.yaml;
    key = "sebastianstupak-hash";
    neededForUsers = true;
  };
}
