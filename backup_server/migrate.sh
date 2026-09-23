#!/usr/bin/env bash
# One-off: convert the old pull-based backup (backups/<laptop>/, home-backup.timer) to the Syncthing layout.
# Run once after install.sh. Usage: sudo ./migrate.sh <laptop name>
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
[ $# -eq 1 ] || { echo "usage: sudo $0 <laptop name>" >&2; exit 1; }
source /etc/home-backup/config  # DRIVE
READER="${SUDO_USER:?run with sudo from your normal account}"
ACCOUNT=homebackup
LAPTOP="$1"
OLD="$DRIVE/backups/$LAPTOP"
SOURCE="$LAPTOP-home"  # the laptop's Syncthing folder label
DEST="$DRIVE/snapshots/$SOURCE"
SYNCED="$DRIVE/sync/$SOURCE"

mountpoint -q "$DRIVE" || { echo "$DRIVE isn't mounted" >&2; exit 1; }

# 1. Remove the pull service, script and key
systemctl disable --now home-backup.timer 2> /dev/null || true
rm -rf /etc/systemd/system/home-backup.service /etc/systemd/system/home-backup.timer \
    /etc/systemd/system/home-backup.service.d /usr/local/lib/home-backup/pull_backup \
    /etc/home-backup/pull_key.pub /etc/home-backup/excludes /var/lib/homebackup
systemctl daemon-reload

# 2. Move the snapshots (seed, dated ones and the relative `latest` link) to the new layout
if [ -d "$OLD" ]; then
    [ ! -e "$DEST" ] || { echo "$DEST already exists" >&2; exit 1; }
    mv "$OLD" "$DEST"
    rmdir "$DRIVE/backups" 2> /dev/null || true
fi

# 3. Music, for_dad and for_mum only live on the drive: real folders owned by the reader, snapshotted separately
if [ -L "$DRIVE/Music" ] && [ -d "$DEST/seed/Music" ]; then
    rm "$DRIVE/Music"
    mv "$DEST/seed/Music" "$DRIVE/Music"
fi
for folder in Music for_dad for_mum; do
    [ -d "$DRIVE/$folder" ] && chown -R "$READER:$READER" "$DRIVE/$folder"
done

# 4. Point the top-level links at the new location
for link in "$DRIVE"/*; do
    target="$(readlink "$link" || true)"
    if [[ $target == backups/$LAPTOP/latest/* ]]; then
        ln -sfn "snapshots/$SOURCE/latest/${target#backups/$LAPTOP/latest/}" "$link"
    fi
done

# 5. Fill the laptop's synced folder from its latest snapshot, so Syncthing only uploads what changed since
if [ ! -e "$SYNCED" ]; then
    echo "copying the latest snapshot into $SYNCED (local, but can take a while)..."
    install -d -o "$READER" -g "$READER" -m 700 "$SYNCED"
    rsync -a --chown="$READER:$READER" "$DEST/latest/" "$SYNCED/"
fi

# 6. Start taking snapshots
systemctl enable --now backup-snapshot.timer
echo "migrated $LAPTOP's backups to $DEST"
