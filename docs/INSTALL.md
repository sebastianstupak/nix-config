# Installing this config from scratch (wipe → NixOS)

Step-by-step for putting NixOS + this flake on the HP laptop, **erasing the whole
disk** (no dual-boot). Read the whole thing once before you start. Commands assume
a UEFI machine and an NVMe disk at `/dev/nvme0n1` — **confirm your disk with
`lsblk` and substitute the real name** (it may be `/dev/sda`).

> ⚠️ **Everything on the disk is destroyed.** Back up first (music projects,
> samples, VST installers + licenses, documents, eID certs). **Deauthorize
> seat-limited plugin licenses in Windows first** (iLok / Native Access / Waves).

---

## 0. Prepare the USB installer (on Windows, before wiping)

1. Download the NixOS **26.05** ISO (Graphical or Minimal, x86_64) from
   <https://nixos.org/download>. Minimal is fine.
2. Flash it to an 8 GB+ USB stick with [Rufus](https://rufus.ie) (use **DD mode**
   when prompted) or [Ventoy](https://ventoy.net).
3. Have your **Wi-Fi name + password** handy.

## 1. Firmware (BIOS/UEFI) settings

Reboot and enter firmware setup (HP: tap **Esc**, then **F10**).

- **Disable Secure Boot** — required (this config uses systemd-boot without
  lanzaboote; it won't boot with Secure Boot on).
- Ensure **UEFI mode** (disable Legacy/CSM).
- Disable **Fast Boot** if present.
- Boot from the USB (HP boot menu: **F9**), or set it first in the boot order.

## 2. Boot the installer and get online

At the live shell become root:

```bash
sudo -i
```

**Wi-Fi** (skip if on Ethernet):

```bash
iwctl
# at the iwctl prompt:
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "YOUR_SSID"    # enter password when asked
exit
```

Verify: `ping -c3 nixos.org`.

## 3. Partition the disk (whole-disk, GPT/UEFI)

Confirm the target disk first:

```bash
lsblk         # note the disk, e.g. nvme0n1 (NOT a partition like nvme0n1p1)
```

Create a 1 GB EFI partition + one root partition (generous ESP avoids running out
of space with many NixOS generations):

```bash
DISK=/dev/nvme0n1        # <-- set this to YOUR disk

parted "$DISK" -- mklabel gpt
parted "$DISK" -- mkpart ESP fat32 1MiB 1025MiB
parted "$DISK" -- set 1 esp on
parted "$DISK" -- mkpart root ext4 1025MiB 100%
```

> On NVMe the partitions are `${DISK}p1` / `${DISK}p2`; on SATA they're `${DISK}1`
> / `${DISK}2`. Adjust the format/mount commands accordingly.

Format and label (the labels match nothing critical — the real filesystem config
is generated in step 4 — but keep them tidy):

```bash
mkfs.fat -F 32 -n BOOT /dev/nvme0n1p1
mkfs.ext4 -L nixos      /dev/nvme0n1p2
```

Mount:

```bash
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/BOOT /mnt/boot
```

*(Swap: skipped here. The config runs fine without it; add a swapfile or zram
later if you want hibernate.)*

## 4. Generate the machine's hardware config

```bash
nixos-generate-config --root /mnt
```

This writes `/mnt/etc/nixos/hardware-configuration.nix` describing **this laptop's**
real disks/drivers. You'll drop it into the flake next (it replaces the committed
placeholder).

## 5. Get this flake and wire in the hardware config

```bash
cd /mnt/etc/nixos
nix-shell -p git      # gives you git in the installer

git clone https://github.com/sebastianstupak/nix-config
cp hardware-configuration.nix nix-config/hosts/workstation/hardware-configuration.nix

cd nix-config
git add hosts/workstation/hardware-configuration.nix   # REQUIRED: flakes ignore untracked files
```

> The `git add` is not optional — Nix only sees files tracked by git, so an
> unstaged hardware config makes the build fail with "path does not exist".

**First-install tip (optional but recommended):** the audio profile pulls
`shibco/ableton-linux`, whose **patched Wine is a large from-source build** that can
make this first install very slow. To get a bootable system quickly, temporarily
remove the audio line, install, boot, then add it back and rebuild (possibly
overnight, or after checking the project's README for a Cachix binary cache):

```bash
# edit hosts/workstation/default.nix and comment out this import for now:
#   ../../modules/nixos/audio.nix
```

## 6. Install

```bash
nixos-install --flake /mnt/etc/nixos/nix-config#workstation
```

This builds the whole system (Hyprland, apps, theming — a big download; give it
time). At the end it prompts for a **root password**.

## 7. Set your user password (needed to log in)

The login manager (greetd/tuigreet) needs a password for `sebastianstupak`, which
the config deliberately doesn't set:

```bash
nixos-enter --root /mnt -c 'passwd sebastianstupak'
```

## 8. Reboot

```bash
reboot
```

Remove the USB. You should get the systemd-boot menu → NixOS → the tuigreet login.
Log in as **sebastianstupak** → Hyprland starts.

*(If the graphical login misbehaves, switch to a TTY with **Ctrl+Alt+F2**, log in,
and check `journalctl -b -e`.)*

---

## 9. First things after first boot

**Wi-Fi:** click the tray applet, or:

```bash
nmcli device wifi connect "YOUR_SSID" password "YOUR_PW"
```

**Clone the config into your home for future edits + enable the dev shell/hooks:**

```bash
git clone https://github.com/sebastianstupak/nix-config ~/nix-config
cd ~/nix-config
direnv allow          # nix-direnv loads the dev shell and sets core.hooksPath
```

**Apply future changes** (a `rebuild` alias is configured):

```bash
sudo nixos-rebuild switch --flake ~/nix-config#workstation
# rollback a bad change:
sudo nixos-rebuild switch --rollback
```

**Keyboard:** US ↔ SK toggles with **Alt+Shift**. Handy Hyprland keys: `Super+Enter`
terminal, `Super+R` launcher, `Super+Q` close, `Super+C` clipboard history,
`Super+Shift+S` snipping tool, `Super+Shift+X` power menu, `Super+L` lock.

## 10. Secrets (sops) — only when you need one

Derive this machine's age key from its SSH host key, put it in `.sops.yaml`, then
create secrets (see `secrets/README.md`):

```bash
nix run nixpkgs#ssh-to-age -- -i /etc/ssh/ssh_host_ed25519_key.pub
# paste the age1... into .sops.yaml, commit, then: sops secrets/secrets.yaml
```

## 11. Ableton / audio (shibco/ableton-linux)

If you removed `audio.nix` for the first install, re-add the import and
`nixos-rebuild switch` first. Then set up the wineprefix (imperative, one-time):

```bash
nix run github:shibco/ableton-linux#setup-prefix
nix run github:shibco/ableton-linux#setup-realtime
nix run github:shibco/ableton-linux#default      # launch Ableton, authorize OFFLINE
```

Install your Windows VSTs into that same wineprefix. Expect DRM caveats
(FabFilter/Valhalla fine; iZotope/iLok/Kontakt activation is the risk).

---

## If something goes wrong

- **Won't boot after install:** pick an older generation in the systemd-boot menu.
- **A rebuild breaks the desktop:** `sudo nixos-rebuild switch --rollback`.
- **Build error mentions "path does not exist":** you added a file but didn't
  `git add` it (see step 5).
- **Graphics glitches:** this laptop likely has AMD graphics (works out of the box
  with `hardware.graphics`); if it's NVIDIA, that needs extra config — tell me and
  I'll add an NVIDIA module.
```
