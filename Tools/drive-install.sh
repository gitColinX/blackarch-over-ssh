#!/bin/bash
# Unattended driver for blackarch-install 1.2.25 (runs on the live ISO).
# Runs the installer inside a pty (via `script`), watches its output for each
# prompt and types the answer. Log: /root/install.log (installer), /root/driver.log (us).
#
# Temporary secrets: LUKS passphrase, root password and user password are all
# "blackarch". Change them on first boot (see INSTALL.md step 6).

HOSTNAME_NEW="${1:-blackarch-laptop}"
USER_NEW="${2:-pentester}"
TZ_NEW="${3:-America/New_York}"
DISK="${4:-nvme0n1}"
TMP_SECRET="blackarch"

LOG=/root/install.log
DLOG=/root/driver.log
FIFO=/root/in.fifo

rm -f "$FIFO" "$LOG"
mkfifo "$FIFO"
: > "$LOG"
export TERM=xterm
export COLUMNS=200 LINES=50

log() { echo "$(date +%T) $*" >> "$DLOG"; }

script -q -f -e -c /usr/bin/blackarch-install "$LOG" < "$FIFO" > /dev/null 2>&1 &
SPID=$!
exec 3>"$FIFO"
log "installer started pid=$SPID host=$HOSTNAME_NEW user=$USER_NEW tz=$TZ_NEW disk=$DISK"

pos=0
expect() {
  local re="$1" t=0
  while true; do
    if tail -c +$((pos + 1)) "$LOG" | grep -aqE -- "$re"; then
      pos=$(stat -c %s "$LOG")
      return 0
    fi
    if ! kill -0 "$SPID" 2>/dev/null; then
      log "INSTALLER EXITED while waiting for: $re"
      exit 1
    fi
    sleep 1
    t=$((t + 1))
    [ $((t % 300)) -eq 0 ] && log "still waiting (${t}s) for: $re"
  done
}
step() {
  expect "$1"
  sleep 1
  local shown="$2"
  [ "$2" = "$TMP_SECRET" ] && shown='<temp secret>'
  log "'$1' -> '$shown'"
  printf '%s\n' "$2" >&3
}

step 'Choose an installation mode'            '1'
step 'Make a choice'                          '2'            # verbose output
step 'Make a choice'                          '1'            # set a locale
step 'Set locale'                             'en_US.UTF-8'
step 'Make a choice'                          '1'            # set a keymap
step 'Set keymap'                             'us'
step 'Set your hostname'                      "$HOSTNAME_NEW"
step 'Please choose a mode'                   '1'            # auto DHCP
step 'Please choose a network interface'      'eth0'
step 'Look for the best server'               'n'            # worldwide Arch mirror
step 'Please choose a device'                 "$DISK"
step 'Install BlackArch Linux with Windows'   'n'
step 'Create partitions with cfdisk'          'n'            # pre-partitioned with sfdisk
step 'Full encrypted root'                    'y'
step 'EFI System partition \('                '1'
step 'Root partition \('                      '3'
step 'filesystem to use in your root'         'ext4'
step 'Swap partition - empty'                 '2'
step 'Partition table correct'                'y'
step 'No crying afterwards'                   'y'
step 'Enter passphrase'                       "$TMP_SECRET"  # luksFormat
step 'Verify passphrase'                      "$TMP_SECRET"
step 'Enter passphrase'                       "$TMP_SECRET"  # luksOpen
step 'New password'                           "$TMP_SECRET"  # root
step 'Retype new password'                    "$TMP_SECRET"
step 'Setup a normal user account'            'y'
step 'User name'                              "$USER_NEW"
step 'New password'                           "$TMP_SECRET"  # user
step 'Retype new password'                    "$TMP_SECRET"
step 'Choose other timezone'                  'y'
step 'Zone/SubZone'                           "$TZ_NEW"
step 'Select a mirror number'                 ''
step 'Perform full system upgrade'            'y'            # asked by strap.sh (new in 2026)
step 'Setup X11'                              'y'
step 'Choose an option'                       ''             # all window managers
step 'Setup VirtualBox modules'               'n'
step 'Setup VMware modules'                   'n'
step 'Setup BlackArch Linux tools'            'n'            # done after first boot

wait "$SPID"
rc=$?
log "installer finished, exit code $rc"
exec 3>&-
exit $rc
