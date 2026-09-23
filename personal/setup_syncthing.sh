# Sync this machine's home dir to the backup server with Syncthing (see backup_server/README.md): a send-only
# folder labelled <hostname>-home, filtered by ~/.stignore, which the server accepts as receive-only and snapshots.
# Runs after setup_server_ssh.sh, since pairing with the server goes over SSH.
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/../.env"  # SERVER
FOLDER="$(hostname)-home"

syncthing_setup install
systemctl --user enable --now syncthing.service
syncthing_setup configure

if ! server_id="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$SERVER" syncthing device-id 2> /dev/null)"; then
    echo "couldn't get $SERVER's Syncthing device ID — set up backup_server there first, then rerun." >&2
    exit 0
fi
my_id="$(syncthing device-id)"

# Pair: the server connects to nothing (no discovery), so this machine dials it at its tailnet name
if ! syncthing cli config devices list | grep -qx "$server_id"; then
    syncthing cli config devices add --device-id "$server_id" --name "$SERVER" --addresses "tcp://$SERVER:22000"
fi
# The folder is created on the server explicitly, since it may already hold files (pre-filled from a seed)
ssh -o BatchMode=yes "$SERVER" "~/.setup/backup_server/add_device.sh $(hostname) $my_id $FOLDER"

if ! syncthing cli config folders list | grep -qx "$FOLDER"; then
    syncthing cli config folders add --id "$FOLDER" --label "$FOLDER" --path "$HOME" --type sendonly
    syncthing cli config folders "$FOLDER" devices add --device-id "$server_id"
fi
