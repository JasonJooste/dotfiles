#!/usr/bin/env bash
# Warn (via notify-msg) when the backup server's newest snapshot of this machine is over 2 days old.
# Run daily by check_backup_age.timer. Stays quiet when the server is unreachable, since it can't tell.
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/../../.env"  # SERVER, BACKUP_DRIVE
DEST="$BACKUP_DRIVE/backups/$(hostname)"
MAX_AGE_DAYS=2

status=0
latest="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$SERVER" readlink "$DEST/latest" 2> /dev/null)" || status=$?
[ "$status" -eq 255 ] && exit 0  # ssh couldn't connect

if [[ ! $latest =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_ ]]; then
    notify-msg --error "No backup of $(hostname) has completed on $SERVER yet"
    exit 0
fi
age_days=$(( ($(date +%s) - $(date -d "${latest:0:10}" +%s)) / 86400 ))
if [ "$age_days" -gt "$MAX_AGE_DAYS" ]; then
    notify-msg --error "Last backup of $(hostname) is $age_days days old ($latest)"
fi
