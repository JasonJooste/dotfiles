#!/usr/bin/env bash
# Let a device (laptop, phone) back up to this server's Syncthing. Folders it shares are accepted automatically,
# as receive-only folders under <drive>/sync/<folder label>, and get snapshotted like everything else.
# Run as the user running Syncthing on the server. Usage: add_device.sh <name> <device id>
set -euo pipefail
[ $# -eq 2 ] || { echo "usage: $0 <name> <device id>" >&2; exit 1; }
NAME="$1"
ID="$2"

if syncthing cli config devices list | grep -qx "$ID"; then
    echo "$NAME is already a known device"
else
    syncthing cli config devices add --device-id "$ID" --name "$NAME" --addresses dynamic --auto-accept-folders
    echo "added $NAME; folders it shares will be accepted automatically"
fi
