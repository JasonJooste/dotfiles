#!/usr/bin/env bash
# One-off: move existing folders from the top of the backup drive into a `seed` snapshot, and replace them with
# links to the latest snapshot. Files only in the seed (not on the laptop) are kept there forever.
# Usage: sudo ./seed.sh <folder>...   e.g. sudo ./seed.sh Documents Games Pictures Videos
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
[ $# -ge 1 ] || { echo "usage: sudo $0 <folder>..." >&2; exit 1; }
source /etc/home-backup/config  # LAPTOP, DRIVE
ACCOUNT=homebackup
DEST="$DRIVE/backups/$LAPTOP"
SEED="$DEST/seed"

mountpoint -q "$DRIVE" || { echo "$DRIVE isn't mounted" >&2; exit 1; }
[ ! -e "$SEED" ] || { echo "$SEED already exists" >&2; exit 1; }
for folder in "$@"; do
    [ -d "$DRIVE/$folder" ] && [ ! -L "$DRIVE/$folder" ] || { echo "$DRIVE/$folder isn't a folder" >&2; exit 1; }
done

mkdir "$SEED"
for folder in "$@"; do
    mv "$DRIVE/$folder" "$SEED/"
done
# Same ownership and permissions the pull applies to snapshots
chown -R "$ACCOUNT:$ACCOUNT" "$SEED"
find "$SEED" -type d -exec chmod 750 {} +
find "$SEED" -type f -exec chmod go-w,g+rX,o-rwx {} +

ln -sfn seed "$DEST/latest"
chown -h "$ACCOUNT:$ACCOUNT" "$DEST/latest"
for folder in "$@"; do
    ln -s "backups/$LAPTOP/latest/$folder" "$DRIVE/$folder"
done
echo "seeded $SEED with: $*"
