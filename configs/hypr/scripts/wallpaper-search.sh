#!/usr/bin/env bash

LOG="/tmp/wallpaper-search.log"
UA="Mozilla/5.0 (X11; Linux x86_64) Gecko/20100101 Firefox/126.0"

search() {
    local query="${1:-}"
    local sort="${2:-relevance}"
    local range="${3:-1M}"
    local purity="${4:-100}"
    local categories="${5:-111}"
    local ratio="${6:-}"
    local page="${7:-1}"

    echo "[$(date +%H:%M:%S)] CALL query=\"$query\" sort=$sort purity=$pur page=$page" >> "$LOG"

    local url="https://wallhaven.cc/api/v1/search?atleast=2560x1440&purity=${purity}&sorting=${sort}&categories=${categories}&page=${page}&apikey=EC0aZgPiNJsb3Nq9TsRoyub16cQLhLDi"

    if [ -n "$query" ]; then
        local enc
        enc=$(jq -rn --arg q "$query" '$q|@uri') || { printf '{"error":"jq uri encoding failed","items":[]}\n'; return 0; }
        url="${url}&q=${enc}"
    fi

    if [ "$sort" = "toplist" ]; then
        url="${url}&topRange=${range}"
    fi

    if [ -n "$ratio" ]; then
        url="${url}&ratios=${ratio}"
    fi

    local retry_count=0
    local max_retries=3
    local raw=""
    local http_code=0

    while [ $retry_count -lt $max_retries ]; do
        local resp
        resp=$(curl -s --max-time 10 -w "\n%{http_code}" "$url" -A "$UA")
        http_code=$(echo "$resp" | tail -n1)
        raw=$(echo "$resp" | sed '$d')

        case "$http_code" in
            200) break ;;
            401|403)
                printf '{"error":"Wallhaven API auth failed (HTTP %s)","items":[]}\n' "$http_code"
                return 0
                ;;
            429)
                retry_count=$((retry_count + 1))
                sleep $((2 ** retry_count))
                ;;
            *)
                printf '{"error":"Wallhaven API returned HTTP %s","items":[]}\n' "$http_code"
                return 0
                ;;
        esac
    done

    [ -n "$raw" ] || { printf '{"error":"Empty response from Wallhaven","items":[]}\n'; echo "[$(date +%H:%M:%S)] EMPTY HTTP=$http_code URL=$url" >> "$LOG"; return 0; }

    local result
    result=$(printf '%s' "$raw" | jq -c '{
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
    }' 2>&1) || { printf '{"error":"jq parse failed: %s","items":[]}\n' "$(printf '%s' "$raw" | head -c 200)"; echo "[$(date +%H:%M:%S)] JQ_FAIL http=$http_code raw=$(printf '%s' "$raw" | head -c 300)" >> "$LOG"; return 0; }

    echo "[$(date +%H:%M:%S)] OK items=$(printf '%s' "$result" | jq -c '[.items[]] | length') page=$page url=$url" >> "$LOG"
    printf '%s\n' "$result"
}

