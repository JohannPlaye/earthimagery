#!/bin/bash

# Test spécifique VIS06 - focus sur la transition jour/fallback
source .env.local

echo "🎯 Test VIS06 transition jour/fallback - $(date)"

# Test dans la fenêtre où on sait qu'il y a de vraies images puis fallback
test_timestamps=(
    "2025-08-21T08:00:00.000Z"
    "2025-08-21T09:00:00.000Z"
    "2025-08-21T10:00:00.000Z"
    "2025-08-21T10:15:00.000Z"
    "2025-08-21T10:30:00.000Z"
    "2025-08-21T10:45:00.000Z"
    "2025-08-21T11:00:00.000Z"
    "2025-08-21T11:15:00.000Z"
)

mkdir -p "test_transition"

echo "📊 Test de la séquence de transition:"
for timestamp in "${test_timestamps[@]}"; do
    filename="vis06_$(echo "$timestamp" | sed 's/[:-]//g' | cut -c1-15).png"
    curl -s -o "test_transition/$filename" "https://view.eumetsat.int/geoserver/ows?service=WMS&request=GetMap&version=1.3.0&layers=mtg_fd:vis06_hrfi&styles=&format=image/png&crs=EPSG:4326&bbox=-80,-60,80,80&width=2000&height=2000&time=${timestamp}&access_token=${EUMETSAT_TOKEN}"
    
    if [ -f "test_transition/$filename" ]; then
        size=$(stat -c%s "test_transition/$filename")
        hash=$(md5sum "test_transition/$filename" | cut -d' ' -f1)
        time_only=$(echo "$timestamp" | cut -d'T' -f2 | cut -d':' -f1-2)
        
        # Test de détection
        if [ "$hash" = "9c4b8cfe900cfdeaedc49bee40ad63bc" ] && [ "$size" = "74212" ]; then
            echo "$time_only: $size bytes - Hash: ${hash:0:8} 🚫 FALLBACK"
        else
            echo "$time_only: $size bytes - Hash: ${hash:0:8} ✅ Vraie image"
        fi
    fi
done

echo ""
echo "📈 Résumé des transitions:"
cd test_transition
prev_hash=""
for f in vis06_*.png; do
    if [ -f "$f" ]; then
        hash=$(md5sum "$f" | cut -d' ' -f1)
        size=$(stat -c%s "$f")
        time=$(echo "$f" | sed 's/vis06_//g' | sed 's/.png//g' | sed 's/\(..\)\(..\)\(..\)T\(..\)\(..\)\(..\).*/\1:\2:\3 \4:\5:\6/')
        
        if [ "$hash" = "$prev_hash" ] && [ -n "$prev_hash" ]; then
            echo "$time: IDENTIQUE à la précédente"
        else
            echo "$time: NOUVELLE image"
        fi
        prev_hash="$hash"
    fi
done

cd ..
rm -rf test_transition
