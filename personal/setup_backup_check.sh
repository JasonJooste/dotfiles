# Enable the daily backup age check (units are linked into ~/.config/systemd/user by install.sh)
set -euo pipefail
systemctl --user daemon-reload
systemctl --user enable --now check_backup_age.timer
