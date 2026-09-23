#!/usr/bin/env bash
# Set up the pull-based laptop backup on this (backup server) machine. See README.md. Safe to rerun.
# Usage: sudo ./install.sh <laptop tailnet name> <backup drive UUID>
# The drive is mounted at BACKUP_DRIVE from the repo's .env.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
[ $# -eq 2 ] || { echo "usage: sudo $0 <laptop> <drive UUID>" >&2; exit 1; }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../.env"  # BACKUP_DRIVE
LAPTOP="$1"
UUID="$2"
DRIVE="$BACKUP_DRIVE"
READER="${SUDO_USER:?run with sudo from your normal account}"  # reads the snapshots; also the user on the laptop
ACCOUNT=homebackup
CONF=/etc/home-backup

# Dedicated account that pulls and owns the snapshots. The reader gets read-only access through its group.
if ! id "$ACCOUNT" &> /dev/null; then
    useradd --system --create-home --home-dir "/var/lib/$ACCOUNT" --shell /usr/sbin/nologin "$ACCOUNT"
fi
chmod 700 "/var/lib/$ACCOUNT"
usermod -aG "$ACCOUNT" "$READER"

# Key for pulling from the laptop (which restricts it to read-only rsync of the home dir)
KEY="/var/lib/$ACCOUNT/.ssh/id_ed25519"
if [ ! -f "$KEY" ]; then
    install -d -o "$ACCOUNT" -g "$ACCOUNT" -m 700 "$(dirname "$KEY")"
    sudo -u "$ACCOUNT" ssh-keygen -q -t ed25519 -N "" -C "$ACCOUNT@$(hostname)" -f "$KEY"
fi

# Root-owned copies of everything that runs as the backup account, so the reader account (which the laptop
# can log in as) can't change what it runs
install -d -m 755 "$CONF" /usr/local/lib/home-backup
install -m 644 "$KEY.pub" "$CONF/pull_key.pub"
install -m 644 "$HERE/excludes" "$CONF/excludes"
printf 'LAPTOP=%s\nLAPTOP_USER=%s\nDRIVE=%s\n' "$LAPTOP" "$READER" "$DRIVE" > "$CONF/config"
chmod 644 "$CONF/config"
install -m 755 "$HERE/pull_backup.sh" /usr/local/lib/home-backup/pull_backup
install -m 644 "$HERE/home-backup.service" "$HERE/home-backup.timer" /etc/systemd/system/
install -d -m 755 /etc/systemd/system/home-backup.service.d
printf '[Service]\nReadWritePaths=%s\n' "$DRIVE" > /etc/systemd/system/home-backup.service.d/drive.conf

# Mount the drive at boot instead of via the desktop (nofail, so a missing drive doesn't block booting)
if ! grep -q "UUID=$UUID" /etc/fstab; then
    echo "UUID=$UUID $DRIVE ext4 defaults,nofail 0 2" >> /etc/fstab
fi
mkdir -p "$DRIVE"
systemctl daemon-reload
for mount in $(findmnt -rno TARGET -S "UUID=$UUID"); do
    [ "$mount" = "$DRIVE" ] || umount "$mount"
done
mountpoint -q "$DRIVE" || mount "$DRIVE"

install -d -o "$ACCOUNT" -g "$ACCOUNT" -m 750 "$DRIVE/backups" "$DRIVE/backups/$LAPTOP"

systemctl enable --now home-backup.timer

cat << EOF

Done. Next steps (see README.md):
  - Log out and back in on this machine so $READER picks up the $ACCOUNT group.
  - Optionally seed from existing folders on the drive: sudo $HERE/seed.sh <folder>...
  - On $LAPTOP, run install.sh personal to authorize this key (read-only rsync of the home dir):
      $(cat "$KEY.pub")
EOF
