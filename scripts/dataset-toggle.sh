#!/bin/bash

# Script simple pour activer/désactiver les datasets
# Usage: ./dataset-toggle.sh [enable|disable] SATELLITE SECTOR PRODUCT RESOLUTION [AUTO_DOWNLOAD]

ACTION="$1"
SATELLITE="$2"
SECTOR="$3"
PRODUCT="$4"
RESOLUTION="$5"
AUTO_DOWNLOAD="${6:-false}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TRACKING_FILE="$PROJECT_ROOT/config/download-tracking.json"

# Validation des paramètres
if [ "$#" -lt 5 ]; then
    echo "❌ Usage: $0 [enable|disable] SATELLITE SECTOR PRODUCT RESOLUTION [AUTO_DOWNLOAD]"
    exit 1
fi

if [ ! -f "$TRACKING_FILE" ]; then
    echo "❌ Fichier de tracking non trouvé: $TRACKING_FILE"
    exit 1
fi

# Construction de la clé du dataset
DATASET_KEY="${SATELLITE}.${SECTOR}.${PRODUCT}.${RESOLUTION}"

case "$ACTION" in
    "enable")
        echo "🔧 Activation du dataset: $DATASET_KEY"
        
        # Créer ou mettre à jour l'entrée du dataset
        jq --arg key "$DATASET_KEY" \
           --arg satellite "$SATELLITE" \
           --arg sector "$SECTOR" \
           --arg product "$PRODUCT" \
           --arg resolution "$RESOLUTION" \
           --arg auto "$AUTO_DOWNLOAD" \
           --arg timestamp "$(date -Iseconds)" \
           '.tracking[$key] = {
             "dataset_info": {
               "satellite": $satellite,
               "sector": $sector,
               "product": $product,
               "resolution": $resolution,
               "enabled": true,
               "auto_download": ($auto == "true")
             },
             "total_images_downloaded": (.tracking[$key].total_images_downloaded // 0),
             "last_download": (.tracking[$key].last_download // null),
             "daily_status": (.tracking[$key].daily_status // {})
           } |
           .last_update = $timestamp' \
           "$TRACKING_FILE" > "$TRACKING_FILE.tmp" && mv "$TRACKING_FILE.tmp" "$TRACKING_FILE"
        
        if [ $? -eq 0 ]; then
            echo "✅ Dataset $DATASET_KEY activé"
        else
            echo "❌ Erreur lors de l'activation"
            exit 1
        fi
        ;;
        
    "disable")
        echo "🔧 Désactivation du dataset: $DATASET_KEY"
        
        # Désactiver le dataset (garder les données)
        jq --arg key "$DATASET_KEY" \
           --arg timestamp "$(date -Iseconds)" \
           '.tracking[$key].dataset_info.enabled = false |
           .last_update = $timestamp' \
           "$TRACKING_FILE" > "$TRACKING_FILE.tmp" && mv "$TRACKING_FILE.tmp" "$TRACKING_FILE"
        
        if [ $? -eq 0 ]; then
            echo "✅ Dataset $DATASET_KEY désactivé"
        else
            echo "❌ Erreur lors de la désactivation"
            exit 1
        fi
        ;;
        
    *)
        echo "❌ Action non reconnue: $ACTION"
        echo "Usage: $0 [enable|disable] SATELLITE SECTOR PRODUCT RESOLUTION [AUTO_DOWNLOAD]"
        exit 1
        ;;
esac
