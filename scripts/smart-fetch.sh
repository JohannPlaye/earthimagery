#!/bin/bash

# Script de téléchargement intelligent avec suivi des téléchargements
# Évite les téléchargements redondants et maintient un état de synchronisation

# Chargement des variables d'environnement
set -a  # Auto-export des variables
source "$(dirname "$0")/../.env.local"
set +a  # Désactiver l'auto-export

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TRACKING_FILE="$PROJECT_ROOT/config/download-tracking.json"
DATASETS_STATUS_FILE="$PROJECT_ROOT/config/datasets-status.json"
LOG_FILE="$DATA_ROOT_PATH/$LOGS_DIR/smart-fetch-$(date +%Y%m%d-%H%M%S).log"

# Création des dossiers si nécessaire
mkdir -p "$DATA_ROOT_PATH/$IMAGES_DIR"
mkdir -p "$DATA_ROOT_PATH/$LOGS_DIR"

# Fonction de logging
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" | tee -a "$LOG_FILE"
}

# Fonction de mise à jour du tracking
update_tracking() {
    local dataset_key="$1"
    local date="$2"
    local action="$3"  # "download" ou "video_generated"
    local status="$4"  # "success" ou "failed"
    local details="$5" # détails supplémentaires
    
    # Vérifier si jq est disponible
    if ! command -v jq &> /dev/null; then
        log "⚠️ jq non disponible, impossible de mettre à jour le tracking"
        return 1
    fi
    
    local timestamp=$(date -Iseconds)
    
    # Mise à jour du fichier de tracking
    local temp_file=$(mktemp)
    
    case "$action" in
        "download")
            jq --arg dataset "$dataset_key" \
               --arg date "$date" \
               --arg timestamp "$timestamp" \
               --arg status "$status" \
               --arg details "$details" \
               '.tracking[$dataset].daily_status[$date].download = {
                   "timestamp": $timestamp,
                   "status": $status,
                   "details": $details,
                   "images_count": ($details | tonumber? // 0)
               } |
               .tracking[$dataset].last_download = $timestamp |
               .tracking[$dataset].total_images_downloaded += ($details | tonumber? // 0) |
               .last_update = $timestamp' \
               "$TRACKING_FILE" > "$temp_file"
            ;;
        "video_generated")
            jq --arg dataset "$dataset_key" \
               --arg date "$date" \
               --arg timestamp "$timestamp" \
               --arg status "$status" \
               --arg details "$details" \
               '.tracking[$dataset].daily_status[$date].video = {
                   "timestamp": $timestamp,
                   "status": $status,
                   "details": $details
               } |
               .tracking[$dataset].last_video_generation = $timestamp |
               .tracking[$dataset].total_videos_generated += 1 |
               .last_update = $timestamp' \
               "$TRACKING_FILE" > "$temp_file"
            ;;
    esac
    
    mv "$temp_file" "$TRACKING_FILE"
}

# Fonction pour vérifier si un dataset/date a déjà été traité
is_already_processed() {
    local dataset_key="$1"
    local date="$2"
    local check_type="$3"  # "download" ou "video"
    
    if ! command -v jq &> /dev/null; then
        return 1  # Si pas de jq, on considère non traité
    fi
    
    local status=$(jq -r --arg dataset "$dataset_key" \
                          --arg date "$date" \
                          --arg type "$check_type" \
                          '.tracking[$dataset].daily_status[$date][$type].status // "missing"' \
                          "$TRACKING_FILE" 2>/dev/null)
    
    [ "$status" = "success" ]
}

