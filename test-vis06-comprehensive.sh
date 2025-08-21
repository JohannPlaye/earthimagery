#!/bin/bash

# Test approfondi VIS06 - investigation de l'API EUMETSAT
# Date: 2025-08-21

source .env.local

echo "🔍 Investigation approfondie VIS06 - $(date)"
echo "Token EUMETSAT: ${EUMETSAT_TOKEN:0:10}..."

# Test avec différentes heures et différents jours
test_vis06_comprehensive() {
    local date="$1"
    local description="$2"
    
    echo ""
    echo "📅 Test $description - $date"
    echo "=================================================="
    
    # Test quelques heures spécifiques dans la journée
    local timestamps=(
        "00:00:00.000Z"
        "03:00:00.000Z" 
        "06:00:00.000Z"
        "09:00:00.000Z"
        "12:00:00.000Z"
        "15:00:00.000Z"
        "18:00:00.000Z"
        "21:00:00.000Z"
    )
    
    local temp_dir="temp_vis06_comprehensive"
    mkdir -p "$temp_dir"
    
    for timestamp in "${timestamps[@]}"; do
        local full_timestamp="${date}T${timestamp}"
        local url="https://view.eumetsat.int/geoserver/ows?service=WMS&request=GetMap&version=1.3.0&layers=mtg_fd:vis06_hrfi&styles=&format=image/png&crs=EPSG:4326&bbox=-80,-60,80,80&width=2000&height=2000&time=${full_timestamp}&access_token=${EUMETSAT_TOKEN}"
        
        local output_file="vis06_${date}_${timestamp//[:.]/}.png"
        
        echo "📡 Test: $full_timestamp"
        curl -s -o "${temp_dir}/${output_file}" "$url"
        
        if [ -f "${temp_dir}/${output_file}" ]; then
            local file_size=$(stat -c%s "${temp_dir}/${output_file}")
            local file_hash=$(md5sum "${temp_dir}/${output_file}" | cut -d' ' -f1)
            
            echo "  ✅ ${file_size} bytes - Hash: ${file_hash:0:8}"
        else
            echo "  ❌ Échec"
        fi
    done
    
    echo ""
    echo "📊 Résumé des hashes pour $date:"
    cd "$temp_dir"
    for f in vis06_${date//[-]/}_*.png; do
        if [ -f "$f" ]; then
            hash=$(md5sum "$f" | cut -d' ' -f1)
            size=$(stat -c%s "$f")
            timestamp=$(echo "$f" | sed "s/vis06_${date//[-]/}_//g" | sed 's/.png//g' | sed 's/\(..\)\(..\)\(..\)000Z/\1:\2:\3/')
            echo "  $timestamp: $hash ($size bytes)"
        fi
    done
    cd ..
    
    # Compter les images uniques
    local unique_hashes=$(cd "$temp_dir" && md5sum vis06_${date//[-]/}_*.png 2>/dev/null | cut -d' ' -f1 | sort -u | wc -l)
    echo "  📈 Images uniques: $unique_hashes/8"
    
    rm -rf "$temp_dir"
}

# Tests sur différents jours
test_vis06_comprehensive "2025-08-21" "Aujourd'hui"
test_vis06_comprehensive "2025-08-20" "Hier"
test_vis06_comprehensive "2025-08-19" "Avant-hier"

echo ""
echo "🔍 Test terminé - Comparaison avec Geocolor..."

# Test de comparaison rapide avec Geocolor sur le même créneau
echo "📊 Comparaison VIS06 vs Geocolor pour aujourd'hui 12:00:"
mkdir -p temp_comparison

# VIS06
curl -s -o "temp_comparison/vis06_1200.png" "https://view.eumetsat.int/geoserver/ows?service=WMS&request=GetMap&version=1.3.0&layers=mtg_fd:vis06_hrfi&styles=&format=image/png&crs=EPSG:4326&bbox=-80,-60,80,80&width=2000&height=2000&time=2025-08-21T12:00:00.000Z&access_token=${EUMETSAT_TOKEN}"

# Geocolor
curl -s -o "temp_comparison/geocolor_1200.png" "https://view.eumetsat.int/geoserver/ows?service=WMS&request=GetMap&version=1.3.0&layers=mtg_fd:rgb_geocolour&styles=&format=image/png&crs=EPSG:4326&bbox=-80,-60,80,80&width=2000&height=2000&time=2025-08-21T12:00:00.000Z&access_token=${EUMETSAT_TOKEN}"

echo "VIS06 12:00:"
if [ -f "temp_comparison/vis06_1200.png" ]; then
    file "temp_comparison/vis06_1200.png"
    echo "  Size: $(stat -c%s temp_comparison/vis06_1200.png) bytes"
    echo "  Hash: $(md5sum temp_comparison/vis06_1200.png | cut -d' ' -f1)"
fi

echo "Geocolor 12:00:"
if [ -f "temp_comparison/geocolor_1200.png" ]; then
    file "temp_comparison/geocolor_1200.png"
    echo "  Size: $(stat -c%s temp_comparison/geocolor_1200.png) bytes"
    echo "  Hash: $(md5sum temp_comparison/geocolor_1200.png | cut -d' ' -f1)"
fi

rm -rf temp_comparison
