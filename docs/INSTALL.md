# Installing this config from scratch (wipe → NixOS)

> `<host>` below is the machine you are installing: **`zagreus`** (AMD HP
> laptop) or **`hestia`** (HP ZBook Firefly 14 G10). They have one host entry
> each — pick the right one or you will give a machine the other's hostname.

Step-by-step for putting NixOS + this flake on either machine, **erasing the whole
disk** (no dual-boot). Read the whole thing once before you start. Commands assume
a UEFI machine and an NVMe disk at `/dev/nvme0n1` — **confirm your disk with
`lsblk` and substitute the real name** (it may be `/dev/sda`).

> **Two things here are order-dependent and will lock you out of the installed
> system if you skip them.** Both were learned the hard way:
>
> 1. **Enrol the machine's SSH host key as a sops recipient *before* the first
>    boot** (step 6). The login password comes from an encrypted secret; a fresh
>    install has a fresh host key, which cannot decrypt it, and
>    `users.mutableUsers = false` then locks every account. `passwd` cannot fix
>    this afterwards — see "The lockout" in [`secrets/README.md`](../secrets/README.md).
> 2. **Do not overwrite `hosts/zagreus/hardware-configuration.nix` with
>    generated output** (step 5). Two machines share it and it is hand-merged;
>    replacing it leaves the other machine unbootable.

