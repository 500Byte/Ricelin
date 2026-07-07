#!/usr/bin/env bash

# Color codes
DIM=$'\e[38;2;91;102;120m'  # Dim label color
G=$'\e[38;2;91;191;115m'    # Accent color (green)
T=$'\e[38;2;196;204;218m'   # Light gray text
X=$'\e[0m'                  # Reset color

# Current hour
hour=$(date +%H)
greeting=""

if [ "$hour" -ge 5 ] && [ "$hour" -lt 12 ]; then
    # Morning greetings
    greetings=(
        "Buenos días. ¿Listo para mover un elemento 1px a la izquierda?"
        "Ese espaciado asimétrico me está dando ansiedad..."
        "Diseño impecable, código... ya veremos."
    )
elif [ "$hour" -ge 12 ] && [ "$hour" -lt 18 ]; then
    # Afternoon greetings
    greetings=(
        "Ah, otra vez por aquí. ¿Alineando divs o peleando con tipografías?"
        "Tu código no compila, pero al menos la interfaz se ve hermosa."
        "¿Listo para criticar la UI de alguien más hoy?"
    )
else
    # Night greetings
    greetings=(
        "Ve a dormir. Ninguna buena decisión de UX se toma después de medianoche."
        "Hoy el kerning se ve bien. Tú... no tanto."
        "¿Alineando pixeles en la oscuridad? Clásico."
    )
fi

# Pick a random greeting from the array
rand_idx=$((RANDOM % ${#greetings[@]}))
greeting="${greetings[$rand_idx]}"

echo "$greeting"