search_moewalls() {
    local query="${1:-}"
    local resolution="${2:-2560x1440}"
    local order="${3:-most_upvotes}"
    local page="${4:-1}"
    echo "[$(date +%H:%M:%S)] MOE query=\"$query\" res=$resolution order=$order page=$page" >> "$LOG"
    UA="$UA" python3 - "$query" "$resolution" "$order" "$page" <<'PYEOF'
import concurrent.futures
import json
import os
import re
import sys
import urllib.parse
import urllib.request

ua = os.environ.get("UA", "Mozilla/5.0")
query = sys.argv[1]
resolution = sys.argv[2]
order = sys.argv[3]
page = int(sys.argv[4])

min_w, min_h = (int(x) for x in resolution.split("x"))

def fetch(url, timeout=10):
    req = urllib.request.Request(url, headers={"User-Agent": ua, "Referer": "https://moewalls.com/"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "ignore")

def post_entry(url):
    try:
        html = fetch(url)
        prev = re.search(r'<source src="(/wp-content/uploads/preview/[^"]+)"', html)
        token = re.search(r'id="moe-download"[^>]*data-url="([^"]+)"', html)
        thumb = re.search(r'poster="([^"]+)"', html)
        if not prev or not token:
            return None
        res = re.search(r'resolutions-(\d+)x(\d+)', html)
        w = int(res.group(1)) if res else 0
        h = int(res.group(2)) if res else 0
        if w < min_w or h < min_h:
            return None
        category = re.search(r'entry-category[^>]*>([^<]+)', html)
        votes = re.search(r'entry-votes.*?<strong>(\d+)', html)
        title_m = re.search(r'<title>([^<]+)', html)
        return {
            "image": "https://go.moewalls.com/download.php?video=" + token.group(1),
            "thumb": urllib.parse.urljoin("https://moewalls.com/", thumb.group(1)) if thumb else "",
            "preview": urllib.parse.urljoin("https://moewalls.com/", prev.group(1)),
            "w": w, "h": h,
            "category": category.group(1).strip() if category else "",
            "votes": int(votes.group(1)) if votes else 0,
            "resolution": res.group(0) if res else "",
            "title": title_m.group(1).strip() if title_m else "",
        }
    except Exception:
        return None

try:
    if query.strip():
        q = urllib.parse.quote(query)
        if page > 1:
            base_url = f"https://moewalls.com/page/{page}/?s={q}"
        else:
            base_url = f"https://moewalls.com/?s={q}"
    else:
        if page > 1:
            base_url = f"https://moewalls.com/resolution/{resolution}/page/{page}/"
        else:
            base_url = f"https://moewalls.com/resolution/{resolution}/"
    if order:
        base_url += ("&" if "?" in base_url else "?") + f"order={order}"

    page_html = fetch(base_url, timeout=12)
    posts = []
    for m in re.finditer(r'href="(https://moewalls\.com/[a-z0-9-]+/[a-z0-9-]+-live-wallpaper/)"', page_html):
        if m.group(1) not in posts:
            posts.append(m.group(1))
    out = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as ex:
        for entry in ex.map(post_entry, posts[:36]):
            if entry:
                out.append(entry)
    print(json.dumps(out))
except Exception as e:
    print("[]")
PYEOF
}

download() {
    set -euo pipefail
    url="${1:-}"
    [ -n "$url" ] || exit 1

    flags="${XDG_STATE_HOME:-$HOME/.local/state}/ricelin/flags.json"
    wpdir=$(jq -r '.wallpaperDir // ""' "$flags" 2>/dev/null || echo "")
    [ -n "$wpdir" ] || wpdir=$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/ricelin-wallpaper-dir" 2>/dev/null || true)
    [ -n "$wpdir" ] || wpdir="$HOME/Pictures/Wallpapers"
    dir="$wpdir/downloads"
    mkdir -p "$dir"

    case "$url" in
        https://go.moewalls.com/download.php*)
            fn=$(curl -fsI --max-time 20 -A "$UA" -e "https://moewalls.com/" "$url" \
                | grep -oiP 'filename=\K[^"\r\n;]+' | head -1 | tr -d '/\\')
            [ -n "$fn" ] || fn="moewalls-$(date +%s).mp4"
            out="$dir/$fn"
            curl -fsL --max-time 600 -A "$UA" -e "https://moewalls.com/" -o "$out" "$url" || exit 1
            [ -s "$out" ] || exit 1
            printf '%s\n' "$out"
            exit 0
            ;;
        *)
            local content_type
            content_type=$(curl -fsI --max-time 5 -A "$UA" "$url" | grep -i '^content-type:' | head -1 | tr -d '\r')
            case "$content_type" in
                *video*)
                    fn="wallhaven-video-$(date +%s)-${RANDOM}.mp4"
                    out="$dir/$fn"
                    curl -fsL --max-time 600 -A "$UA" -o "$out" "$url" || exit 1
                    [ -s "$out" ] || exit 1
                    printf '%s\n' "$out"
                    exit 0
                    ;;
            esac
            ;;
    esac

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
    search_moewalls) search_moewalls "${2:-}" "${3:-2560x1440}" "${4:-most_upvotes}" "${5:-1}" ;;
    download) download "${2:-}" ;;
    *)        printf '[]\n'; exit 0 ;;
esac
