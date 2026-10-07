# BlackArch Linux on a Dell laptop, driven over SSH - step by step

Source: blackarch.org/downloads.html, blackarch.org/blackarch-install.html and the official PDF
guide (blackarch-guide-en.pdf from blackarch.org/guide.html, section 2.1.5). Dell-specific notes are marked **Dell**.

## 0. Which ISO and why (read this once)

| ISO | Size | Date | Verdict |
|---|---|---|---|
| Full | 22 GB | 2023-04-01 | BlackArch's own page: "highly discouraged ... many errors and conflicts". Frozen 2023 packages. |
| Slim | 5.5 GB | 2023-05-01 | GUI installer, a curated subset of tools. |
| **Netinstall** | 815 MB | 2023-04-01 | **Official recommendation.** Bootstrapper only; everything is pulled fresh from the repos. |

"Most complete" = netinstall + `pacman -S blackarch` after first boot. That installs **every** tool
currently in the repo (2800+, newer than anything on the full ISO) with no 2023-vs-2026 conflicts.

## 1. Write the stick (Windows PC)

```powershell
cd C:\Projects\BlackArch
.\Write-IsoToUsb.ps1 -IsoPath "$env:USERPROFILE\Downloads\blackarch-linux-netinst-2023.04.01-x86_64.iso" -DiskNumber 2 -ExpectedSha1 df2dfcfafa1a8f9bab8afd9aa6b788de00e03e09
```
It elevates itself, checks the SHA1, shows the target disk, asks you to type `2`, wipes the stick
and dd's the ISO. When Windows says "format this disk?" click **Cancel**. Eject.

> Check the disk number first with `Get-Disk` - the 128 GB stick was disk 2 in our case.

## 2. Dell BIOS (F2 at the Dell logo)

