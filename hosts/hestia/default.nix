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

  # THE DISCRETE GPU IS DEAD WEIGHT, AND NOUVEAU LOADS ANYWAY — read on, because
  # the obvious move is the wrong one and this file used to make it.
  #
  # This machine has an NVIDIA RTX A500 at 01:00.0 alongside the Raptor Lake
  # iGPU — which ../../docs/REMOTE.md spent a while denying, on the strength of
  # "no Nvidia GPU" being the right answer for the AMD laptop. It changes
  # nothing about what draws the desktop: the card has no display outputs wired
  # to it, so aquamarine enumerates it, finds no KMS, and logs "Skipping device
  # ... not a KMS device" every session. Hyprland renders on /dev/dri/card1
  # (i915) and VA-API encodes on renderD128 (iHD) regardless.
  #
  # So it was blacklisted, to stop Sunshine probing an nvenc/CUDA encoder on
  # every stream and failing it ("Failed to create a CUDA device" — nouveau
  # offers no CUDA and never will). THAT MADE THE POWER WORSE, or at best
  # changed nothing: on an Optimus laptop the chip is put into D3cold by the
  # DRIVER's runtime PM, so with nothing bound there is nothing left to invoke
  # the ACPI power-off and it can sit in D0 indefinitely. The documented remedy
  # for "power is still high after disabling the dGPU" is to remove the
  # blacklist and let nouveau load.
  #
  # The giveaway was that power/control read "on" both before and after the
  # blacklist, because TLP pins runtime PM on AC (see RUNTIME_PM_ON_AC in
  # ../../modules/nixos/laptop.nix, now "auto"). Nothing was ever suspending
  # this GPU; the blacklist only silenced a log line.
  #
  # So: no blacklist, and the driver is left to do its job. The CUDA probe
  # noise comes back and is simply accepted — about 0.4s per Sunshine start,
  # which Sunshine itself prints "Ignore any errors mentioned above" about.
  #
  # Verify rather than trust, because this is the whole point of the change:
  #   cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status   # want: suspended
  # If it still says "active" on battery, the dGPU is awake and the BIOS
  # graphics setting is the only guaranteed off.

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

  # ITS OWN WIREGUARD PORT. Allocation and the reason: ../../modules/nixos/netbird.nix.
  services.netbird.clients.default.port = 51820;

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