> **WARNING — everything on the disk is destroyed.** Back up first (music projects,
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

Format and label. **The labels are load-bearing — get them exactly right.**
`hardware-configuration.nix` mounts `/dev/disk/by-label/nixos` and
`/dev/disk/by-label/BOOT`, which is what lets one host entry boot both machines.
A typo here produces a system that builds fine and then cannot find its root:

```bash
mkfs.fat -F 32 -n BOOT /dev/nvme0n1p1
mkfs.ext4 -L nixos      /dev/nvme0n1p2
```

Verify before continuing — `lsblk -o NAME,FSTYPE,LABEL` must show exactly
`BOOT` (vfat) and `nixos` (ext4).

> Reinstalling a machine whose partition table is already correct? Skip `parted`
> entirely and just re-run these two `mkfs` commands. Same clean slate, no risk
> of writing a bad partition table.

Mount:

```bash
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/BOOT /mnt/boot
```

*(Swap: skipped here. The config runs fine without it; add a swapfile or zram
later if you want hibernate.)*

## 4. Generate the machine's hardware config (for reference only)

```bash
nixos-generate-config --root /mnt
```

This writes `/mnt/etc/nixos/hardware-configuration.nix` describing **this
machine's** real disks and drivers. Read it — but do **not** copy it over the
committed one.

## 5. Get this flake and merge (not replace) the hardware config

```bash
cd /mnt/etc/nixos
nix-shell -p git      # gives you git in the installer

git clone https://github.com/sebastianstupak/nix-config
cd nix-config
```

> ⚠️ **Do not `cp` the generated file over
> `hosts/zagreus/hardware-configuration.nix`.** Two machines share that file
> and it is hand-merged. Overwriting it points the *other* machine at disks it
> does not have, and that machine stops booting on its next rebuild.

Compare the generated file against the committed one and merge **only** what is
genuinely missing:

- **`fileSystems`** — leave the committed `by-label` entries alone. Provided you
  labelled the partitions correctly in step 3, they already describe this
  machine. The generated UUIDs are what you are deliberately *not* using.
- **`boot.initrd.availableKernelModules`** — add any module the generator lists
  that the committed file lacks. This is a union across machines; never a
  replacement.
- **`hardware.cpu.<vendor>.updateMicrocode`** — both vendors are already there.
- **`boot.kernelModules`** — leave empty. KVM is handled by
  `systemd.services.load-kvm` in `hosts/zagreus/default.nix`.

If you changed anything, stage it:

```bash
git add hosts/zagreus/hardware-configuration.nix   # REQUIRED: flakes ignore untracked files
```

> The `git add` is not optional — Nix only sees files tracked by git, so an
> unstaged change makes the build fail with "path does not exist". (Modifications
> to already-tracked files *are* picked up, with a "Git tree is dirty" warning.)

## 6. Enrol this machine's host key in sops — BEFORE installing

**Skip this and you will not be able to log in.** The password for
`sebastianstupak` comes from `secrets/passwords.yaml`, decrypted with this
machine's SSH host key. A fresh install has a host key that is not yet a
recipient.

Generate the host key into the target now, so it exists before activation:

```bash
mkdir -p /mnt/etc/ssh
ssh-keygen -t ed25519 -N "" -C "<machine-name>" -f /mnt/etc/ssh/ssh_host_ed25519_key
chmod 600 /mnt/etc/ssh/ssh_host_ed25519_key
```

Derive its age recipient:

```bash
nix run nixpkgs#ssh-to-age -- -i /mnt/etc/ssh/ssh_host_ed25519_key.pub
```

Then **on a machine that can already decrypt** (one holding
`~/.config/sops/age/keys.txt`), add that `age1…` value to `.sops.yaml` under
`keys:` and to the `creation_rules` age list, and re-encrypt every secret:

```bash
sops updatekeys secrets/passwords.yaml
sops updatekeys secrets/calendars.yaml
sops updatekeys secrets/backup.yaml
```

Commit, push, and `git pull` in the clone from step 5 so the installer uses the
re-encrypted files. Verify from the installer before continuing:

```bash
nix run nixpkgs#ssh-to-age -- -private-key -i /mnt/etc/ssh/ssh_host_ed25519_key > /tmp/age.key
SOPS_AGE_KEY_FILE=/tmp/age.key nix run nixpkgs#sops -- \
  -d --extract '["sebastianstupak-hash"]' secrets/passwords.yaml | wc -c
rm -f /tmp/age.key
```

A byte count (~74) means it works. An error means stop and fix it now — after
the reboot the only way back in is a rescue boot plus a full rebuild.

**First-install tip (optional but recommended):** the audio profile pulls
`shibco/ableton-linux`, whose **patched Wine is a large from-source build** that can
make this first install very slow. To get a bootable system quickly, temporarily
remove the audio line, install, boot, then add it back and rebuild (possibly
overnight, or after checking the project's README for a Cachix binary cache):

```bash
# edit hosts/zagreus/default.nix and comment out this import for now:
#   ../../modules/nixos/audio.nix
```

## 7. Install

```bash
nixos-install --flake /mnt/etc/nixos/nix-config#<host> --no-root-password
```

`--no-root-password` is correct here: `root` is not declared in this config, so
with `mutableUsers = false` its shadow entry is `!` either way. You use `sudo`
via `wheel`. Skipping the prompt also means the install can run unattended.

This builds the whole system (Hyprland, apps, theming). Expect it to be slow —
the audio profile's patched Wine is a from-source build that saturates all cores
for the better part of an hour.

> ⚠️ **Do not reboot until this finishes.** `nixos-install` writes the
> bootloader as its *last* step, so an early reboot leaves the ESP empty and the
> firmware falls through to network boot (`>>Start PXE over IPv4`). Nothing is
> lost — the Nix store on disk survives and a re-run resumes — but you will have
> to redo the installer's network setup.
>
> Confirm completion before rebooting:
>
> ```bash
> ls /mnt/boot/EFI/systemd/ /mnt/boot/loader/entries/   # want: systemd-bootx64.efi + nixos-generation-1.conf
> ```

## 8. Verify the password landed

This is the check that would have caught the lockout. The shadow entry must hold
a real hash, not `!`:

```bash
awk -F: '/^sebastianstupak:/ {print length($2), substr($2,1,3)}' /mnt/etc/shadow
```

- **`73 $y$`** — good. Your password is the one in `secrets/passwords.yaml`
  (i.e. the same password as the other machine).
- **`1 !`** — locked. sops did not decrypt; go back to step 6. Do not reboot
  expecting to fix it with `passwd` — `mutableUsers = false` rewrites that entry
  on every activation, including every boot.

## 9. Check the EFI boot order

A fresh install often lands its boot entry *last*, behind network-boot entries —
which is the other way you end up staring at `>>Start PXE over IPv4`:

```bash
efibootmgr        # find the "Linux Boot Manager" entry number, e.g. 0002
efibootmgr -o 0002,<the rest, comma-separated>
```

## 10. Reboot

```bash
sync && umount -R /mnt && reboot
```

Remove the USB. You should get the systemd-boot menu → NixOS → the tuigreet login.
Log in as **sebastianstupak** → Hyprland starts.

*(If the graphical login misbehaves, switch to a TTY with **Ctrl+Alt+F2**, log in,
and check `journalctl -b -e`.)*

---

## 11. First things after first boot

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
sudo nixos-rebuild switch --flake ~/nix-config#<host>
# rollback a bad change:
sudo nixos-rebuild switch --rollback
```

**Your commit-signing key.** Every commit this config makes is signed with
`~/.ssh/id_ed25519`, which does not exist yet on a fresh machine. Make it, add
it to GitHub as **both** an authentication and a *signing* key, then **rebuild
once more**:

```bash
ssh-keygen -t ed25519 -C "you@example.com"     # no passphrase is fine; an agent holds it
gh auth login                                   # then: gh ssh-key add ~/.ssh/id_ed25519.pub
sudo nixos-rebuild switch --flake ~/nix-config#<host>
```

That last rebuild is the part that is easy to skip and hard to notice. Git's
`allowed_signers` is written during activation *from the key's contents*, so an
activation that ran before the key existed skips it silently — and git then
reports your own commits as signed by an unknown signer. Verified: activating
without a key writes nothing; activating again once the key is there writes it.

```bash
git -C ~/nix-config log -1 --show-signature   # want: Good "git" signature
```

**Keyboard:** US ↔ SK toggles with **Alt+Shift**. Handy Hyprland keys: `Super+Enter`
terminal, `Super+R` launcher, `Super+Q` close, `Super+C` clipboard history,
`Super+Shift+S` snipping tool, `Super+Shift+X` power menu, `Super+L` lock.

## 12. Secrets (sops)

This machine's recipient was already enrolled in **step 6** — that is mandatory,
not optional, because the login password depends on it. Nothing more is needed
here for an install to work.

To add a *new* secret later, or to understand the recipient model and the
lockout failure mode, see [`secrets/README.md`](../secrets/README.md).

## 13. Ableton / audio (shibco/ableton-linux)

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

- **`>>Start PXE over IPv4` instead of booting:** the firmware found no bootable
  entry, or found network-boot entries first. Either the install never reached
  the bootloader step (check `/mnt/boot/EFI/systemd/` exists — step 7), or the
  boot order needs fixing (step 9).
- **Login rejects the correct password, on every account including root:** the
  sops lockout. `/etc/shadow` will show `!` for both users. `passwd` from a
  rescue chroot appears to work and then reverts on reboot, because
  `mutableUsers = false` rewrites shadow on every activation. Fix it by enrolling
  the host key (step 6) and rebuilding, or — as a stopgap — set
  `users.mutableUsers = true` and *then* `nixos-rebuild switch` before `passwd`.
  Full mechanism in [`secrets/README.md`](../secrets/README.md).
- **Rescue access with no working login:** boot the installer USB, then
  `mount /dev/disk/by-label/nixos /mnt && mount /dev/disk/by-label/BOOT /mnt/boot
  && nixos-enter --root /mnt`. Two traps inside that chroot: `systemctl` is inert
  ("Running in chroot, ignoring command"), and `/etc/resolv.conf` needs
  `rm`-ing before it can be rewritten, or DNS silently fails. The prompt still
  shows the *installer's* hostname, so it is easy to think you have left the
  chroot when you have not — check with `readlink /proc/1/root`.
- **Won't boot after a rebuild:** pick an older generation in the systemd-boot
  menu. **A rebuild breaks the desktop:** `sudo nixos-rebuild switch --rollback`.
- **Build error mentions "path does not exist":** you added a file but didn't
  `git add` it (see step 5).
- **`nixos-rebuild` fails with `seq` / "evaluating a branch condition" noise:**
  check the flake path actually exists. Pointing `--flake ~/nix-config#<host>`
  at a directory that isn't there produces exactly this.
- **Graphics:** the AMD machine works out of the box with `hardware.graphics`; so
  does the Intel one. NVIDIA would need a module that doesn't exist yet.
```