- **Secure Boot: OFF** (the BlackArch ISO is not signed).
- SATA/NVMe operation: **AHCI/NVMe**, not RAID/RST (Linux won't see the SSD under RST).
- Boot the stick: power on, tap **F12**, pick the **UEFI** entry for the USB stick.
- At the ISO menu choose **BlackArch Linux (x86_64)**.

## 3. Network - do this BEFORE starting the installer

**Dell:** the laptop has no Ethernet port and the installer script does not do Wi-Fi.
Easiest: plug a USB-C Ethernet adapter / dock. Otherwise connect Wi-Fi by hand, then choose
**Skip** at the installer's network step:

```bash
ip a                              # find the wifi interface name (wlan0 / wlp0s20f3)
iwctl                             # if present
  station wlan0 scan
  station wlan0 get-networks
  station wlan0 connect "YourSSID"   # asks for the password
  exit
# if iwctl is missing, try:  wifi-menu
ping -c 2 archlinux.org
```

Log in as `root`, password `blackarch` (live ISO defaults).

## 4. Fix the 2023 keyrings (prevents "signature is unknown trust" failures)

The ISO is from 2023; refresh the keys before installing anything:

```bash
pacman -Sy archlinux-keyring blackarch-keyring
pacman-key --init
pacman-key --populate archlinux blackarch
```

## 5. Run the installer

Run it over SSH from the Windows PC (tmux/screen from today's repos will not run on the 2023 live
system, so keep the dock cable plugged in; if the SSH tab dies, reconnect and start the installer again).

```bash
pacman -Sy blackarch-installer     # get the current installer (1.2.25 on 2026-10-06)
ssh -t root@<live-iso-ip> blackarch-install
```
Answers for installer 1.2.25 (prompts appear in this order):

| Prompt | Answer |
|---|---|
| Choose an installation mode | **1** - Install from repository using pacman |
| Output mode (verbose/quiet) | **1** verbose, so errors are visible |
| Set locale | Enter (`en_US.UTF-8`) |
| Keymap | Enter (`us`) |
| Set your hostname | e.g. `blackarch-laptop` |
| Network interface | `eth0` (the dock) |
| Network mode | **1** Auto DHCP |
| Install with Windows/Other OS (dualboot) | **n** |
| Full encrypted root (LUKS) | your call. `y` = passphrase at every boot, data safe if laptop is lost. |
| Please choose a device | `nvme0n1` (the 1 TB NVMe). **This erases the SSD.** Never `sda`, that is the USB stick. |
| Create partitions with cfdisk | `y` |
| Start with an in-memory zeroed partition table | `y` (wipes the old Omarchy layout) |
| cfdisk: label type | **gpt** |
| cfdisk: partition 1 | New -> `1G` -> Type -> **EFI System** |
| cfdisk: partition 2 | New -> `32G` -> Type -> **Linux swap** (matches RAM, allows hibernate) |
| cfdisk: partition 3 | New -> Enter (rest of disk) -> leave as Linux filesystem; **Write** -> `yes` -> **Quit** |
| EFI System partition | `1` (the installer expands it to `/dev/nvme0n1p1`; fat32 is automatic) |
| Root partition / filesystem | `3` / Enter (ext4) |
| Swap partition | `2` |
| Partition table correct | `y` |
| Timezone (Zone/SubZone) | `America/New_York` (adjust) |
| root password, user name + password | set both; don't run as root day to day |
| Select a mirror number | Enter for default |
| Setup X11 + window managers | **y** (installs LXDM login screen + window managers) |
| Choose window managers [6] | Enter = all five (Awesome, Fluxbox, i3, Openbox, Spectrwm). Pick Openbox at login for a normal mouse-driven desktop. |
| VirtualBox / VMware guest tools | **n** (real hardware) |
| Setup BlackArch Linux tools | **n** - do it after first boot (step 7) over SSH where errors can be handled |

Reboot, remove the stick.

## 5b. Unattended run (what we actually did on 2026-10-06)

`Tools\drive-install.sh` runs the installer inside a pty on the live ISO and types every answer
(partitions were made first with `sfdisk`: 1G EFI / 32G swap / rest root, LUKS on root). Launch from
Windows:

```bash
scp C:\Projects\BlackArch\Tools\drive-install.sh root@<live-iso-ip>:/root/
ssh root@<live-iso-ip> "sed -i 's/\r$//' /root/drive-install.sh; chmod +x /root/drive-install.sh; setsid nohup /root/drive-install.sh blackarch-laptop pentester America/New_York nvme0n1 > /root/driver.out 2>&1 < /dev/null &"
```
Progress: `ssh root@<live-iso-ip> cat /root/driver.log`. Full installer output: `/root/install.log`.
It sets **temporary** secrets, all `blackarch`: LUKS passphrase, root password, user password.

## 6. First boot - change the three temporary secrets FIRST

At the boot prompt "Enter passphrase" type `blackarch`. Log in as `pentester` / `blackarch`, then:

```bash
passwd                                        # your user password
sudo passwd root                              # root password
sudo cryptsetup luksChangeKey /dev/nvme0n1p3  # disk passphrase: asks old (blackarch), then new twice
```
Verify the new disk passphrase before you forget the old one: `sudo cryptsetup open --test-passphrase /dev/nvme0n1p3`.

The installed system came up at **<laptop-ip>** (the live ISO had .172). The Windows PC's SSH key was
pre-installed for root and pentester, so from Windows: `ssh pentester@<laptop-ip>`.

Then:
```bash
sudo pacman -Syyu            # full system update
```
**Dell:** if Wi-Fi is missing after install: `sudo pacman -S iwd` then `sudo systemctl enable --now iwd`
(or `networkmanager` + `nmtui`). Firmware for the Intel AX211 card is in `linux-firmware`, already pulled in.

## 7. Install EVERYTHING

```bash
sudo pacman -S blackarch     # all 2800+ tools; press Enter to accept defaults. Needs ~40-60 GB.
```
Takes a while. If it stops with "failed to commit transaction / conflicting files", the official fix is:
```bash
sudo pacman -Syyu --needed --overwrite='*' blackarch
```
Or install by category instead: `pacman -Sg | grep blackarch` then `sudo pacman -S blackarch-<category>`.

Done 2026-10-06 16:56-18:29 MDT: 2,855 tools / 6,028 packages, 25 GB download, 130 GB on disk.
29 tools had non-fatal post-install hook failures (old Ruby gems / pinned Python deps); the packages
are installed, those tools may need their own setup the first time. The list is in the pacman log (`grep "command failed" /var/log/pacman.log`).

## 7b. Daily-driver desktop, drivers, firmware, performance (what we ran)

`Tools\post-tools-desktop.sh` (run as root after the tools): GNOME + GDM login screen, Ubuntu-style
dock (`gnome-shell-extension-dash-to-dock` from the AUR via paru), tray icons, Firefox, NetworkManager,
PipeWire audio, Bluetooth, `nvidia-open` + `nvidia-utils` + `nvidia-prime` (RTX laptop GPU), Intel media
driver, fwupd, power-profiles-daemon set to **performance**, weekly `fstrim.timer`.

Lessons:
- The Arch package is **`nvidia-open`** now (not `nvidia`) for RTX cards. A wrong name aborts the whole pacman batch.
- Always `sudo pacman -Syu` **before** installing anything. The repo kernel moved 7.2.8 -> 7.2.9 during our
  session, so the NVIDIA module was built for a kernel that was not running yet. Full upgrade + reboot fixed it.
- Run the GPU on demand: `prime-run <program>` sends that program to the NVIDIA card; the Intel GPU drives
  the desktop. `hashcat -I` lists both once `opencl-nvidia` is installed.
- After switching to NetworkManager the laptop got a new DHCP address (<laptop-ip>). Use `ssh pentester@blackarch-laptop`
  or check `ip -br a` on the laptop.

## 7c. Choosing a desktop (several are installed, pick at the login screen)

Installed on blackarch-laptop: **GNOME** (Wayland only), **KDE Plasma** (Wayland + X11), **Cinnamon** (X11 and
Wayland), **Xfce**, plus the five bare window managers from the installer (awesome, fluxbox, i3,
openbox, spectrwm - keyboard-driven, skip them). To switch: log out, click your name at the GDM login
screen, then the **gear icon bottom-right**, pick a session, enter the password. GDM remembers the last
choice per user.

| Desktop | Feel | BlackArch tool menu (categories) |
|---|---|---|
| KDE Plasma | Windows-like taskbar + start menu, most configurable, good on NVIDIA | yes (start menu) |
| Cinnamon | Linux Mint; simplest, bottom panel + menu | yes |
| GNOME | Ubuntu-like dock + Activities overview | no (flat app grid; add the ArcMenu extension for categories) |
| Xfce | lightweight, traditional | yes |

"X11" vs "Wayland" entries: same desktop, different display system. Wayland is newer and smoother;
X11 is the one almost every pentest GUI tool was written for (screen capture, Java apps, Burp,
Wireshark). On this laptop prefer the **X11** entry when a tool misbehaves. The Xfce Wayland entry
needs `labwc`, which is not installed, so it just bounces back to the login screen.

Install/remove desktops with pacman, e.g. `sudo pacman -Rns xfce4 xfce4-goodies` once you have settled.

## 8. If the installer dies at the ping check

The script aborts when `ping github.com` fails (firewalls that drop ICMP). Official workaround:
edit `/usr/bin/blackarch-install`, find the block starting `if ! ping -c 1 github.com` (around line 545)
and delete through its `fi`, then rerun `blackarch-install`.

## Plan B - plain Arch first, BlackArch on top

If `blackarch-install` won't cooperate on this laptop, install vanilla Arch (archinstall or Omarchy)
and then, as root:
```bash
curl -O https://blackarch.org/strap.sh
echo d338a4bb95d9e09f97508da68ac9e17d963b85f6 strap.sh | sha1sum -c
chmod +x strap.sh && sudo ./strap.sh
sudo pacman -Syu && sudo pacman -S blackarch
```
Result is the same repo and the same tools - that is literally what the netinstall path does.

## 9. Dell laptop hardware notes (Linux has no "driver pack" step)

Linux drivers live inside the kernel and the `linux-firmware` package. Both are installed by the
installer automatically, so there is nothing to slipstream onto the stick (the stick is a read-only
dd image anyway). The only things to add are done AFTER install, with pacman:

| Hardware | Status | After install |
|---|---|---|
| Thunderbolt dock Ethernet (Realtek) | in-kernel `r8152` / `r8169` - works in the live ISO, pick **Auto DHCP** | nothing |
| Intel AX211 Wi-Fi / Bluetooth | in-kernel `iwlwifi` + firmware | `sudo pacman -S networkmanager && sudo systemctl enable --now NetworkManager` then `nmtui` |
| Intel Iris Xe iGPU | in-kernel `i915` | `sudo pacman -S mesa intel-media-driver` |
| NVIDIA RTX laptop GPU (this laptop) | boots on `nouveau`; proper driver is `nvidia-open` | `sudo pacman -Syu nvidia-open nvidia-utils nvidia-prime opencl-nvidia` then reboot; verify with `nvidia-smi` |
| Touchpad, audio, webcam, USB-C | in-kernel | nothing (audio: `sudo pacman -S pipewire pipewire-pulse wireplumber`) |
| Fingerprint reader (Goodix) | not supported on Linux | skip |

Dock tips: in BIOS keep **Thunderbolt > Enable Thunderbolt Boot Support** ON and security level
"No security" or "User Authorization"; plug the dock in before powering on so the live ISO sees it.
Check with `ip a` - the dock NIC shows as `enp...` or `eth0`; `ping -c 2 archlinux.org` must answer.

## 10. Talking to Claude while installing

Keep this Claude Code session open on the Windows PC. Photograph the Dell screen with your phone and
paste the photo into the chat; that is enough to read error messages. Or type the exact prompt text.
