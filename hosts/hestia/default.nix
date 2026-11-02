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

  # THE DISCRETE GPU IS DEAD WEIGHT, so its driver does not load — and the power
  # is handled somewhere else entirely. Read on: the obvious diagnosis here was
  # wrong twice, and the measurement that settled it is below.
  #
  # This machine has an NVIDIA RTX A500 at 01:00.0 alongside the Raptor Lake
  # iGPU — which ../../docs/REMOTE.md spent a while denying, on the strength of
  # "no Nvidia GPU" being the right answer for the AMD laptop. It changes
  # nothing about what draws the desktop: the card has no display outputs wired
  # to it, so aquamarine enumerates it, finds no KMS, and logs "Skipping device
  # ... not a KMS device" every session. Hyprland renders on /dev/dri/card1
  # (i915) and VA-API encodes on renderD128 (iHD) regardless.
  #
  # So it is blacklisted, which stops Sunshine probing an nvenc/CUDA encoder on
  # every stream and failing it ("Failed to create a CUDA device" — nouveau
  # offers no CUDA and never will), and removes /dev/dri/card0 and renderD129
  # so the probe has nothing to find.
  #
  # THIS WAS BRIEFLY REVERTED, on the widely-repeated argument that an Optimus
  # dGPU only reaches D3cold through its DRIVER's runtime PM — so a blacklisted
  # card supposedly sits in D0 forever, and the documented remedy for "power is
  # still high after disabling the dGPU" is to let nouveau load. MEASURED ON
  # THIS MACHINE, THAT IS FALSE. With no driver bound at all, and TLP no longer
  # pinning power/control, the device runtime-suspends by itself:
  #
  #   driver bound:           none
  #   power/control:          auto
  #   runtime_status:         suspended
  #   runtime_active_time:    14828646 ms  (4.1h, accumulated while pinned "on")
  #   runtime_suspended_time: 143921 ms    (began the moment it was not)
  #
  # The PCI core suspends an unbound device perfectly well here. The real cause
  # was always TLP's RUNTIME_PM_ON_AC default of "on" (see
  # ../../modules/nixos/laptop.nix): power/control read "on" both before AND
  # after the blacklist, so nothing was ever suspending this GPU and the
  # blacklist was never what cost the power.
  #
  # Both are therefore kept, because they fix different things and do not
  # conflict — the blacklist buys quiet logs, TLP's "auto" buys the power.
  # Letting nouveau load would hand back the CUDA probe noise for no measured
  # benefit.
  #
  # Verify rather than trust:
  #   cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status   # want: suspended
  # If that reads "active", suspect a pin on power/control before suspecting the
  # missing driver. The BIOS graphics setting remains the only guaranteed off.
  boot.blacklistedKernelModules = [
    "nouveau"
    "nvidiafb"
  ];

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
