#!/usr/bin/env bash
# Show the server's alerts and failed services as notifications. Run daily by check_server.timer.
# Anything on the server can raise an alert by writing a one-line message to a file in /var/lib/server-alerts
# (and clear it by deleting the file). Stays quiet when the server is unreachable, since it can't tell.
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/../../.env"  # SERVER

status=0
report="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$SERVER" \
    'cat /var/lib/server-alerts/* 2> /dev/null; systemctl --failed --no-legend --plain | awk "{print \$1 \" has failed\"}"')" \
    || status=$?
[ "$status" -eq 255 ] && exit 0  # ssh couldn't connect

while IFS= read -r line; do
    [ -n "$line" ] && notify-msg --error "$SERVER: $line"
done <<< "$report"
