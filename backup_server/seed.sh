#!/usr/bin/env bash
# One-off, for a fresh install: move existing folders from the top of the backup drive into a `seed` snapshot of
# a source, replace them with links to its latest snapshot, and copy them into its synced folder, so Syncthing
# finds them already there instead of uploading them again. Files only in the seed are kept there forever.
# Usage: sudo ./seed.sh <source> <folder>...   e.g. sudo ./seed.sh juicer-home Documents Games Pictures Videos
# (<source> is the device's Syncthing folder label, e.g. <hostname>-home for a laptop)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
[ $# -ge 2 ] || { echo "usage: sudo $0 <source> <folder>..." >&2; exit 1; }
source /etc/home-backup/config  # DRIVE
READER="${SUDO_USER:?run with sudo from your normal account}"
ACCOUNT=homebackup
SOURCE="$1"
shift
DEST="$DRIVE/snapshots/$SOURCE"
SEED="$DEST/seed"
SYNCED="$DRIVE/sync/$SOURCE"

mountpoint -q "$DRIVE" || { echo "$DRIVE isn't mounted" >&2; exit 1; }
[ ! -e "$SEED" ] || { echo "$SEED already exists" >&2; exit 1; }
for folder in "$@"; do
    [ -d "$DRIVE/$folder" ] && [ ! -L "$DRIVE/$folder" ] || { echo "$DRIVE/$folder isn't a folder" >&2; exit 1; }
done

install -d -o "$ACCOUNT" -g "$ACCOUNT" -m 750 "$DEST"
mkdir "$SEED"
for folder in "$@"; do
    mv "$DRIVE/$folder" "$SEED/"
done
# Same ownership and permissions snapshot.sh gives snapshots
chown -R "$ACCOUNT:$ACCOUNT" "$SEED"
find "$SEED" -type d -exec chmod 750 {} +
find "$SEED" -type f -exec chmod go-w,g+rX,o-rwx {} +
ln -sfn seed "$DEST/latest"
chown -h "$ACCOUNT:$ACCOUNT" "$DEST/latest"
for folder in "$@"; do
    ln -s "snapshots/$SOURCE/latest/$folder" "$DRIVE/$folder"
done

echo "copying the seed into $SYNCED (local, but can take a while)..."
install -d -o "$READER" -g "$READER" -m 700 "$SYNCED"
rsync -a --chown="$READER:$READER" "$SEED/" "$SYNCED/"
echo "seeded $SOURCE with: $*"
