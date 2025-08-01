#!/bin/bash
# Script de migration des anciens dossiers HLS (satellite-...-...-...) vers le format standard GOES18.hi.GEOCOLOR.600x600
# À exécuter depuis la racine du projet

set -e

HLS_DIR="public/data/hls"

# Table de correspondance (ancien nom -> nouveau nom)
declare -A MAP=(
  ["satellite-GOES18-hi-GEOCOLOR-600x600"]="GOES18.hi.GEOCOLOR.600x600"
  ["satellite-GOES19-CONUS-GEOCOLOR-2500x1500"]="GOES19.CONUS.GEOCOLOR.2500x1500"
  ["satellite-GOES19-CONUS-GEOCOLOR-625x375"]="GOES19.CONUS.GEOCOLOR.625x375"
)

for old in "${!MAP[@]}"; do
  new="${MAP[$old]}"
  if [ -d "$HLS_DIR/$old" ]; then
    echo "Migration: $old -> $new"
    if [ -d "$HLS_DIR/$new" ]; then
      echo "  ⚠️  Dossier cible $new existe déjà, fusion des contenus..."
      rsync -a "$HLS_DIR/$old/" "$HLS_DIR/$new/"
      rm -rf "$HLS_DIR/$old"
    else
      mv "$HLS_DIR/$old" "$HLS_DIR/$new"
    fi
  else
    echo "Aucun dossier à migrer pour $old"
  fi
done

echo "✅ Migration terminée."
