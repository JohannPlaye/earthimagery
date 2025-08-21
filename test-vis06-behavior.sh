#!/bin/bash

# Test du comportement VIS06 - analyse détaillée
# Date: 2025-08-21

source scripts/.env

echo "🔍 Analyse comportement VIS06 - $(date)"
echo "Token EUMETSAT: ${EUMETSAT_TOKEN:0:10}..."

# Fonction pour tester un timestamp spécifique
test_vis06_timestamp() {
    local timestamp="$1"
    local description="$2"
    
    echo ""
    echo "📅 Test $description - $timestamp"
    echo "=================================================="
    
    local url="https://view.eumetsat.int/geoserver/ows?service=WMS&request=GetMap&version=1.3.0&layers=mtg_fd:vis06_hrfi&styles=&format=image/png&crs=EPSG:4326&bbox=-90,-180,90,180&width=2000&height=2000&time=${timestamp}&access_token=${EUMETSAT_TOKEN}"
    
    local output_file="test_vis06_${timestamp//[:-]/}.png"
    local temp_dir="temp_vis06_test"
    mkdir -p "$temp_dir"
    
    echo "📡 Téléchargement: $timestamp"
    curl -s -o "${temp_dir}/${output_file}" "$url"
    
    if [ -f "${temp_dir}/${output_file}" ]; then
        local file_size=$(stat -c%s "${temp_dir}/${output_file}")
        local file_hash=$(md5sum "${temp_dir}/${output_file}" | cut -d' ' -f1)
        
        echo "✅ Téléchargé: ${file_size} bytes"
        echo "🔐 Hash MD5: ${file_hash}"
        
        # Vérifier si c'est une vraie image PNG
        file "${temp_dir}/${output_file}"
        
    else
        echo "❌ Échec téléchargement"
    fi
}

# Tests de timestamps spécifiques
test_vis06_timestamp "2025-08-21T00:00:00.000Z" "Minuit (00:00)"
test_vis06_timestamp "2025-08-21T06:00:00.000Z" "Matin (06:00)"
test_vis06_timestamp "2025-08-21T10:15:00.000Z" "Matinée (10:15)"
test_vis06_timestamp "2025-08-21T12:00:00.000Z" "Midi (12:00)"
test_vis06_timestamp "2025-08-21T18:00:00.000Z" "Soir futur (18:00)"
test_vis06_timestamp "2025-08-21T23:45:00.000Z" "Fin futur (23:45)"

echo ""
echo "📊 Comparaison des hashes pour détecter les doublons:"
echo "=================================================="
cd temp_vis06_test
for f in *.png; do
    if [ -f "$f" ]; then
        hash=$(md5sum "$f" | cut -d' ' -f1)
        size=$(stat -c%s "$f")
        echo "$f: $hash ($size bytes)"
    fi
done

echo ""
echo "🔍 Analyse terminée - nettoyage..."
cd ..
rm -rf temp_vis06_test
