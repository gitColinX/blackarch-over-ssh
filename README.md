# BlackArch Linux on a Dell laptop, driven from Windows over SSH

Most "how to install BlackArch" guides tell you what to type at the laptop's keyboard. This one does
something different: as soon as the live ISO booted, the laptop was turned into an SSH target, and
everything after that, including the interactive installer's 37 prompts, was run from a second
computer with prepared, copy-pasteable commands and a small pty driver. No typos on a bare TTY, no
walking back to the keyboard, and a full log of every step.

This is a documented, repeatable install of [BlackArch Linux](https://blackarch.org/) (Arch Linux
plus the 2,800-tool BlackArch repository) on a Dell laptop, with the whole thing driven from a Windows
PC: ISO verification, writing the USB stick without Rufus, the SSH pivot, the unattended install, and
the post-install setup of drivers, firmware and a daily-driver desktop.

Done on 2026-10-06 in one evening with Claude Code as the operator. Everything in this repo is what
actually ran, including the mistakes and the fixes.

## Why this exists

BlackArch's ISOs date from 2023 and the project itself says the 22 GB "full" ISO is "highly
discouraged". The supported path is the 815 MB netinstall ISO plus `pacman -S blackarch` afterwards,
which gives you every tool at its *current* version. The catch is that a 2023 live ISO has stale
keyrings, references the retired Arch `community` repo, and the installer asks ~35 questions on a
bare TTY. All of that is handled here.

## The pieces

| File | What it does |
|---|---|
| [`Write-IsoToUsb.ps1`](Write-IsoToUsb.ps1) | Windows-native `dd`: self-elevates, verifies the ISO's SHA1 against blackarch.org, refuses non-USB or system disks, raw-writes the hybrid ISO, verifies the first MB. No Rufus, no UNetbootin (BlackArch forbids it). |
| [`Tools/drive-install.sh`](Tools/drive-install.sh) | Runs `blackarch-install` inside a pty (`script`) and answers every prompt from a table: install mode, locale, network, disk, LUKS, partitions, users, timezone, mirror, X11, window managers. Pre-partition the disk with `sfdisk` and it needs no human at all. |
| [`Tools/post-install-chroot.sh`](Tools/post-install-chroot.sh) | Before the first reboot: opens the new encrypted root, enables `sshd` and installs your SSH public key for root and the user, so the installed system is reachable on first boot. |
| [`Tools/post-tools-desktop.sh`](Tools/post-tools-desktop.sh) | After `pacman -S blackarch`: daily-driver desktop (GNOME, dock from the AUR via `paru`), NetworkManager, PipeWire, Bluetooth, `nvidia-open` + PRIME, fwupd firmware updates, performance power profile, TRIM timer. |
| [`Tools/Build-Guides.ps1`](Tools/Build-Guides.ps1) | Turns every `.md` in a folder into a styled `.html` and a `.pdf` (python-markdown + Edge headless). |
| [`INSTALL.md`](INSTALL.md) | The full walkthrough with the answer table, Dell-specific notes, first-boot steps and the lessons learned. Also as [PDF](INSTALL.pdf) and [HTML](INSTALL.html). |

## How it went (timeline)

1. **ISO choice and stick.** Netinstall ISO, SHA1 verified, raw-written to a 128 GB USB stick from
   PowerShell in 14 s. The partition table on the stick was byte-compared against the ISO's own.
2. **Live boot and first fixes.** Logged in on the laptop, found the dock's Ethernet already up.
   `pacman -Sy` failed with a 404 on `community.db`: Arch merged that repo into `extra` a month after
   the ISO was built. One `sed` on `/etc/pacman.conf` fixed it, then refreshed both keyrings and
   pulled the current `blackarch-installer` (1.2.25, much newer than the website tutorial describes).
3. **Pivot to SSH.** Started `sshd` on the live system, which refused root password logins by
   default (`PermitRootLogin prohibit-password` earlier in the file wins over an appended line).
   Installed a key instead, after discovering the key had been generated with a two-character
   passphrase of `""` thanks to PowerShell quoting. From here on every command ran from Windows.
4. **Unattended install.** `sfdisk` made 1 GB EFI / 32 GB swap / rest root. `drive-install.sh` ran
   the installer in a pty and answered 37 prompts in under 15 minutes, including the LUKS passphrase
   and `passwd` prompts that only accept input from a terminal. One surprise: the current `strap.sh`
   asks "Perform full system upgrade?", which stalled the driver for five minutes until it was fed
   through the same FIFO. The driver now knows that prompt.
5. **First boot.** `post-install-chroot.sh` enabled SSH in the new system before reboot. The laptop
   came up on the network with a new address and was reachable immediately.
6. **All the tools.** `pacman -S blackarch`: 6,028 packages, 25 GB download, 77 GB installed,
   90 minutes. 29 tools' post-install hooks failed (old Ruby gems, pinned Python 2 deps); the
   packages are installed regardless.
7. **Desktop and drivers.** First run aborted: Arch's NVIDIA package is `nvidia-open` now, not
   `nvidia`, and one bad name aborts the whole batch. Second run succeeded, but the module was built
   for kernel 7.2.9 while 7.2.8 was running, because the repo moved between the first update and
   the setup script's `-Sy`. `pacman -Syu` and a reboot fixed it. Lesson: full upgrade first, always.
8. **Verified:** `nvidia-smi` sees the RTX laptop GPU, `hashcat -I` lists CUDA, Wi-Fi and Bluetooth up,
   audio on the dock's soundbar, fwupd sees the dock, performance profile active.

## Reusing it

- Any UEFI x86-64 laptop: change `DISK`, user, hostname and timezone on the `drive-install.sh`
  command line. For a legacy-BIOS machine the installer takes a `dos` label and an ext4 boot
  partition; the driver's partition answers would need to change.
- The temporary secrets (`blackarch` for LUKS, root and the user) are deliberate so the run can be
  unattended. Change all three at first login; the guide has the three commands.
- The driver is generic "expect in bash": `step '<prompt regex>' '<answer>'`. It is easy to adapt to
  any other TTY installer.

## Credits

BlackArch Linux team for the distro and the `blackarch-installer`. Written up and operated with
Claude Code (Anthropic) from the Windows side.
