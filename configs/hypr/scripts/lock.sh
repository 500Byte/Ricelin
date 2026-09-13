#!/bin/sh
set -u
umask 077

dir="${XDG_RUNTIME_DIR:-/tmp}"
state="${XDG_STATE_HOME:-$HOME/.local/state}"

# --- 1. Sanity checks: abort loudly if deps are missing ---
command -v hyprctl >/dev/null 2>&1 || { echo "lock: hyprctl not found" >&2; exit 1; }
command -v jq      >/dev/null 2>&1 || { echo "lock: jq not found" >&2;      exit 1; }
command -v grim    >/dev/null 2>&1 || { echo "lock: grim not found" >&2;    exit 1; }

# --- 2. Resolve monitor list up front ---
monitors=$(hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null) || {
    echo "lock: failed to enumerate monitors" >&2
    exit 1
}
[ -n "$monitors" ] || { echo "lock: no monitors reported" >&2; exit 1; }

# --- 3. Grab each monitor in parallel with a 1s timeout ---
# grim captures to a temporary file first so failed or interrupted grabs never leave 0-byte pngs.
for out in $monitors; do
    [ -n "$out" ] || continue
    (
        rm -f "$dir/ricelin-lock-$out.tmp"
        if timeout 1 grim -o "$out" "$dir/ricelin-lock-$out.tmp" 2>/dev/null && [ -s "$dir/ricelin-lock-$out.tmp" ]; then
            mv -f "$dir/ricelin-lock-$out.tmp" "$dir/ricelin-lock-$out.png"
        else
            rm -f "$dir/ricelin-lock-$out.tmp"
            # Fallback to current wallpaper still if capture failed or DPMS was off
            if [ ! -s "$dir/ricelin-lock-$out.png" ]; then
                still="$state/ricelin-wallpaper-still-$out.png"
                [ -s "$still" ] || still="$state/ricelin-wallpaper-still.png"
                if [ -s "$still" ]; then
                    cp -f "$still" "$dir/ricelin-lock-$out.png"
                fi
            fi
        fi
    ) &
done
wait

# --- 4. Fire the lock trigger ---
# Direct write so QFileSystemWatcher sees the same-inode change.
date +%s%N > "$dir/ricelin-lock-trigger"

# Secondary IPC trigger in case filesystem watch was missed
qs -c lock ipc call lock lock >/dev/null 2>&1 &

# --- 5. Warn if no screenshots landed (lock still opens) ---
ok=0
for out in $monitors; do
    [ -s "$dir/ricelin-lock-$out.png" ] && ok=$((ok + 1))
done
[ "$ok" -gt 0 ] || echo "lock: no screenshots captured" >&2
