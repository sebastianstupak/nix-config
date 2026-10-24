# Battery, sleep and hibernation

Policy lives in `modules/nixos/power.nix` (`my.power.*`); the warnings you see
come from `modules/home/battery.nix`.

```
20%  low       normal notification                      my.power.warnPercentage
10%  critical  sticky notification (swaync never
               auto-dismisses critical ones)            my.power.criticalPercentage
 7%  action    upower hibernates, or powers off          my.power.actionPercentage
```

One set of numbers drives three things — the toast, waybar's amber/red battery
colour, and upower's action. Change a number in `hosts/common/default.nix` and
all three follow.

Two deliberate choices in there:

- **The action is upower's, not the script's.** `modules/home/battery.nix` is a
  *user* unit, so it is not running at the greeter or after logout — which is
  exactly when a laptop gets left to die. upower is a system service and keeps
  watching.
- **7%, not 5%.** The action has to finish before the battery does. Writing a
  RAM-sized hibernation image takes tens of seconds and 5% can be under three
  minutes of runtime under load.

## Hibernation is off, and why

`my.power.hibernate.enable` is `false` on both machines, and
`modules/nixos/power.nix` **asserts** that it cannot be turned on while the host
declares no LUKS device.

Hibernating writes the entire contents of RAM to `/swapfile`. That includes
`/run/secrets` — tmpfs, so it lives in RAM — the gpg/ssh agent cache (24h TTL,
see `modules/home/security.nix`), and every open session. On a plaintext root
that is a readable dump of everything the session has touched.

The sharper problem is already there without hibernation:
`modules/nixos/core.nix` derives the sops age key from
`/etc/ssh/ssh_host_ed25519_key`, which sits unencrypted on an unencrypted
ext4 root. Anyone holding the disk gets that file, and with it every secret in
`secrets/` — the restic credentials, the password hash, the calendar URLs.

So the order is: **encrypt the root, then enable hibernation.** The assertion
exists to stop the second from happening without the first.

## Part 1 — encrypt the root

This is a reinstall. `cryptsetup reencrypt --encrypt --reduce-device-size 32M`
can convert in place, but cryptsetup's own man page is blunt that during the
conversion *"the whole device must be treated as unencrypted — there are no
guarantees of confidentiality"*, and it is a long unattended run on a daily
driver. There is a tested restic repository and a declarative flake; reinstall
is the lower-risk path. One machine at a time.

**Before touching anything:** verify a restore actually works —
`docs/BACKUP.md`, "The one thing to do before you need it". Then follow
`docs/INSTALL.md` with these changes.

### Step 3 (partition and format)

```bash
DISK=/dev/nvme0n1        # confirm with lsblk

parted "$DISK" -- mklabel gpt
parted "$DISK" -- mkpart ESP fat32 1MiB 1025MiB
parted "$DISK" -- set 1 esp on
parted "$DISK" -- mkpart cryptroot 1025MiB 100%

mkfs.fat -F 32 -n BOOT /dev/nvme0n1p1

# LUKS2. The passphrase typed here is what unlocks the machine at every boot.
cryptsetup luksFormat --type luks2 --label cryptroot /dev/nvme0n1p2
cryptsetup open /dev/nvme0n1p2 cryptroot

# The ext4 label goes on the MAPPED device, so the committed
# fileSystems."/" = /dev/disk/by-label/nixos keeps working untouched — the
# two-machines-one-hardware-config trick survives encryption unchanged.
mkfs.ext4 -L nixos /dev/mapper/cryptroot
```

Mount as INSTALL.md says (`/dev/disk/by-label/nixos`, then `BOOT` at
`/mnt/boot`) — those paths do not change.

### Step 5 (hardware config)

`hosts/common/hardware-configuration.nix` is hand-merged and must not be
regenerated (rule 7 in `AGENTS.md`). The `fileSystems` entries stay exactly as
they are. Add, by hand:

```nix
  # Root is LUKS2. The container is addressed by GPT partition label so that
  # both machines can share this one line, the same reason the filesystems are
  # by-label rather than by-uuid.
  boot.initrd.luks.devices.cryptroot = {
    device = "/dev/disk/by-partlabel/cryptroot";
    # TRIM passthrough to the SSD. The cost is that an attacker can see which
    # blocks are unused — how full the disk is, roughly. The benefit is that
    # the drive does not degrade into permanent write amplification.
    allowDiscards = true;
  };
```

Both machines need the same partition label for that line to work, so encrypt
them the same way. Until the second one is converted, keep the line in
`hosts/<host>/default.nix` instead of the shared file — a machine with no
`cryptroot` partition will sit in the initrd waiting for a device that is never
coming.

Nothing else changes: `boot.initrd.systemd.enable` is already on, which is what
makes the unlock-then-resume ordering work.

### Unlocking it

**Use a passphrase.** It is one prompt per cold boot, and nothing about it can
be subtly wrong.

TPM2 auto-unlock is tempting and, on these machines as they stand, close to
worthless on its own: Secure Boot is **disabled** and the kernel is not a signed
UKI (`bootctl status` → `Measured UKI: no`). That makes the unseal bypassable —
substitute a fake LUKS container carrying the original UUID, let the TPM unseal
fail, unlock the fake with your own password, and the initrd runs *your* `init`
with TPM access and no signature check, which then extracts the real volume key.
PCRs 0–7 never noticed. See
<https://oddlama.org/blog/bypassing-disk-encryption-with-tpm2-unlock/>.

