#!/bin/bash
# Run on the live ISO AFTER blackarch-install finishes and BEFORE reboot.
# Opens the new encrypted root, enables sshd in it and installs the Windows PC's
# SSH public key for root and the normal user, so the installed system is reachable
# over SSH on first boot. Usage: post-install-chroot.sh <user> [root-partition] [efi-partition]
set -e
USER_NEW="${1:-pentester}"
ROOT_PART="${2:-/dev/nvme0n1p3}"
EFI_PART="${3:-/dev/nvme0n1p1}"
PUBKEY="$(cat /root/.ssh/authorized_keys)"

MAP=$(ls /dev/mapper | grep -v '^control$' | head -1)
if [ -z "$MAP" ]; then
  echo "Opening LUKS root (temporary passphrase)..."
  cryptsetup open "$ROOT_PART" newroot
  MAP=newroot
fi
echo "Using LUKS mapping: $MAP"
mkdir -p /mnt
mountpoint -q /mnt || mount "/dev/mapper/$MAP" /mnt
mkdir -p /mnt/boot
mountpoint -q /mnt/boot || mount "$EFI_PART" /mnt/boot

echo "Installed system:"; ls /mnt; cat /mnt/etc/hostname

for u in root "$USER_NEW"; do
  home=$([ "$u" = root ] && echo /mnt/root || echo "/mnt/home/$u")
  mkdir -p "$home/.ssh"
  echo "$PUBKEY" > "$home/.ssh/authorized_keys"
  chmod 700 "$home/.ssh"; chmod 600 "$home/.ssh/authorized_keys"
  uid=$(grep "^$u:" /mnt/etc/passwd | cut -d: -f3); gid=$(grep "^$u:" /mnt/etc/passwd | cut -d: -f4)
  chown -R "$uid:$gid" "$home/.ssh"
done

# enable sshd on first boot; allow root login with key only
mkdir -p /mnt/etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/sshd.service /mnt/etc/systemd/system/multi-user.target.wants/sshd.service
grep -q '^PermitRootLogin' /mnt/etc/ssh/sshd_config && sed -i 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/' /mnt/etc/ssh/sshd_config || echo 'PermitRootLogin prohibit-password' >> /mnt/etc/ssh/sshd_config
ls -l /mnt/usr/lib/systemd/system/sshd.service

echo "fstab:"; cat /mnt/etc/fstab
echo "crypttab / kernel cmdline:"; cat /mnt/etc/crypttab 2>/dev/null; grep -h 'cryptdevice\|rd.luks' /mnt/boot/grub/grub.cfg /mnt/etc/default/grub 2>/dev/null | head -3

umount -R /mnt
cryptsetup close "$MAP"
sync
echo "POST-INSTALL-DONE: safe to reboot"
