
#!/bin/bash

# Script pour générer des vidéos HLS sur une période donnée (start_date, end_date inclus)
# Usage: ./generate-historical-data.sh START_DATE END_DATE

START_DATE="$1"
END_DATE="$2"

if [ -z "$START_DATE" ] || [ -z "$END_DATE" ]; then
  echo "Usage: $0 START_DATE END_DATE (format: YYYY-MM-DD)"
  exit 1
fi

echo "🕐 Génération de profondeur temporelle du $START_DATE au $END_DATE"

# Datasets activés (reprendre la logique du pipeline principal)
CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config"
DATASETS=($(jq -r '[.enabled_datasets // {} | to_entries[]] | .[] | select(.value.auto_download == true) | .key' "$CONFIG_DIR/datasets-status.json"))

if [ ${#DATASETS[@]} -eq 0 ]; then
  echo "Aucun dataset actif trouvé dans $CONFIG_DIR/datasets-status.json"
  exit 1
fi

current_date="$START_DATE"
while [[ "$current_date" < "$END_DATE" || "$current_date" == "$END_DATE" ]]; do
  for dataset_key in "${DATASETS[@]}"; do
    IFS='.' read -ra PARTS <<< "$dataset_key"
    satellite="${PARTS[0]}"
    sector="${PARTS[1]}"
    product="${PARTS[2]}"
    resolution="${PARTS[3]}"
    echo "📅 $current_date: Génération $satellite/$sector/$product/$resolution"
    ./scripts/generate-satellite-videos.sh generate "$satellite" "$sector" "$product" "$resolution" "$current_date" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo "   ✅ Vidéo générée"
    else
      # Exception : si c'est aujourd'hui et aucune image, ne rien signaler
      today=$(date +%Y-%m-%d)
      if [ "$current_date" != "$today" ]; then
        echo "   ⚠️ Pas d'images pour cette date"
      fi
    fi
  done
  # Pause tous les 10 jours
  if [ $(( $(date -d "$current_date" +%s) % 10 )) -eq 0 ]; then
    echo "   💤 Pause..."
    sleep 1
  fi
  current_date=$(date -I -d "$current_date + 1 day")
done

echo "🎯 Génération terminée !"
echo "📊 Total de playlists générées:"
find public/data/hls -name "playlist.m3u8" | wc -l
