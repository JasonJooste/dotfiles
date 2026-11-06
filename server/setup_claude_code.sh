set -euo pipefail
sudo apt install -y curl
if ! curl -fsSL https://claude.ai/install.sh -o /tmp/claude_install.sh; then
    echo "ERROR: failed to download the Claude Code installer. A VPN can block this; try disconnecting it." >&2
    exit 1
fi
bash /tmp/claude_install.sh
rm /tmp/claude_install.sh