# Fonction pour obtenir les datasets actifs
get_active_datasets() {
    if ! command -v jq &> /dev/null; then
        log "⚠️ jq non disponible, impossible de lire les datasets"
        return 1
    fi
    
    # Chercher auto_download: true dans toutes les sections (enabled, disabled, discovered)
    jq -r '[
        (.enabled_datasets // {} | to_entries[]),
        (.disabled_datasets // {} | to_entries[]),
        (.discovered_datasets // {} | to_entries[])
    ] | .[] | select(.value.auto_download == true) | .key' "$DATASETS_STATUS_FILE"
}

# Fonction pour télécharger les images d'un dataset pour une date
download_dataset_images() {
    local dataset_key="$1"
    local satellite="$2"
    local sector="$3"
    local product="$4"
    local resolution="$5"
    local target_date="$6"
    
    log "📥 Téléchargement: $dataset_key pour $target_date"
    
    # URL du listing NOAA (logique conditionnelle pour certains secteurs)
    local sector_upper=$(echo "$sector" | tr '[:lower:]' '[:upper:]')
    local listing_url=""
    if [[ "$sector_upper" == "CONUS" || "$sector_upper" == "FD" || "$sector_upper" == MESO* ]]; then
        listing_url="https://cdn.star.nesdis.noaa.gov/$satellite/ABI/$sector_upper/$product/"
    else
        listing_url="https://cdn.star.nesdis.noaa.gov/$satellite/ABI/SECTOR/$sector/$product/"
    fi
    log "📋 Récupération de la liste depuis $listing_url"
    
    # Récupérer tous les fichiers horodatés pour cette résolution
    local files=$(curl -L -s "$listing_url" | grep -o "href=\"[0-9]\{11\}_[^\"]*${resolution}\.jpg\"" | sed 's/href="//;s/"//')
    
    if [ -z "$files" ]; then
        log "❌ Aucun fichier trouvé pour $dataset_key"
        update_tracking "$dataset_key" "$target_date" "download" "failed" "0"
        return 1
    fi
    
    # Convertir la date cible en jour julien pour filtrer efficacement
    local target_year=$(echo "$target_date" | cut -d'-' -f1)
    local target_julian=$(date -d "$target_date" +%j)
    # Assurer que le jour julien a 3 chiffres (padding zero)
    target_julian=$(printf "%03d" "$target_julian")
    local target_prefix="${target_year}${target_julian}"
    
    # Filtrer les fichiers pour la date cible AVANT la boucle (optimisation majeure)
    local filtered_files=$(echo "$files" | grep "^${target_prefix}")
    
    if [ -z "$filtered_files" ]; then
        log "❌ Aucun fichier trouvé pour la date $target_date"
        update_tracking "$dataset_key" "$target_date" "download" "failed" "0"
        return 1
    fi
    
    local total_filtered=$(echo "$filtered_files" | wc -l)
    log "📊 $total_filtered fichiers trouvés pour $target_date"
    
    # Afficher un échantillon des fichiers correspondant à la date
    log "� Échantillon des fichiers NOAA pour $target_date :"
    echo "$filtered_files" | head -3 | while read -r f; do log "  - $f"; done
    
    # Filtrer par date cible et télécharger
    local downloaded_count=0
    local target_date_compact=$(echo "$target_date" | sed 's/-//g')
    
    # Utiliser un fichier temporaire pour préserver le compteur
    local temp_file=$(mktemp)
    echo "0" > "$temp_file"
    
    # Traitement ligne par ligne sans pipe pour préserver les variables
    while IFS= read -r filename; do
        if [ -n "$filename" ]; then
            # Parser le timestamp (on sait déjà que c'est la bonne date)
            local timestamp=$(echo "$filename" | grep -o "^[0-9]\{11\}")
            local time=$(echo "$timestamp" | cut -c8-11)
            local hour=$(echo "$time" | cut -c1-2)
            local minute=$(echo "$time" | cut -c3-4)
            
            # Créer le dossier de destination
            local output_dir="$DATA_ROOT_PATH/$satellite/$sector/$product/$resolution/$target_date"
            mkdir -p "$output_dir"
            
            # Nom de fichier de destination (format unifié)
            local parsed_time="${target_date}_${hour}${minute}"
            local output_file="$output_dir/${parsed_time}_${satellite}-${sector}-${product}.jpg"
            
            # Vérifier si déjà téléchargé
            if [ -f "$output_file" ]; then
                continue
            fi
            
            # URL complète
            local url="$listing_url$filename"
            
            # Télécharger l'image avec retry
            local max_retries=3
            local retry_count=0
            local success=false
            
            while [ $retry_count -lt $max_retries ] && [ "$success" = false ]; do
                if curl -L -s -f -o "$output_file" "$url" 2>/dev/null; then
                    if [ -s "$output_file" ]; then
                        log "  ✓ ${parsed_time}_${satellite}-${sector}-${product}.jpg (depuis $filename)"
                        # Incrémenter le compteur dans le fichier temporaire
                        local current_count=$(cat "$temp_file")
                        echo $((current_count + 1)) > "$temp_file"
                        success=true
                    else
                        log "  ⚠️ Fichier vide téléchargé: $output_file"
                        rm -f "$output_file"
                    fi
                else
                    log "  ⚠️ Échec curl pour: $url"
                fi
                
                if [ "$success" = false ]; then
                    retry_count=$((retry_count + 1))
                    if [ $retry_count -lt $max_retries ]; then
                        sleep 1
                    fi
                fi
            done
            
            if [ "$success" = false ]; then
                log "  ✗ Échec: ${parsed_time}_${satellite}-${sector}-${product}.jpg (depuis $filename)"
            fi
            
            # Petite pause pour éviter de surcharger le serveur
            sleep 0.2
        fi
    done <<< "$filtered_files"
    
    # Lire le compteur final depuis le fichier temporaire
    downloaded_count=$(cat "$temp_file")
    rm -f "$temp_file"
    
    # Mise à jour du tracking
    if [ $downloaded_count -gt 0 ]; then
        update_tracking "$dataset_key" "$target_date" "download" "success" "$downloaded_count"
        log "📊 Téléchargé: $downloaded_count images pour $dataset_key - $target_date"
    else
        # Vérifier si des fichiers existent déjà
        local existing_files=$(find "$DATA_ROOT_PATH/$satellite/$sector/$product/$resolution/$target_date" -name "*.jpg" 2>/dev/null | wc -l)
        if [ $existing_files -gt 0 ]; then
            update_tracking "$dataset_key" "$target_date" "download" "success" "$existing_files"
            log "📁 Images déjà présentes: $existing_files fichiers pour $dataset_key - $target_date"
        else
            update_tracking "$dataset_key" "$target_date" "download" "failed" "0"
            log "❌ Aucune image téléchargée pour $dataset_key - $target_date"
        fi
    fi
}
# Fonction pour traiter un dataset sur une plage de dates
process_dataset_range() {
    local dataset_key="$1"
    local start_date="$2"
    local end_date="$3"
    
    log "🎯 Traitement du dataset: $dataset_key ($start_date à $end_date)"
    
    # Extraire les composants du dataset
    IFS='.' read -r satellite sector product resolution <<< "$dataset_key"
    
    # Générer les dates à traiter
    local current_date="$start_date"
    while [[ "$current_date" != "$end_date" ]]; do
        download_dataset_images "$dataset_key" "$satellite" "$sector" "$product" "$resolution" "$current_date"
        current_date=$(date -d "$current_date + 1 day" +%Y-%m-%d)
    done
    
    # Traiter aussi la date de fin
    download_dataset_images "$dataset_key" "$satellite" "$sector" "$product" "$resolution" "$end_date"
}

# Fonction principale de synchronisation
sync_all_datasets() {
    local depth_days="${1:-10}"
    
    log "🔄 Début de synchronisation complète (profondeur: $depth_days jours, toutes les images disponibles)"
    
    # Calculer la plage de dates
    local end_date=$(date +%Y-%m-%d)
    local start_date=$(date -d "$end_date - $depth_days days" +%Y-%m-%d)
    
    log "📅 Plage de dates: $start_date à $end_date"
    
    # Obtenir les datasets actifs
    local datasets=($(get_active_datasets))
    
    if [ ${#datasets[@]} -eq 0 ]; then
        log "⚠️ Aucun dataset actif trouvé"
        return 1
    fi
    
    log "📦 Datasets actifs: ${datasets[*]}"
    
    # Traiter chaque dataset
    for dataset in "${datasets[@]}"; do
        process_dataset_range "$dataset" "$start_date" "$end_date"
    done
    
    log "✅ Synchronisation terminée"
}

# Traitement des arguments de ligne de commande
case "${1:-sync}" in
    "sync")
        sync_all_datasets "${2:-10}" "${3:-24}"
        ;;
    "dataset")
        if [ $# -lt 4 ]; then
            echo "Usage: $0 dataset DATASET_KEY START_DATE END_DATE"
            exit 1
        fi
        process_dataset_range "$2" "$3" "$4"
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [COMMAND] [OPTIONS]"
        echo ""
        echo "Commandes:"
        echo "  sync [DEPTH]                     Synchroniser tous les datasets actifs (toutes les images)"
        echo "  dataset KEY START END            Synchroniser un dataset spécifique (toutes les images)"
        echo "  help                             Afficher cette aide"
        echo ""
        echo "Exemples:"
        echo "  $0 sync 10                       # 10 jours, toutes les images disponibles"
        echo "  $0 dataset GOES18.hi.GEOCOLOR.600x600 2025-06-01 2025-07-29"
        ;;
    *)
        echo "Commande inconnue: $1"
        echo "Utilisez '$0 help' pour voir l'aide"
        exit 1
        ;;
esac
