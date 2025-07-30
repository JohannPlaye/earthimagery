#!/bin/bash

# Script simple pour créer de la profondeur temporelle (2 mois)
# en simulant des téléchargements historiques

echo "🕐 Génération de profondeur temporelle (60 jours)"

# Datasets activés
DATASETS=("GOES18.hi.GEOCOLOR.600x600" "GOES18.hi.FireTemperature.600x600")

# Générer pour les 60 derniers jours (2 mois)
for days_back in {1..60}; do
    date_str=$(date -d "-$days_back days" +'%Y-%m-%d')
    
    # Alterner les datasets pour simuler une disponibilité réaliste
    if [ $((days_back % 3)) -eq 0 ]; then
        dataset_idx=$((days_back % 2))
        dataset_key="${DATASETS[$dataset_idx]}"
        
        # Parser le dataset
        IFS='.' read -ra PARTS <<< "$dataset_key"
        satellite="${PARTS[0]}"
        sector="${PARTS[1]}"
        product="${PARTS[2]}"
        resolution="${PARTS[3]}"
        
        echo "📅 $date_str: Génération $satellite/$sector/$product/$resolution"
        
        # Générer la vidéo pour cette date
        ./scripts/generate-satellite-videos.sh generate "$satellite" "$sector" "$product" "$resolution" "$date_str" >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo "   ✅ Vidéo générée"
        else
            echo "   ⚠️ Pas d'images pour cette date"
        fi
    fi
    
    # Pause pour éviter de surcharger
    if [ $((days_back % 10)) -eq 0 ]; then
        echo "   💤 Pause..."
        sleep 1
    fi
done

echo "🎯 Génération terminée !"
echo "📊 Total de playlists générées:"
find public/data/hls -name "playlist.m3u8" -path "*/satellite-*" | wc -l
