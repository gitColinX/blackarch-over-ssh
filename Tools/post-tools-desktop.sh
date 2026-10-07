#!/bin/bash
# Run as root on blackarch-laptop AFTER `pacman -S blackarch` has finished.
# Adds a daily-driver desktop (GNOME with an Ubuntu-style dock), NetworkManager, audio,
# Bluetooth, NVIDIA + Intel graphics drivers, Dell firmware updates (fwupd), power profiles.
set -u
LOG=/root/post-tools-desktop.log
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date) post-tools-desktop start ==="

while [ -f /var/lib/pacman/db.lck ]; do echo "pacman busy, waiting..."; sleep 30; done

PKGS="gnome gnome-tweaks gnome-shell-extension-appindicator paru base-devel git sassc
networkmanager
firefox xdg-utils xdg-user-dirs gvfs gvfs-mtp
pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol
bluez bluez-utils blueman
nvidia-open nvidia-utils nvidia-settings nvidia-prime mesa intel-media-driver libva-utils
fwupd power-profiles-daemon
noto-fonts noto-fonts-emoji ttf-dejavu ttf-liberation"

echo "== installing desktop + drivers =="
pacman -Sy --needed --noconfirm --overwrite='*' $PKGS
echo "pacman exit: $?"

echo "== dash-to-dock from AUR (built as pentester, installed as root) =="
su - pentester -c 'rm -rf ~/aur/dash-to-dock; mkdir -p ~/aur && git clone -q https://aur.archlinux.org/gnome-shell-extension-dash-to-dock.git ~/aur/dash-to-dock && cd ~/aur/dash-to-dock && makepkg --noconfirm -f' 2>&1 | tail -n 3
pkg=$(ls /home/pentester/aur/dash-to-dock/*.pkg.tar.* 2>/dev/null | head -1)
if [ -n "$pkg" ] && pacman -U --noconfirm "$pkg"; then
  DOCK='dash-to-dock@micxgx.gmail.com'
else
  echo "AUR build failed, falling back to dash-to-panel (official repo)"
  pacman -S --needed --noconfirm gnome-shell-extension-dash-to-panel
  DOCK='dash-to-panel@jderose9.github.com'
fi
echo "dock extension: $DOCK"

echo "== switching to NetworkManager (eth0 keeps its DHCP lease, brief SSH blip) =="
systemctl disable --now systemd-networkd-wait-online.service 2>/dev/null
systemctl enable NetworkManager
systemctl disable systemd-networkd iwd 2>/dev/null
systemctl start NetworkManager
sleep 3
systemctl stop systemd-networkd iwd 2>/dev/null
nmcli -t -f DEVICE,STATE,CONNECTION dev 2>/dev/null

echo "== services =="
systemctl enable --now bluetooth power-profiles-daemon
# GDM replaces LXDM as the login screen at reboot (do not stop lxdm now, the user is logged in)
systemctl disable lxdm
systemctl enable gdm
systemctl is-active NetworkManager bluetooth power-profiles-daemon | paste -sd' '

echo "== user dirs + GNOME defaults for pentester (apply at next GNOME login) =="
su - pentester -c 'xdg-user-dirs-update' 2>/dev/null
cat > /tmp/gnome-defaults.sh <<EOF
gsettings set org.gnome.shell enabled-extensions "['$DOCK', 'appindicatorsupport@rgcjonas.gmail.com']"
gsettings set org.gnome.shell.extensions.dash-to-dock dock-position BOTTOM 2>/dev/null
gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed true 2>/dev/null
gsettings set org.gnome.shell.extensions.dash-to-dock extend-height false 2>/dev/null
gsettings set org.gnome.desktop.interface color-scheme prefer-dark
gsettings set org.gnome.shell favorite-apps "['firefox.desktop', 'org.gnome.Console.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Settings.desktop']"
EOF
chmod 755 /tmp/gnome-defaults.sh
su - pentester -c 'dbus-run-session -- /tmp/gnome-defaults.sh' 2>&1 | grep -v "^$"
ls /usr/share/xsessions/ /usr/share/wayland-sessions/ 2>/dev/null | paste -sd' '

echo "== graphics =="
mkinitcpio -P >/dev/null 2>&1 && echo "initramfs regenerated"
lspci -k | grep -A3 -E 'VGA|3D' | grep -E 'VGA|3D|Kernel driver'

echo "== performance tuning =="
systemctl enable --now fstrim.timer
powerprofilesctl set performance 2>/dev/null && echo "power profile: $(powerprofilesctl get)"
cat /sys/devices/system/cpu/intel_pstate/status 2>/dev/null | sed 's/^/intel_pstate: /'
nvme list 2>/dev/null | tail -n +3 | cut -c1-80

echo "== firmware (fwupd) =="
fwupdmgr refresh --force 2>&1 | tail -n 2
fwupdmgr get-updates 2>&1 | tail -n 25

echo "=== $(date) post-tools-desktop done. Reboot to load the NVIDIA driver and start GNOME (GDM). ==="
