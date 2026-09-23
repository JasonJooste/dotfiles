#!/usr/bin/env bash
# Show a desktop notification with a custom message, optionally speaking it or playing a sound.
# Each output is skipped if its tool isn't installed, so this is safe to call on headless machines.
# Usage: notify-msg [--speak] [--sound] [--error] <message>
speak=0
sound=0
icon=terminal
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --speak) speak=1 ;;
        --sound) sound=1 ;;
        --error) icon=error ;;
        *) echo "notify-msg: unknown option $1" >&2; exit 1 ;;
    esac
    shift
done
msg="$*"

if command -v notify-send >/dev/null; then
    notify-send --urgency=normal -i "$icon" "$msg"
fi
if [ "$speak" = 1 ] && command -v spd-say >/dev/null; then
    spd-say "$msg"
fi
if [ "$sound" = 1 ] && command -v paplay >/dev/null; then
    sound_file=/usr/share/sounds/freedesktop/stereo/complete.oga
    paplay "$sound_file"; sleep 1; paplay "$sound_file"
fi
exit 0
