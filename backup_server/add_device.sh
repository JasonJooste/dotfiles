#!/usr/bin/env bash
# Let a device (laptop, phone) back up to this server's Syncthing. Folders it shares are accepted as receive-only
# folders under <drive>/sync/<folder label>, and get snapshotted like everything else.
# Folders are auto-accepted when the device first shares them, except where <drive>/sync/<folder> already exists
# (e.g. pre-filled by seed.sh or migrate.sh), which Syncthing refuses; pass those folder IDs to create them here.
# Run as the user running Syncthing on the server. Usage: add_device.sh <name> <device id> [folder id...]
set -euo pipefail
[ $# -ge 2 ] || { echo "usage: $0 <name> <device id> [folder id...]" >&2; exit 1; }
source /etc/home-backup/config  # DRIVE
NAME="$1"
ID="$2"
shift 2

if syncthing cli config devices list | grep -qx "$ID"; then
    echo "$NAME is already a known device"
else
    syncthing cli config devices add --device-id "$ID" --name "$NAME" --addresses dynamic --auto-accept-folders
    echo "added $NAME; folders it shares will be accepted automatically"
fi

for folder in "$@"; do
    if ! syncthing cli config folders list | grep -qx "$folder"; then
        syncthing cli config folders add --id "$folder" --label "$folder" --path "$DRIVE/sync/$folder" --type receiveonly
    fi
    if ! syncthing cli config folders "$folder" devices list | grep -qx "$ID"; then
        syncthing cli config folders "$folder" devices add --device-id "$ID"
    fi
    echo "receiving $folder from $NAME into $DRIVE/sync/$folder"
done
