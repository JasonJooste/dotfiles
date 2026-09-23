# Set up passwordless SSH to the server over the tailnet (needed for unattended backups).
# Asks for the server's password once, the first time.
set -euo pipefail
SERVER=server
KEY="$HOME/.ssh/id_ed25519"

if [ ! -f "$KEY" ]; then
    ssh-keygen -t ed25519 -N "" -f "$KEY" -q
fi

if ssh -o BatchMode=yes -o ConnectTimeout=5 "$SERVER" true 2> /dev/null; then
    exit 0
fi
if [ -t 0 ]; then
    ssh-copy-id -i "$KEY.pub" "$SERVER" || echo "couldn't copy the SSH key to $SERVER — is it on the tailnet? Rerun later." >&2
else
    echo "passwordless SSH to $SERVER isn't set up — run 'ssh-copy-id $SERVER'." >&2
fi
