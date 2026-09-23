# Enable the daily check of the server's alerts (units are linked into ~/.config/systemd/user by install.sh)
set -euo pipefail
systemctl --user daemon-reload
systemctl --user enable --now check_server.timer
