#!/usr/bin/env bash

# Color codes
DIM=$'\e[38;2;91;102;120m'  # Dim label color
G=$'\e[38;2;91;191;115m'    # Accent color (green)
T=$'\e[38;2;196;204;218m'   # Light gray text
X=$'\e[0m'                  # Reset color

# Current hour
hour=$(date +%H)
# Load greeting strings
STRINGS_FILE="/home/diego/.config/fish/welcome_strings.sh"
if [ -f "$STRINGS_FILE" ]; then
    source "$STRINGS_FILE"
else
    greetings_morning=("Diseño impecable, código... ya veremos.")
    greetings_afternoon=("Tu código no compila, pero al menos la interfaz se ve hermosa.")
    greetings_night=("Hoy el kerning se ve bien. Tú... no tanto.")
fi

if [ "$hour" -ge 5 ] && [ "$hour" -lt 12 ]; then
    greetings=("${greetings_morning[@]}")
elif [ "$hour" -ge 12 ] && [ "$hour" -lt 18 ]; then
    greetings=("${greetings_afternoon[@]}")
else
    greetings=("${greetings_night[@]}")
fi

# Pick a random greeting from the array
rand_idx=$((RANDOM % ${#greetings[@]}))
greeting="${greetings[$rand_idx]}"

# Uptime parsing
upt=$(uptime -p | sed 's/^up //')

# Weather caching (async)
cache_file="/home/diego/.cache/terminal_weather"
mkdir -p "$(dirname "$cache_file")"

current_time=$(date +%s)
last_modified=0
if [ -f "$cache_file" ]; then
    last_modified=$(date -r "$cache_file" +%s 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)
fi

if [ $((current_time - last_modified)) -gt 1800 ] || [ ! -s "$cache_file" ]; then
    nohup bash -c '
        weather=$(curl -s --connect-timeout 2 "wttr.in/Santa_Marta?format=%c%t" 2>/dev/null)
        if [ -n "$weather" ] && [[ ! "$weather" =~ "<html>" ]] && [[ ! "$weather" =~ "Error" ]]; then
            echo "$weather" | sed "s/+//g" | xargs > "'"$cache_file"'"
        fi
    ' >/dev/null 2>&1 &
fi

weather_info="N/A"
if [ -s "$cache_file" ]; then
    weather_info=$(cat "$cache_file")
fi

# Print greeting line
# For length calculation we use the string without color codes:
raw_first_line="${greeting} ✨  ·  Santa Marta: ${weather_info}  ·  Uptime: ${upt}"
char_count=$(echo -n "$raw_first_line" | wc -m)

# Format first line with colors
first_line="${T}${greeting}${X} ${G}✨${X}  ${DIM}·${X}  ${DIM}Santa Marta:${X} ${T}${weather_info}${X}  ${DIM}·${X}  ${DIM}Uptime:${X} ${T}${upt}${X}"
echo -e "$first_line"

# Generate divider
divider=""
for ((i=0; i<char_count; i++)); do
    divider="${divider}─"
done
echo -e "${DIM}${divider}${X}"

# Gather metrics
# CPU Usage & Temp
read -ra a < /proc/stat
sleep 0.08
read -ra b < /proc/stat
t1=0; for v in "${a[@]:1}"; do t1=$((t1+v)); done
t2=0; for v in "${b[@]:1}"; do t2=$((t2+v)); done
id1=$((a[4]+a[5])); id2=$((b[4]+b[5]))
dt=$((t2-t1)); di=$((id2-id1))
cpu=$(( dt>0 ? 100*(dt-di)/dt : 0 ))

cpu_temp="--"
for hw in /sys/class/hwmon/hwmon*; do
    if [ -f "$hw/name" ] && [ "$(cat "$hw/name" 2>/dev/null)" = "k10temp" ]; then
        if [ -f "$hw/temp1_input" ]; then
            cpu_temp=$(( $(cat "$hw/temp1_input") / 1000 ))
        fi
        break
    fi
done

# AMD GPU Usage & Temp
gpu="--"
gpu_temp="--"
for gpath in /sys/class/drm/card*/device; do
    if [ -f "$gpath/gpu_busy_percent" ]; then
        gpu=$(cat "$gpath/gpu_busy_percent")
        for hpath in "$gpath"/hwmon/hwmon* "$gpath"/hwmon*; do
            if [ -f "$hpath/temp1_input" ]; then
                gpu_temp=$(( $(cat "$hpath/temp1_input") / 1000 ))
                break
            fi
        done
        break
    fi
done

# RAM Usage
mt=$(awk '/MemTotal/{print $2}' /proc/meminfo)
ma=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
mu=$((mt-ma))
rused=$(awk "BEGIN{printf \"%.1f\",$mu/1048576}")
rtot=$(awk "BEGIN{printf \"%.0f\",$mt/1048576}")
rpct=$((100*mu/mt))

# Disk Usage
read -r dpct davail < <(df -BG --output=pcent,avail / 2>/dev/null | tail -1)
dpct=${dpct// /}
davail=${davail// /}
davail=${davail%G}

# Print metrics line using Nerd Fonts icons ( CPU: ..., GPU: ..., RAM: ..., Disco: ... )
# cpu icon: , gpu icon: 󰢮, ram icon: , disk icon: 󰋊
echo -e "${G}${X}  ${DIM}CPU:${X} ${T}${cpu}% (${cpu_temp}°C)${X}    ${G}󰢮${X}  ${DIM}GPU:${X} ${T}${gpu}% (${gpu_temp}°C)${X}    ${G}${X}  ${DIM}RAM:${X} ${T}${rused}/${rtot} GB (${rpct}%)${X}    ${G}󰋊${X}  ${DIM}Disco:${X} ${T}${davail} GB libres (${dpct})${X}"
