#!/usr/bin/env bash
# Take daily hard-linked snapshots of every source into <drive>/snapshots/<source>/<date>/, point `latest` at the
# newest, and prune: keeps the newest snapshot of each of the last 7 days, 4 weeks and 4 months, plus the newest of
# every year. The `seed` snapshot is never pruned. Sources are every receive-only Syncthing folder on this server
# (named by folder label) plus the drive folders in /etc/home-backup/sources.
# Runs hourly as homebackup (backup-snapshot.timer). A source is snapshotted once its latest snapshot is 20 hours
# old and, for Syncthing folders, once the folder is idle and fully synced. Problems are raised as alerts in
# /var/lib/server-alerts, which the laptop's check_server shows.
set -euo pipefail
source /etc/home-backup/config  # DRIVE
API_KEY="$(cat /etc/home-backup/syncthing-apikey)"
ALERTS=/var/lib/server-alerts
MIN_AGE_HOURS=20
MAX_AGE_DAYS=2
SNAPSHOT_PATTERN='^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}$'

alert() {  # <key> <message>
    printf '%s\n' "$2" > "$ALERTS/backup-$1"
}
clear_alert() {  # <key>
    rm -f "$ALERTS/backup-$1"
}
api() {  # <path under /rest/>
    curl -fsS --max-time 10 -H "X-API-Key: $API_KEY" "http://127.0.0.1:8384/rest/$1"
}
age_seconds() {  # <snapshot name> -> seconds since it was taken
    echo $(( $(date +%s) - $(date -d "${1:0:10} ${1:11:2}:${1:13:2}:${1:15:2}" +%s) ))
}

prune() {  # <dest>
    local dest="$1" snap
    local -a snapshots
    local -A keep=()
    mapfile -t snapshots < <(ls "$dest" | grep -E "$SNAPSHOT_PATTERN" | sort -r)
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
            rm -rf "${dest:?}/$snap"
            echo "$(basename "$dest"): pruned $snap"
        fi
    done
}

snapshot() {  # <name> <source dir> [syncthing folder id]
    local name="$1" src="$2" folder="${3:-}" dest="$DRIVE/snapshots/$1" latest status snap
    mkdir -p "$dest"
    latest="$(readlink "$dest/latest" || true)"
    if [[ $latest =~ $SNAPSHOT_PATTERN ]] && (( $(age_seconds "$latest") < MIN_AGE_HOURS * 3600 )); then
        return 0
    fi
    if [ -n "$folder" ]; then
        # Folder errors don't block the snapshot, but are worth knowing about
        if [ "$(api "folder/errors?folder=$folder" | jq '.errors | length')" -gt 0 ]; then
            alert "errors-$name" "Syncthing has errors syncing $name (see its web UI on the server)"
        else
            clear_alert "errors-$name"
        fi
        status="$(api "db/status?folder=$folder")"
        if [ "$(jq -r '.state' <<< "$status")" != idle ] || [ "$(jq '.needTotalItems' <<< "$status")" -ne 0 ]; then
            echo "$name: still syncing, trying again next hour"
            return 0
        fi
    fi

    # Build in .in-progress, so a failed run is resumed next time instead of becoming `latest`.
    # Files are owned by homebackup; its group (the reader's) can read but not change them.
    mkdir -p "$dest/.in-progress"
    local rsync_status=0 link_dest=()
    [ -e "$dest/latest" ] && link_dest=(--link-dest="$dest/latest/")
    rsync -rlptH --delete --delete-excluded --chmod=D750,Fgo-w,Fg+rX,Fo-rwx \
        --exclude=/.stfolder --exclude=/.stignore --exclude=.stversions/ --exclude='.syncthing.*.tmp' \
        "${link_dest[@]}" "$src/" "$dest/.in-progress/" || rsync_status=$?
    # 24 = some files vanished while copying, which is fine
    if [ "$rsync_status" -ne 0 ] && [ "$rsync_status" -ne 24 ]; then
        echo "$name: rsync exited with code $rsync_status" >&2
        return 1
    fi
    snap="$(date +%F_%H%M%S)"
    mv "$dest/.in-progress" "$dest/$snap"
    ln -sfn "$snap" "$dest/latest"
    echo "$name: created snapshot $snap"
    prune "$dest"
}

if ! mountpoint -q "$DRIVE"; then
    alert drive "The backup drive isn't mounted at $DRIVE"
    exit 0
fi
clear_alert drive

# Sources: receive-only Syncthing folders, then drive folders
declare -A source_dirs=() source_folders=()
if folders="$(api config/folders)"; then
    clear_alert syncthing
    while IFS=$'\t' read -r id label path; do
        name="$(tr -c 'A-Za-z0-9._\n-' '_' <<< "$label")"
        source_dirs[$name]="$path"
        source_folders[$name]="$id"
    done < <(jq -r '.[] | select(.type == "receiveonly") | [.id, .label, .path] | @tsv' <<< "$folders")
else
    alert syncthing "Can't reach Syncthing's API on the server"
fi
while read -r name dir; do
    [ -n "$name" ] && [ "${name:0:1}" != "#" ] && source_dirs[$name]="$DRIVE/$dir"
done < /etc/home-backup/sources

# Devices that haven't connected in a while
if devices="$(api config/devices)" && stats="$(api stats/device)" && my_id="$(api system/status | jq -r .myID)"; then
    while IFS=$'\t' read -r id name; do
        last_seen="$(jq -r --arg id "$id" '.[$id].lastSeen // "1970-01-01T00:00:00Z"' <<< "$stats")"
        if (( $(date +%s) - $(date -d "$last_seen" +%s) > MAX_AGE_DAYS * 86400 )); then
            alert "device-$name" "$name hasn't connected to the server's Syncthing in over $MAX_AGE_DAYS days"
        else
            clear_alert "device-$name"
        fi
    done < <(jq -r --arg me "$my_id" '.[] | select(.deviceID != $me) | [.deviceID, .name] | @tsv' <<< "$devices")
fi

for name in "${!source_dirs[@]}"; do
    if ! snapshot "$name" "${source_dirs[$name]}" "${source_folders[$name]:-}"; then
        alert "failed-$name" "Snapshot of $name failed (journalctl -u backup-snapshot)"
        continue
    fi
    clear_alert "failed-$name"
    latest="$(readlink "$DRIVE/snapshots/$name/latest" || true)"
    if [[ ! $latest =~ $SNAPSHOT_PATTERN ]]; then
        alert "overdue-$name" "No snapshot of $name has been taken yet (waiting for it to finish syncing?)"
    elif (( $(age_seconds "$latest") > MAX_AGE_DAYS * 86400 )); then
        alert "overdue-$name" "No snapshot of $name in over $MAX_AGE_DAYS days"
    else
        clear_alert "overdue-$name"
    fi
done
