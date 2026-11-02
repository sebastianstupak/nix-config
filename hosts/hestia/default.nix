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

  # THE DISCRETE GPU IS DEAD WEIGHT HERE, so its driver does not load.
  #
  # This machine has an NVIDIA RTX A500 at 01:00.0 alongside the Raptor Lake
  # iGPU — which ../../docs/REMOTE.md spent a while denying, on the strength of
  # "no Nvidia GPU" being the right answer for the AMD laptop. It changes
  # nothing about what draws the desktop: the card has no display outputs
  # wired to it, so aquamarine enumerates it, finds no KMS, and logs
  # "Skipping device ... not a KMS device" every session. Hyprland renders on
  # /dev/dri/card1 (i915) and VA-API encodes on renderD128 (iHD) regardless.
  #
  # What it DID do was cost. Sunshine probes an nvenc/CUDA encoder on every
  # single stream because an NVIDIA device is present, fails it
  # ("Failed to create a CUDA device: Operation not permitted" — nouveau
  # offers no CUDA and never will), and the card sat permanently at
  # power/control=on. Blacklisting the driver removes /dev/dri/card0 and
  # renderD129 entirely, so the probe has nothing to find.
  #
  # nvidiafb goes too: it binds the same device and is the other module the
  # kernel would try. Nothing here wants the dGPU — no CUDA workload, no
  # external-display duty, no gaming on this host (that is zagreus).
  #
  # Reversing this is one line, but note what it is NOT: a power switch. With
  # no driver bound the chip's power state is firmware's decision, and TLP
  # pins runtime PM to "on" for everything while on AC. The udev rule below
  # asks for "auto" on this one device so the kernel is at least permitted to
  # suspend it; the only guaranteed off is the BIOS graphics setting. Verify
  # with `cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status`.
  boot.blacklistedKernelModules = [
    "nouveau"
    "nvidiafb"
  ];

  services.udev.extraRules = ''
    # RTX A500 (01:00.0) — unbound and unwanted; let the kernel suspend it.
    # Narrow on purpose: TLP's AC profile is left alone for every other device.
    ACTION=="add", SUBSYSTEM=="pci", KERNEL=="0000:01:00.0", ATTR{power/control}="auto"
  '';

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
