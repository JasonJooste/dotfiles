# Install tailscale and join the tailnet. Joins without prompting when TS_AUTHKEY is set (generate one in the
# admin console under Settings -> Keys), otherwise shows a login link/QR code to open on any other device.
# For always-on machines, disable key expiry in the admin console so they don't silently drop off after 180 days.
set -euo pipefail

if ! command -v tailscale > /dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
fi

if tailscale status > /dev/null 2>&1; then
    exit 0
fi
if [ -n "${TS_AUTHKEY:-}" ]; then
    sudo tailscale up --auth-key="$TS_AUTHKEY"
elif [ -t 0 ]; then
    sudo tailscale up --qr
else
    echo "tailscale is installed but not connected — run 'sudo tailscale up' to join the tailnet." >&2
fi
