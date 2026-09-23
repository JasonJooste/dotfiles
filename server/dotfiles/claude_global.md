# Notifications

My Stop and PermissionRequest hooks speak a notification via `claude_helpers flagged_cwd_alert`. It's skipped while a `notify-off` flag file exists in the session's scratchpad directory.

- "Mute notifications": `touch <scratchpad dir>/notify-off`
- "Unmute notifications": `rm <scratchpad dir>/notify-off`

This only affects the current session.
