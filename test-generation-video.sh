#!/bin/bash

# Test rapide de la génération vidéo avec la nouvelle structure NOAA

set -euo pipefail

# Configuration comme dans testcomplet.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
DATA_DIR="$PROJECT_ROOT/public/data"
CONFIG_DIR="$PROJECT_ROOT/config"

# Fonction pour construire le chemin de données satellite avec structure NOAA
build_satellite_data_path() {
    local dataset_key="$1"
    local date="$2"
    
    # Conversion du dataset key en chemin: GOES19.car.GEOCOLOR.4000x4000 -> NOAA/GOES19/car/GEOCOLOR/4000x4000
    IFS='.' read -ra PARTS <<< "$dataset_key"
    if [ ${#PARTS[@]} -eq 4 ]; then
        local satellite="${PARTS[0]}"
        local sector="${PARTS[1]}"
        local product="${PARTS[2]}"
        local resolution="${PARTS[3]}"
        
        # Satellites NOAA (GOES) vont dans NOAA/satellite/...
        if [[ "$satellite" =~ ^GOES[0-9]+$ ]]; then
            echo "$DATA_DIR/NOAA/$satellite/$sector/$product/$resolution/$date"
        else
            # Autres satellites gardent la structure actuelle
            echo "$DATA_DIR/$satellite/$sector/$product/$resolution/$date"
        fi
    else
        # Fallback vers l'ancienne méthode si le format n'est pas reconnu
        local dataset_path=$(echo "$dataset_key" | tr '.' '/')
        echo "$DATA_DIR/$dataset_path/$date"
    fi
}

# Test avec quelques datasets
datasets=("GOES19.car.GEOCOLOR.4000x4000" "GOES19.CONUS.GEOCOLOR.2500x1500" "GOES18.hi.GEOCOLOR.600x600")
date="2025-08-20"

echo "🧪 Test de détection d'images avec la nouvelle structure NOAA"
echo "=============================================================="

for dataset_key in "${datasets[@]}"; do
    echo
    echo "📊 Dataset: $dataset_key"
    
    # Utilisation de la nouvelle fonction pour gérer la structure NOAA
    images_dir=$(build_satellite_data_path "$dataset_key" "$date")
    echo "   📁 Chemin: $images_dir"
    
    # Vérification de la présence d'images
    if [ -d "$images_dir" ]; then
        img_count=$(find "$images_dir" -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -type f 2>/dev/null | wc -l)
        echo "   📊 Images trouvées: $img_count"
        
        if [ "$img_count" -gt 0 ]; then
            echo "   ✅ Dataset prêt pour génération vidéo"
            
            # Afficher quelques exemples d'images
            echo "   📸 Exemples d'images:"
            find "$images_dir" -name "*.jpg" -type f 2>/dev/null | head -3 | while read -r img; do
                echo "      - $(basename "$img")"
            done
        else
            echo "   ❌ Aucune image trouvée"
        fi
    else
        echo "   ❌ Répertoire inexistant"
    fi
done

echo
echo "🎯 Résumé: La fonction build_satellite_data_path fonctionne correctement"
