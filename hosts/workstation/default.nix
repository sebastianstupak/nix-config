# workstation — the AMD HP laptop, daily driver.
#
# Everything shared with the other machine is in ../common. What is here is
# only what distinguishes this one: its name, its password, and the fact that
# it is the machine that prunes the backup repository.
{ ... }:
{
  imports = [ ../common ];

  networking.hostName = "workstation";

  # THE ONE MACHINE THAT PRUNES.
  #
  # Pruning takes an exclusive lock on the shared restic repository, so it has
  # to be exactly one of them — every other machine backs up and expires
  # nothing. While both machines shared a single host entry they both had this
  # set, which is the collision the comment in ../common warns about.
  my.backup.prune = true;

  # This host's login password.
  #
  # STILL THE SHARED FILE, and deliberately so. The per-host layout and the
  # .sops.yaml rules for secrets/workstation/ are in place, but splitting the
  # hash means creating a new encrypted file, and a file this option points at
  # that cannot be decrypted locks root and this user out on the next
  # activation — see "The lockout" in secrets/README.md. So the split is a
  # deliberate two-step on each machine, documented there, not something to
  # inherit half-finished.
  #
  # Root-owned 0400 is correct: the reader is update-users-groups.pl running as
  # root, not a user unit. `neededForUsers` makes it available before users are
  # set up rather than only after activation.
  sops.secrets.sebastianstupak-hash = {
    sopsFile = ../../secrets/common/passwords.yaml;
    key = "sebastianstupak-hash";
    neededForUsers = true;
  };
}
