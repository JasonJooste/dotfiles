#!/usr/bin/env bash
# Helpers for Claude Code hooks.
# Usage: claude_helpers <function> [args...]
MUTE_FLAG=notify-off

# Show and speak a notification, unless the mute flag file exists in the given flag directory.
# Usage: flagged_alert <flag_dir> <message>
flagged_alert() {
    local flag_dir="$1"
    shift
    if [ -n "$flag_dir" ] && [ -e "$flag_dir/$MUTE_FLAG" ]; then
        return 0
    fi
    notify-msg --speak "$*"
}

# Flagged alert saying "<message> in <folder>". Reads the flag directory and folder from the hook's JSON input on stdin.
# Usage: flagged_cwd_alert <message>
flagged_cwd_alert() {
    local in flag_dir cwd
    in=$(cat)
    flag_dir=$(jq -r '.scratchpad_dir // empty' <<<"$in")
    cwd=$(jq -r '.cwd // empty' <<<"$in")
    flagged_alert "$flag_dir" "$* in ${cwd##*/}"
}

"$@"
