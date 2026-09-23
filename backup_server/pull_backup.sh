#!/usr/bin/env bash
# Pull a snapshot of the laptop's home dir onto the backup drive, with unchanged files hard-linked to the
# previous snapshot, then point `latest` at it and prune old snapshots. Keeps the newest snapshot of each of
# the last 7 days, 4 weeks and 4 months, plus the newest of every year. The `seed` snapshot is never pruned.
# Runs hourly as the homebackup user (home-backup.timer), but skips while the latest snapshot is under
# 20 hours old or the laptop is unreachable, so it takes one snapshot a day whenever the laptop is online.
set -euo pipefail
source /etc/home-backup/config  # LAPTOP, LAPTOP_USER, DRIVE
DEST="$DRIVE/backups/$LAPTOP"
MIN_AGE_HOURS=20
SNAPSHOT_PATTERN='^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}$'

snapshot_time() {  # <snapshot name> -> epoch seconds
    date -d "${1:0:10} ${1:11:2}:${1:13:2}:${1:15:2}" +%s
}

# Never write to the system disk because the drive didn't mount
mountpoint -q "$DRIVE" || { echo "$DRIVE isn't mounted" >&2; exit 1; }

latest="$(readlink "$DEST/latest" || true)"
if [[ $latest =~ $SNAPSHOT_PATTERN ]] && (( $(date +%s) - $(snapshot_time "$latest") < MIN_AGE_HOURS * 3600 )); then
    exit 0
fi
# Laptop asleep or away: try again next hour
if ! timeout 5 bash -c "echo > /dev/tcp/$LAPTOP/22" 2> /dev/null; then
    echo "$LAPTOP isn't reachable, skipping"
    exit 0
fi

# Build the snapshot in .in-progress, so a failed run is resumed next time instead of becoming `latest`.
# Files are owned by homebackup; its group (which the laptop's user is in) can read but not change them.
mkdir -p "$DEST/.in-progress"
rsync_status=0
rsync -rlptH --delete --delete-excluded --chmod=D750,Fgo-w,Fg+rX,Fo-rwx \
    --exclude-from=/etc/home-backup/excludes --link-dest="$DEST/latest/" \
    -e "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new" \
    "$LAPTOP_USER@$LAPTOP:" "$DEST/.in-progress/" || rsync_status=$?
# 24 = some files vanished while copying, which is normal for a live home dir
if [ "$rsync_status" -ne 0 ] && [ "$rsync_status" -ne 24 ]; then
    echo "rsync exited with code $rsync_status" >&2
    exit "$rsync_status"
fi

snapshot="$(date +%F_%H%M%S)"
mv "$DEST/.in-progress" "$DEST/$snapshot"
ln -sfn "$snapshot" "$DEST/latest"
echo "created snapshot $snapshot"

# Prune: walk snapshots newest first, keeping the first one seen in each new day/week/month/year bucket
mapfile -t snapshots < <(ls "$DEST" | grep -E "$SNAPSHOT_PATTERN" | sort -r)
declare -A keep
keep_newest_per() {  # <date format of the bucket> <number of buckets to keep, 0 = all>
    local format="$1" count="$2" last_bucket="" kept=0 snap bucket
    for snap in "${snapshots[@]}"; do
        [ "$count" -ne 0 ] && [ "$kept" -ge "$count" ] && break
        bucket="$(date -d "${snap:0:10}" +"$format")"
        if [ "$bucket" != "$last_bucket" ]; then
            keep[$snap]=1
            last_bucket="$bucket"
            kept=$((kept + 1))
        fi
    done
}
keep_newest_per %F 7
keep_newest_per %G-W%V 4
keep_newest_per %Y-%m 4
keep_newest_per %Y 0

for snap in "${snapshots[@]}"; do
    if [ -z "${keep[$snap]:-}" ]; then
        rm -rf "${DEST:?}/$snap"
        echo "pruned $snap"
    fi
done