If you want it anyway, the PIN is what carries the security, not the TPM:

```bash
sudo systemd-cryptenroll /dev/nvme0n1p2 \
  --tpm2-device=auto --tpm2-with-pin=yes --tpm2-pcrs=7
```

...and add `crypttabExtraOpts = [ "tpm2-device=auto" ]` to the LUKS device
above. Making PCR 7 mean anything needs Secure Boot plus signed boot artifacts
(lanzaboote) — a separate project, and the prerequisite for ever dropping the
PIN.

**Residual risk either way:** `/boot` stays unencrypted and unsigned, so a
backdoored initrd is an available attack against someone who gets the machine
twice. Encryption at rest is what this buys; boot integrity is what Secure Boot
would add.

### After the reinstall

Re-enrol the host key in `.sops.yaml` — a fresh install means a fresh
`/etc/ssh/ssh_host_ed25519_key`, and the old recipient decrypts nothing. This is
INSTALL.md step 6 and "The lockout" in `secrets/README.md`; getting it wrong
locks you out of the password hash.

## Part 2 — enable hibernation

Once root is LUKS, in `hosts/<host>/default.nix`:

```nix
  my.power.hibernate = {
    enable = true;
    swapSizeMiB = 32768; # hestia: 30 GiB RAM.  zagreus (16 GiB RAM): 20480
  };
```

Sized at or above RAM: systemd refuses to hibernate when free swap cannot hold
the image, and the image is bounded by memory in use, so RAM-sized is the only
size that always works. Check the disk has room first (`df -h /`) — hestia had
772G free, zagreus is the smaller disk.

Switch once. That creates and `mkswap`s `/swapfile`; confirm:

```bash
swapon --show          # /swapfile, prio 0, next to /dev/zram0 at prio 5
```

zram needs no changes. systemd deliberately skips zram and zswap when choosing
somewhere to hibernate, and `/swapfile` sits below zram in priority, so normal
memory pressure goes to zram and the file stays free for the image.

**Then test it by hand, before trusting it at 7% in a café:**

```bash
systemctl hibernate
# press power, unlock, and check the session came back
journalctl -b -u systemd-hibernate.service
journalctl -b 0 | grep -i 'hibernat\|resum'
```

Only once that works do the automatic paths matter, and they then come for free:

- the lid becomes `suspend-then-hibernate`
- hypridle's 10-minute idle action becomes `suspend-then-hibernate`
  (`modules/home/hyprland.nix`)
- upower's 7% action becomes `Hibernate` instead of `PowerOff`

`HibernateDelaySec` is deliberately **not** set. Left unset, systemd uses the
ACPI `_BTP` low-battery alarm to wake a suspended machine and hibernate it as
the battery approaches 5% — both machines populate
`/sys/class/power_supply/BAT0/alarm`, so the trip point works. Setting a delay
*disables* that and replaces it with periodic timed wakeups: more drain, and
hibernation on a clock rather than on need.

### If resume does not work

The modern path needs no kernel arguments: with `boot.initrd.systemd.enable`,
systemd-sleep picks the swap area itself and records it in the
`HibernateLocation` EFI variable, which `systemd-hibernate-resume` reads at
boot. If that misbehaves, fall back to naming it explicitly — in
`hosts/<host>/default.nix`, because the offset is per-machine:

```bash
sudo filefrag -v /swapfile | awk '$1=="0:" {print $4}'   # strip the trailing ".."
```

```nix
  boot.resumeDevice = "/dev/mapper/cryptroot";   # the MAPPED device, not the LUKS partition
  boot.kernelParams = [ "resume_offset=<the number above>" ];
```

The offset changes if the swapfile is ever recreated. Re-read it after anything
that deletes `/swapfile`.

## Things that will bite

- **Do not `nixos-rebuild switch` with a hibernation image pending.** A changed
  kernel or initrd can make the kernel refuse the image (*"Hibernate
  inconsistent memory map"*), and systemd-boot's one-shot entry can name a file
  the newer generation renamed. Resume first, then switch.
- **Per-machine verification.** A clean hibernate on hestia proves nothing about
  zagreus. Test each.
- **`randomEncryption` is not an option.** The usual "encrypted swap" one-liner
  is incompatible with hibernation by design — NixOS's own warning: *"Don't try
  to hibernate when you have at least one swap partition with this option
  enabled… you would lose it!"* The key must persist, which is why swap lives
  inside the encrypted root instead.
- **Charge limiting is not available on hestia.** Capping charge at ~80% roughly
  doubles cell life, but `BAT0` exposes no `charge_control_end_threshold` — HP's
  firmware does not surface it to the kernel on this ZBook, so TLP's
  `START_CHARGE_THRESH_BAT0` would be silently inert. The only lever is HP's
  BIOS battery-care setting. Worth re-checking on zagreus:
  `ls /sys/class/power_supply/BAT0/ | grep charge_control`.
- **Kernel-level hibernation image encryption** (which would let swap stay
  plaintext) is an RFC on linux-pm, not upstream. Not a shortcut around Part 1.
