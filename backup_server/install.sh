#!/usr/bin/env bash
# Set up the backup server: Syncthing receiving from devices, and daily snapshots. See README.md. Safe to rerun.
# Usage: sudo ./install.sh <backup drive UUID>
# The drive is mounted at BACKUP_DRIVE from the repo's .env.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
[ $# -eq 1 ] || { echo "usage: sudo $0 <drive UUID>" >&2; exit 1; }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../.env"  # BACKUP_DRIVE
UUID="$1"
DRIVE="$BACKUP_DRIVE"
READER="${SUDO_USER:?run with sudo from your normal account}"  # runs Syncthing and can read the snapshots
ACCOUNT=homebackup
CONF=/etc/home-backup
ALERTS=/var/lib/server-alerts

DEBIAN_FRONTEND=noninteractive apt-get install -y -qq rsync jq curl

# Dedicated account that takes and owns the snapshots. The reader gets read-only access through its group.
if ! id "$ACCOUNT" &> /dev/null; then
    useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin "$ACCOUNT"
fi
usermod -aG "$ACCOUNT" "$READER"

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

# Synced copies (written by Syncthing as the reader), snapshots (only homebackup can write), and alerts
install -d -o "$READER" -g "$READER" -m 750 "$DRIVE/sync"
install -d -o "$ACCOUNT" -g "$ACCOUNT" -m 750 "$DRIVE/snapshots" "$ALERTS"

# Syncthing, running as the reader. Folders that devices share are accepted as receive-only under sync/.
"$HERE/../server/scripts/syncthing_setup.sh" install
systemctl enable --now "syncthing@$READER.service"
sudo -u "$READER" -H "$HERE/../server/scripts/syncthing_setup.sh" configure
api_key="$(sudo -u "$READER" -H syncthing cli config gui apikey get)"
curl -fsS -X PATCH -H "X-API-Key: $api_key" http://127.0.0.1:8384/rest/config/defaults/folder \
    -d "{\"path\": \"$DRIVE/sync\", \"type\": \"receiveonly\"}"

# Root-owned copies of everything that runs as homebackup, so the reader account (which devices can log in
# as) can't change what it runs
install -d -m 755 "$CONF" /usr/local/lib/home-backup
printf 'DRIVE=%s\n' "$DRIVE" > "$CONF/config"
chmod 644 "$CONF/config"
install -m 644 "$HERE/sources" "$CONF/sources"
install -m 640 -g "$ACCOUNT" /dev/null "$CONF/syncthing-apikey"
printf '%s\n' "$api_key" > "$CONF/syncthing-apikey"
install -m 755 "$HERE/snapshot.sh" /usr/local/lib/home-backup/snapshot
install -m 644 "$HERE/backup-snapshot.service" "$HERE/backup-snapshot.timer" /etc/systemd/system/
install -d -m 755 /etc/systemd/system/backup-snapshot.service.d
cat > /etc/systemd/system/backup-snapshot.service.d/local.conf << EOF
[Unit]
After=syncthing@$READER.service

[Service]
ReadWritePaths=$DRIVE/snapshots $ALERTS
EOF
systemctl daemon-reload

if [ -d "$DRIVE/backups" ]; then
    echo "Found the old pull-based layout ($DRIVE/backups): run sudo $HERE/migrate.sh <laptop name> next."
    echo "The snapshot timer stays off until then."
else
    systemctl enable --now backup-snapshot.timer
fi

cat << EOF

Done. Next steps (see README.md):
  - Log out and back in so $READER picks up the $ACCOUNT group.
  - Add devices: on the laptop, install.sh personal does it; for the phone, run
      $HERE/add_device.sh <name> <device id from the phone's Syncthing app>
    This server's device ID (for the phone):
      $(sudo -u "$READER" -H syncthing device-id)
EOF
