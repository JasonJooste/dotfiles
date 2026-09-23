# SSH between this machine and the server, over the tailnet:
# 1. Passwordless SSH to the server (asks for the server's password once, the first time)
# 2. Let the server's backup pull this machine's home dir (see backup_server/README.md): an SSH server that
#    only accepts keys over the tailnet, and the server's pull key restricted to read-only rsync of ~
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/../.env"  # SERVER
KEY="$HOME/.ssh/id_ed25519"

# 1. This machine -> server
if [ ! -f "$KEY" ]; then
    ssh-keygen -t ed25519 -N "" -f "$KEY" -q
fi
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$SERVER" true 2> /dev/null; then
    if [ -t 0 ]; then
        ssh-copy-id -i "$KEY.pub" "$SERVER" || echo "couldn't copy the SSH key to $SERVER — is it on the tailnet? Rerun later." >&2
    else
        echo "passwordless SSH to $SERVER isn't set up — run 'ssh-copy-id $SERVER'." >&2
    fi
fi

# 2. Server's backup -> this machine
apt_install_missing openssh-server
sudo tee /etc/ssh/sshd_config.d/10-keys-only.conf > /dev/null << 'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
sudo systemctl try-reload-or-restart ssh.service
# Only reachable over the tailnet (ufw denies other incoming connections by default)
sudo ufw allow in on tailscale0 to any port 22 proto tcp > /dev/null

if ! pull_key="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$SERVER" cat /etc/home-backup/pull_key.pub 2> /dev/null)"; then
    echo "couldn't get the backup pull key from $SERVER — set up backup_server there first, then rerun." >&2
    exit 0
fi
entry="command=\"rrsync -ro $HOME\",restrict $pull_key"
touch "$HOME/.ssh/authorized_keys"
chmod 600 "$HOME/.ssh/authorized_keys"
grep -qxF "$entry" "$HOME/.ssh/authorized_keys" || echo "$entry" >> "$HOME/.ssh/authorized_keys"
