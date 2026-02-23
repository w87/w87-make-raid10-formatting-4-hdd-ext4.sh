# [w87-make-raid10-formatting-4-hdd-ext4.sh](https://w87.eu/code/raid10/)
## Summary

**w87-make-raid10-formatting-4-hdd-ext4.sh** — A stepwise Bash utility to wipe specified disks, partition them, create a RAID10 array, format it with ext4, mount it at specified directory, persist the configuration, run final checks and tune read-ahead.

## Author
[Walerian Walawski](https://w87.eu/)

## Step-by-step behavior

- **Privilege check**: Exits unless run as root.
- **Help / usage**: If no argument or `-h`/`--help` is passed, prints usage, step descriptions, and script metadata (author, license).
- **step1 — Wipe disks**: For sda, sdb, sdc, sdd:
  - Runs `wipefs -a $disk` to clear filesystem signatures.
  - Runs `mdadm --zero-superblock $disk` to remove RAID metadata.
- **step2 — Create partitions**:
  - Uses `parted -s $disk mklabel gpt` to create a GPT label.
  - Creates a single primary partition spanning the whole disk: `parted -s $disk mkpart primary 0% 100%`.
  - Flags the partition as RAID with `parted -s $disk set 1 raid on`.
  - Shows the created partition device nodes (sda1 ...).
- **step3 — Create RAID10**:
  - Runs `mdadm --create /dev/md0 --level=10 --raid-devices=4 --layout=n2 --bitmap=internal /dev/sd[a-d]1` to build a 4-device RAID10 using layout n2 and internal bitmap.
  - Polls `mdadm --detail /dev/md0` and mdstat until the array becomes active.
- **step4 — Format and mount**:
  - Formats `/dev/md0` with `mkfs.ext4` using: label `www`, `-E stride=128,stripe-width=256`, `-O dir_index,filetype`, and `-m 0` (0% reserved).
  - If www exists, moves it to `/var/www_backup`, creates www, then mounts `/dev/md0` there with `noatime,nodiratime,commit=60`.
- **step5 — Make persistent**:
  - Appends `mdadm --detail --scan` output to `/etc/mdadm/mdadm.conf`.
  - Runs `update-initramfs -u`.
  - Shows `/etc/mdadm/mdadm.conf`, runs `blkid /dev/md0` to show UUID, then appends an fstab entry using the UUID to mount www with the same mount options.
- **step6 — Final check and status**:
  - Runs `mount -a`, shows `mdadm --detail /dev/md0` and `df -h`.
  - Enables/starts `smartd` (or `smartmontools.service`) and shows its status.
  - Runs `smartctl -a` on each disk to display SMART data.
- **step7 — Read-ahead tuning**:
  - Shows current read-ahead: `blockdev --getra /dev/md0`.
  - Sets read-ahead to `4096` with `blockdev --setra 4096 /dev/md0`.
  - Writes a udev rule `99-md0-read-ahead.rules` to set `ATTR{bdi/read_ahead_kb}="2048"` for `md0`, reloads udev, triggers it, and re-reads the value.

## Safety notes & important caveats

- **Data destruction**: Steps 1–3 irreversibly wipe disks and RAID metadata. Run only on machines where you have full backups and on the intended disks.
- **Fixed device names**: Script uses hardcoded sda…sdd. On systems with different device naming (hot-plug, NVMe, different order), this may target the wrong drives. Prefer using WWN/UUID or confirm device mapping before running.
- **Partition alignment / options**: `parted mkpart primary 0% 100%` is simple but may need alignment/partition type checks for specific hardware.
- **Filesystem options**: `-m 0` sets reserved blocks to 0% — useful for data servers but removes root-rescue space for non-root users; confirm intent.
- **fstab append**: The script appends to fstab and `/etc/mdadm/mdadm.conf` without checking duplicates — repeated runs will duplicate entries.
- **udev rule correctness**: The appended udev rule line uses ACTION=="add|change" but quotes and matching are literal; validate the rule syntax and the correct attribute path on the kernel version in use. Also the script sets blockdev read-ahead to 4096 (units are 512-byte sectors for blockdev --setra), while the udev rule sets `read_ahead_kb=2048` — be aware of the units and intended values.
- **Services**: The script tries `systemctl enable smartd || systemctl enable smartmontools.service` — which may behave differently across distros. It starts `smartd` unconditionally afterward.
- **Error handling**: The script is minimal on error checks (many commands run without verifying return codes). Monitor outputs and stop if something fails.

## Quick recommended pre-run checks

- Confirm device-to-disk mapping:
  - `lsblk -o NAME,KNAME,SIZE,MODEL,WWN,MOUNTPOINT` and verify which physical drives correspond to `/dev/sdX`.
- Back up any data on the disks.
- Run the script step-by-step (e.g., `.w87-make-raid10-formatting-4-hdd-ext4.sh step1`, inspect, then continue).
- Consider editing the script to:
  - Use a configurable device list variable instead of hardcoded `/dev/sd{a,b,c,d}`.
  - Check return codes and bail on failures.
  - Prevent duplicate entries when appending to fstab and `/etc/mdadm/mdadm.conf`.

## License
**CC BY-SA 4.0** — [ATTRIBUTION-SHAREALIKE 4.0 INTERNATIONAL](https://creativecommons.org/licenses/by-sa/4.0/) (also in LICENSE.md).

### You are free to:
* Share — copy and redistribute the material in any medium or format for any purpose, even commercially.
* Adapt — remix, transform, and build upon the material for any purpose, even commercially.
* The licensor cannot revoke these freedoms as long as you follow the license terms.
### Under the following terms:
* Attribution — You must give appropriate credit , provide a link to the license, and indicate if changes were made . You may do so in any reasonable manner, but not in any way that suggests the licensor endorses you or your use.
* ShareAlike — If you remix, transform, or build upon the material, you must distribute your contributions under the same license as the original.
