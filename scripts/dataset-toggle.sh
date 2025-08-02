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
CONFIG_FILE="$PROJECT_ROOT/config/datasets-status.json"

# Validation des paramètres
if [ "$#" -lt 5 ]; then
    echo "❌ Usage: $0 [enable|disable|toggle-download] SATELLITE SECTOR PRODUCT RESOLUTION [AUTO_DOWNLOAD]"
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Fichier de configuration non trouvé: $CONFIG_FILE"
    exit 1
fi

# Construction de la clé du dataset
DATASET_KEY="${SATELLITE}.${SECTOR}.${PRODUCT}.${RESOLUTION}"

case "$ACTION" in
    "enable")
        echo "🔧 Activation du dataset: $DATASET_KEY"
        
        # Vérifier si le dataset existe dans discovered_datasets
        if jq -e ".discovered_datasets[\"$DATASET_KEY\"]" "$CONFIG_FILE" >/dev/null 2>&1; then
            # Déplacer de discovered_datasets vers enabled_datasets
            jq --arg key "$DATASET_KEY" \
               --arg auto "$AUTO_DOWNLOAD" \
               --arg timestamp "$(date -Iseconds)" \
               '(.enabled_datasets[$key] = .discovered_datasets[$key]) |
               .enabled_datasets[$key].auto_download = ($auto == "true") |
               del(.discovered_datasets[$key]) |
               .last_update = $timestamp' \
               "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        elif jq -e ".disabled_datasets[\"$DATASET_KEY\"]" "$CONFIG_FILE" >/dev/null 2>&1; then
            # Déplacer de disabled_datasets vers enabled_datasets
            jq --arg key "$DATASET_KEY" \
               --arg auto "$AUTO_DOWNLOAD" \
               --arg timestamp "$(date -Iseconds)" \
               '(.enabled_datasets[$key] = .disabled_datasets[$key]) |
               .enabled_datasets[$key].auto_download = ($auto == "true") |
               del(.disabled_datasets[$key]) |
               .last_update = $timestamp' \
               "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        else
            # Vérifier si déjà dans enabled_datasets et juste mettre à jour auto_download
            if jq -e ".enabled_datasets[\"$DATASET_KEY\"]" "$CONFIG_FILE" >/dev/null 2>&1; then
                jq --arg key "$DATASET_KEY" \
                   --arg auto "$AUTO_DOWNLOAD" \
                   --arg timestamp "$(date -Iseconds)" \
                   '.enabled_datasets[$key].auto_download = ($auto == "true") |
                   .last_update = $timestamp' \
                   "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
            else
                echo "❌ Dataset non trouvé dans discovered_datasets, disabled_datasets ou enabled_datasets"
                exit 1
            fi
        fi
        
        if [ $? -eq 0 ]; then
            echo "✅ Dataset $DATASET_KEY activé"
        else
            echo "❌ Erreur lors de l'activation"
            exit 1
        fi
        ;;

        "set-default")
        echo "🔧 Définition du dataset par défaut: $DATASET_KEY"
        # Exclusivité : retire le flag default_display de tous les autres datasets
        if jq -e ".enabled_datasets[\"$DATASET_KEY\"]" "$CONFIG_FILE" >/dev/null 2>&1; then
            jq --arg key "$DATASET_KEY" '
              .enabled_datasets |= with_entries(
                if .key == $key then .value.default_display = true else .value.default_display = false end
              )' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
            if [ $? -eq 0 ]; then
                echo "✅ Dataset $DATASET_KEY défini comme affiché par défaut"
            else
                echo "❌ Erreur lors de la définition du dataset par défaut"
                exit 1
            fi
        else
            echo "❌ Dataset non trouvé dans enabled_datasets"
            exit 1
        fi
        ;;
        
    "disable")
        echo "🔧 Désactivation du dataset: $DATASET_KEY"
        
        # Déplacer de enabled_datasets vers disabled_datasets
        if jq -e ".enabled_datasets[\"$DATASET_KEY\"]" "$CONFIG_FILE" >/dev/null 2>&1; then
            jq --arg key "$DATASET_KEY" \
               --arg timestamp "$(date -Iseconds)" \
               '(.disabled_datasets[$key] = .enabled_datasets[$key]) |
               .disabled_datasets[$key].auto_download = false |
               del(.enabled_datasets[$key]) |
               .last_update = $timestamp' \
               "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        else
            echo "❌ Dataset non trouvé dans enabled_datasets"
            exit 1
        fi
        
        if [ $? -eq 0 ]; then
            echo "✅ Dataset $DATASET_KEY désactivé"
        else
            echo "❌ Erreur lors de la désactivation"
            exit 1
        fi
        ;;
        
    "toggle-download")
        echo "🔧 Modification téléchargement: $DATASET_KEY (auto: $AUTO_DOWNLOAD)"
        
        # Modifier auto_download dans enabled_datasets, disabled_datasets ou discovered_datasets
        if jq -e ".enabled_datasets[\"$DATASET_KEY\"]" "$CONFIG_FILE" >/dev/null 2>&1; then
            # Dataset dans enabled_datasets
            jq --arg key "$DATASET_KEY" \
               --arg auto "$AUTO_DOWNLOAD" \
               --arg timestamp "$(date -Iseconds)" \
               '.enabled_datasets[$key].auto_download = ($auto == "true") |
               .last_update = $timestamp' \
               "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        elif jq -e ".disabled_datasets[\"$DATASET_KEY\"]" "$CONFIG_FILE" >/dev/null 2>&1; then
            # Dataset dans disabled_datasets
            jq --arg key "$DATASET_KEY" \
               --arg auto "$AUTO_DOWNLOAD" \
               --arg timestamp "$(date -Iseconds)" \
               '.disabled_datasets[$key].auto_download = ($auto == "true") |
               .last_update = $timestamp' \
               "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        elif jq -e ".discovered_datasets[\"$DATASET_KEY\"]" "$CONFIG_FILE" >/dev/null 2>&1; then
            # Dataset dans discovered_datasets
            jq --arg key "$DATASET_KEY" \
               --arg auto "$AUTO_DOWNLOAD" \
               --arg timestamp "$(date -Iseconds)" \
               '.discovered_datasets[$key].auto_download = ($auto == "true") |
               .last_update = $timestamp' \
               "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        else
            echo "❌ Dataset non trouvé"
            exit 1
        fi
        
        if [ $? -eq 0 ]; then
            echo "✅ Téléchargement $DATASET_KEY modifié (auto: $AUTO_DOWNLOAD)"
        else
            echo "❌ Erreur lors de la modification"
            exit 1
        fi
        ;;
        
    *)
        echo "❌ Action non reconnue: $ACTION"
        echo "Usage: $0 [enable|disable|toggle-download] SATELLITE SECTOR PRODUCT RESOLUTION [AUTO_DOWNLOAD]"
        exit 1
        ;;
esac
