#!/bin/bash

source .env.local

echo "🕐 Test horaire VIS06 pour aujourd'hui - $(date)"

test_hour() {
    local hour="$1"
    local timestamp="2025-08-21T${hour}:00:00.000Z"
    
    curl -s -o "test_${hour//:/}.png" "https://view.eumetsat.int/geoserver/ows?service=WMS&request=GetMap&version=1.3.0&layers=mtg_fd:vis06_hrfi&styles=&format=image/png&crs=EPSG:4326&bbox=-80,-60,80,80&width=2000&height=2000&time=${timestamp}&access_token=${EUMETSAT_TOKEN}"
    
    if [ -f "test_${hour//:/}.png" ]; then
        local size=$(stat -c%s "test_${hour//:/}.png")
        local hash=$(md5sum "test_${hour//:/}.png" | cut -d' ' -f1)
        echo "$hour: $size bytes - Hash: ${hash:0:8}"
        rm "test_${hour//:/}.png"
    fi
}

# Test heure par heure
for hour in "09:00" "09:15" "09:30" "09:45" "10:00" "10:15" "10:30" "10:45" "11:00" "11:15" "11:30" "11:45" "12:00" "12:15" "12:30"; do
    test_hour "$hour"
done
