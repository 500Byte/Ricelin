#!/usr/bin/env bash
MAGICK_CONFIGURE_PATH="$(dirname "$0")/magick-policy"
export MAGICK_CONFIGURE_PATH

flags="${XDG_STATE_HOME:-$HOME/.local/state}/ricelin/flags.json"
wpdir=$(jq -r '.wallpaperDir // ""' "$flags" 2>/dev/null || echo "")
[ -n "$wpdir" ] || wpdir=$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/ricelin-wallpaper-dir" 2>/dev/null || true)
[ -n "$wpdir" ] || wpdir="$HOME/Pictures/Wallpapers"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/ricelin-wp-thumbs"
mkdir -p "$cache"

for f in "$cache"/*.png; do
    [ -e "$f" ] || continue
    base="$(basename "$f" .png)"
    [ -n "$(find "$wpdir" -type f -name "$base" -print -quit)" ] || rm -f "$f"
done

max_jobs=4

process_file() {
    local src="$1" thumb="$2"
    case "$src" in
        *.[Mm][Pp][4]|*.[Ww][Ee][Bb][Mm]|*.[Mm][Kk][Vv]|*.[Mm][Oo][Vv])
            ffmpeg -y -loglevel quiet -i "$src" -frames:v 1 -vf 'scale=512:-2' -f image2 -c:v png "$thumb.tmp" 2>/dev/null
            ;;
        *)
            magick "${src}[0]" -strip -resize 512x "png:$thumb.tmp" 2>/dev/null
            ;;
    esac
    if [ -s "$thumb.tmp" ]; then
        mv "$thumb.tmp" "$thumb"
    else
        rm -f "$thumb.tmp"
    fi
}

find "$wpdir" -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.mov' \) | while IFS= read -r src; do
    thumb="$cache/$(basename "$src").png"
    if [ ! -s "$thumb" ] || [ "$src" -nt "$thumb" ]; then
        process_file "$src" "$thumb" &
        while [ "$(jobs -r | wc -l)" -ge "$max_jobs" ]; do
            wait -n 2>/dev/null || true
        done
    fi
done
wait

# Cache cleanup: remove entries older than 7 days if cache exceeds limits
cache_size=$(du -sm "$cache" 2>/dev/null | cut -f1)
cache_count=$(find "$cache" -type f | wc -l)
if [ "${cache_size:-0}" -gt 100 ] || [ "${cache_count:-0}" -gt 1000 ]; then
    find "$cache" -type f -atime +7 -delete 2>/dev/null
fi
