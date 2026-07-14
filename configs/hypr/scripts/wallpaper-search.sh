#!/usr/bin/env bash

UA="Mozilla/5.0 (X11; Linux x86_64) Gecko/20100101 Firefox/126.0"

search() {
    local query="${1:-}"
    local sort="${2:-relevance}"
    local range="${3:-1M}"
    local purity="${4:-100}"
    local categories="${5:-111}"
    local ratio="${6:-}"
    local page="${7:-1}"

    local url="https://wallhaven.cc/api/v1/search?atleast=2560x1440&purity=${purity}&sorting=${sort}&categories=${categories}&page=${page}&apikey=EC0aZgPiNJsb3Nq9TsRoyub16cQLhLDi"

    if [ -n "$query" ]; then
        local enc
        enc=$(jq -rn --arg q "$query" '$q|@uri') || { printf '{"items":[],"page":1,"totalPages":0,"total":0}\n'; return 0; }
        url="${url}&q=${enc}"
    fi

    if [ "$sort" = "toplist" ]; then
        url="${url}&topRange=${range}"
    fi

    if [ -n "$ratio" ]; then
        url="${url}&ratios=${ratio}"
    fi

    raw=$(curl -s --max-time 10 "$url" -A "$UA")
    [ -n "$raw" ] || { printf '{"items":[],"page":1,"totalPages":0,"total":0}\n'; return 0; }

    printf '%s' "$raw" | jq -c '{
        items: ((.data // [])
            | map({
                image: .path,
                thumb: .thumbs.small,
                w: (.dimension_x // 0 | if . == null then 0 else . end),
                h: (.dimension_y // 0 | if . == null then 0 else . end)
              })
            | map(select(.image != null and .image != ""))),
        page: (.meta.current_page // 1),
        totalPages: (.meta.last_page // 1),
        total: (.meta.total // 0)
    }' 2>/dev/null || printf '{"items":[],"page":1,"totalPages":0,"total":0}\n'
}

download() {
    set -euo pipefail
    url="${1:-}"
    [ -n "$url" ] || exit 1

    flags="${XDG_STATE_HOME:-$HOME/.local/state}/ricelin/flags.json"
    wpdir=$(jq -r '.wallpaperDir // ""' "$flags" 2>/dev/null || echo "")
    [ -n "$wpdir" ] || wpdir="$HOME/Pictures/Wallpapers"
    dir="$wpdir/downloads"
    mkdir -p "$dir"

    tmp=$(mktemp "${TMPDIR:-/tmp}/ddg-wp.XXXXXX")
    trap 'rm -f "$tmp" "$tmp.out"' EXIT

    curl -fsL --max-time 30 -A "$UA" -o "$tmp" "$url" || exit 1
    [ -s "$tmp" ] || exit 1

    export MAGICK_CONFIGURE_PATH="$(dirname "$0")/magick-policy"

    fmt=$(magick identify -format '%m' "${tmp}[0]" 2>/dev/null | head -1) || exit 1

    case "$fmt" in
        JPEG) ext=jpg ;;
        PNG)  ext=png ;;
        *)    ext=png ;;
    esac

    out="$dir/wallhaven-$(date +%s)-${RANDOM}.${ext}"

    if [ "$ext" = "png" ] && [ "$fmt" != "PNG" ]; then
        magick "${tmp}[0]" -strip "png:$tmp.out" 2>/dev/null || exit 1
        [ -s "$tmp.out" ] || exit 1
        mv "$tmp.out" "$out"
    else
        cp "$tmp" "$out"
    fi

    [ -s "$out" ] || exit 1
    printf '%s\n' "$out"
}

case "${1:-}" in
    search)   search "${2:-}" "${3:-relevance}" "${4:-1M}" "${5:-100}" "${6:-111}" "${7:-}" "${8:-1}" ;;
    download) download "${2:-}" ;;
    *)        printf '[]\n'; exit 0 ;;
esac
