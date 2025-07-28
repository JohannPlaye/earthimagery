#!/bin/bash

# Script de récupération automatique des images satellitaires
# À exécuter via cron à intervalles réguliers

# Chargement des variables d'environnement
source "$(dirname "$0")/../.env.local"

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$DATA_ROOT_PATH/$LOGS_DIR/fetch-images-$(date +%Y%m%d).log"

# Création des dossiers si nécessaire
mkdir -p "$DATA_ROOT_PATH/$IMAGES_DIR"
mkdir -p "$DATA_ROOT_PATH/$LOGS_DIR"

# Fonction de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Fonction de téléchargement d'image
fetch_image() {
    local url="$1"
    local output_path="$2"
    local max_retries=3
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        if curl -s -o "$output_path" "$url"; then
            if [ -s "$output_path" ]; then
                log "✓ Image téléchargée: $output_path"
                return 0
            else
                log "⚠ Fichier vide: $output_path"
                rm -f "$output_path"
            fi
        else
            log "✗ Erreur de téléchargement: $url"
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            log "Retry $retry_count/$max_retries dans 5 secondes..."
            sleep 5
        fi
    done
    
    return 1
}

# Génération des chemins pour la date actuelle
CURRENT_DATE=$(date +%Y-%m-%d)
CURRENT_TIMESTAMP=$(date +%Y%m%d_%H%M)
DATE_DIR="$DATA_ROOT_PATH/$IMAGES_DIR/$CURRENT_DATE"

mkdir -p "$DATE_DIR"

log "Début de récupération des images pour $CURRENT_DATE"

# Lecture des sources d'images depuis le fichier de configuration
if [ -f "$PROJECT_ROOT/config/image-sources.json" ]; then
    # Exemple de traitement des URLs depuis JSON (nécessite jq)
    if command -v jq &> /dev/null; then
        jq -r '.sources[].url' "$PROJECT_ROOT/config/image-sources.json" | while read -r url_template; do
            # Remplacer les variables dans l'URL
            url=$(echo "$url_template" | sed "s/{date}/$CURRENT_DATE/g" | sed "s/{timestamp}/$CURRENT_TIMESTAMP/g")
            filename=$(basename "$url")
            output_path="$DATE_DIR/${CURRENT_TIMESTAMP}_${filename}"
            
            fetch_image "$url" "$output_path"
        done
    else
        log "⚠ jq non installé, utilisation des URLs par défaut"
    fi
else
    log "⚠ Fichier de configuration des sources non trouvé, utilisation des URLs par défaut"
    
    # URLs par défaut (exemples - à adapter selon vos sources)
    URLS=(
        "https://example.com/meteosat/latest.jpg"
        "https://example.com/goes/latest.jpg"
    )
    
    for url in "${URLS[@]}"; do
        filename=$(basename "$url")
        output_path="$DATE_DIR/${CURRENT_TIMESTAMP}_${filename}"
        fetch_image "$url" "$output_path"
    done
fi

# Nettoyage des images anciennes (garde 30 jours)
find "$DATA_ROOT_PATH/$IMAGES_DIR" -type d -name "20*" -mtime +30 -exec rm -rf {} \; 2>/dev/null

# Nettoyage des logs anciens (garde 7 jours)
find "$DATA_ROOT_PATH/$LOGS_DIR" -name "fetch-images-*.log" -mtime +7 -delete 2>/dev/null

log "Récupération terminée pour $CURRENT_DATE"
