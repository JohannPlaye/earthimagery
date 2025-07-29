#!/bin/bash

# Script de téléchargement unifié pour tous les datasets satellitaires
# Supporte différentes sources (NOAA, simulation, etc.) via configuration

# Chargement des variables d'environnement
source "$(dirname "$0")/../.env.local"

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TRACKING_FILE="$PROJECT_ROOT/config/download-tracking.json"
LOG_FILE="$DATA_ROOT_PATH/$LOGS_DIR/unified-download-$(date +%Y%m%d-%H%M).log"

# Création des dossiers si nécessaire
mkdir -p "$DATA_ROOT_PATH/$LOGS_DIR"

# Fonction de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Fonction pour convertir le jour julien en date
julian_to_date() {
    local year="$1"
    local julian_day="$2"
    
    date -d "$year-01-01 +$((julian_day - 1)) days" +%Y-%m-%d
}

# Fonction pour parser le timestamp NOAA
parse_noaa_timestamp() {
    local filename="$1"
    
    local timestamp=$(echo "$filename" | grep -o "^[0-9]\{11\}")
    local year=$(echo "$timestamp" | cut -c1-4)
    local julian_day=$(echo "$timestamp" | cut -c5-7)
    local time=$(echo "$timestamp" | cut -c8-11)
    local hour=$(echo "$time" | cut -c1-2)
    local minute=$(echo "$time" | cut -c3-4)
    
    local date=$(julian_to_date "$year" "$julian_day")
    echo "${date}_${hour}${minute}"
}

# Fonction de téléchargement avec gestion d'erreurs
fetch_image() {
    local url="$1"
    local output_path="$2"
    local max_retries=3
    local retry_count=0

    mkdir -p "$(dirname "$output_path")"

    while [ $retry_count -lt $max_retries ]; do
        if curl -s -f --connect-timeout 30 --max-time 60 -o "$output_path" "$url"; then
            if [ -s "$output_path" ]; then
                return 0
            else
                rm -f "$output_path"
            fi
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            sleep 2
        fi
    done
    
    return 1
}

# Fonction pour mettre à jour le tracking d'un jour
update_daily_tracking() {
    local dataset_key="$1"
    local date="$2"
    local status="$3"
    local count="$4"
    local details="$5"
    
    if [ ! -f "$TRACKING_FILE" ]; then
        log "❌ Fichier de tracking non trouvé: $TRACKING_FILE"
        return 1
    fi
    
    local timestamp=$(date -Iseconds)
    
    jq --arg key "$dataset_key" \
       --arg date "$date" \
       --arg status "$status" \
       --arg count "$count" \
       --arg details "$details" \
       --arg timestamp "$timestamp" \
       '.tracking[$key].daily_status[$date] = {
         "download": {
           "timestamp": $timestamp,
           "status": $status,
           "details": $details,
           "images_count": ($count | tonumber)
         }
       } |
       .tracking[$key].last_download = $timestamp |
       if $status == "success" then
         .tracking[$key].total_images_downloaded += ($count | tonumber)
       else . end |
       .last_update = $timestamp' \
       "$TRACKING_FILE" > "$TRACKING_FILE.tmp" && mv "$TRACKING_FILE.tmp" "$TRACKING_FILE"
}

# Fonction pour télécharger via NOAA
download_noaa_dataset() {
    local dataset_key="$1"
    local satellite="$2"
    local sector="$3"
    local product="$4"
    local resolution="$5"
    
    log "🛰️ Téléchargement NOAA: $dataset_key"
    
    # URL du listing NOAA
    local listing_url="https://cdn.star.nesdis.noaa.gov/$satellite/ABI/SECTOR/$sector/$product/"
    
    log "📋 Récupération de la liste depuis $listing_url"
    
    # Récupérer tous les fichiers horodatés pour cette résolution
    local files=$(curl -L -s "$listing_url" | grep -o "href=\"[0-9]\{11\}_[^\"]*${resolution}\.jpg\"" | sed 's/href="//;s/"//')
    
    if [ -z "$files" ]; then
        log "❌ Aucun fichier trouvé pour $dataset_key"
        return 1
    fi
    
    local total_files=$(echo "$files" | wc -l)
    log "📊 $total_files fichiers disponibles"
    
    # Grouper par jour et télécharger
    declare -A daily_counts
    local total_downloaded=0
    
    echo "$files" | while read filename; do
        if [ -n "$filename" ]; then
            # Parser le timestamp et extraire la date
            local parsed=$(parse_noaa_timestamp "$filename")
            local date=$(echo "$parsed" | cut -d'_' -f1)
            local time=$(echo "$parsed" | cut -d'_' -f2)
            
            # Chemin de destination
            local output_dir="$DATA_ROOT_PATH/$satellite/$sector/$product/$resolution/$date"
            local output_file="$output_dir/${parsed}_${satellite}-${sector}-${product}.jpg"
            
            # Vérifier si l'image existe déjà
            if [ -f "$output_file" ]; then
                daily_counts["$date"]=$((${daily_counts["$date"]:-0} + 1))
                continue
            fi
            
            # URL complète
            local url="$listing_url$filename"
            
            # Télécharger l'image
            if fetch_image "$url" "$output_file"; then
                daily_counts["$date"]=$((${daily_counts["$date"]:-0} + 1))
                total_downloaded=$((total_downloaded + 1))
                log "  ✓ ${date}_${time}"
            else
                log "  ❌ Échec: ${date}_${time}"
            fi
            
            # Petite pause pour éviter de surcharger le serveur
            sleep 0.3
        fi
    done
    
    # Mettre à jour le tracking pour chaque jour
    for date in "${!daily_counts[@]}"; do
        local count=${daily_counts["$date"]}
        update_daily_tracking "$dataset_key" "$date" "success" "$count" "NOAA historical data"
        log "📅 $date: $count images"
    done
    
    log "🎯 Téléchargement NOAA terminé: $total_downloaded nouvelles images"
}

# Fonction pour télécharger un dataset
download_dataset() {
    local dataset_key="$1"
    
    # Lecture de la configuration du dataset depuis le tracking
    local satellite=$(jq -r ".tracking[\"$dataset_key\"].dataset_info.satellite" "$TRACKING_FILE")
    local sector=$(jq -r ".tracking[\"$dataset_key\"].dataset_info.sector" "$TRACKING_FILE")
    local product=$(jq -r ".tracking[\"$dataset_key\"].dataset_info.product" "$TRACKING_FILE")
    local resolution=$(jq -r ".tracking[\"$dataset_key\"].dataset_info.resolution" "$TRACKING_FILE")
    local enabled=$(jq -r ".tracking[\"$dataset_key\"].dataset_info.enabled" "$TRACKING_FILE")
    
    if [ "$enabled" != "true" ]; then
        log "⏸️ Dataset $dataset_key désactivé"
        return
    fi
    
    # Déterminer la source selon le satellite
    case "$satellite" in
        "GOES16"|"GOES17"|"GOES18")
            download_noaa_dataset "$dataset_key" "$satellite" "$sector" "$product" "$resolution"
            ;;
        *)
            log "❌ Source non supportée pour satellite: $satellite"
            ;;
    esac
}

# Fonction pour synchroniser tous les datasets activés
sync_all_datasets() {
    log "🔄 Synchronisation de tous les datasets activés"
    
    # Lecture des datasets activés
    local datasets=$(jq -r '.tracking | to_entries[] | select(.value.dataset_info.enabled == true) | .key' "$TRACKING_FILE")
    
    if [ -z "$datasets" ]; then
        log "⚠️ Aucun dataset activé trouvé"
        return 0
    fi
    
    local dataset_count=$(echo "$datasets" | wc -l)
    log "📋 Datasets à traiter: $dataset_count"
    
    # Traitement de chaque dataset
    while IFS= read -r dataset_key; do
        download_dataset "$dataset_key"
        
        if [ $dataset_count -gt 1 ]; then
            log "⏸️ Pause de 5 secondes entre les datasets..."
            sleep 5
        fi
    done <<< "$datasets"
    
    log "✅ Synchronisation terminée"
}

# Fonction d'aide
show_help() {
    echo "Script de téléchargement unifié pour datasets satellitaires"
    echo ""
    echo "Usage:"
    echo "  $0 [COMMANDE] [OPTIONS]"
    echo ""
    echo "Commandes:"
    echo "  sync                    - Synchroniser tous les datasets activés"
    echo "  download DATASET_KEY    - Télécharger un dataset spécifique"
    echo "  list                    - Lister les datasets disponibles"
    echo "  status                  - Afficher le statut des téléchargements"
    echo "  help                    - Afficher cette aide"
    echo ""
    echo "Exemples:"
    echo "  $0 sync"
    echo "  $0 download GOES18.hi.GEOCOLOR.600x600"
    echo "  $0 list"
}

# Script principal
main() {
    local command="${1:-sync}"
    
    case "$command" in
        "sync")
            log "🚀 Démarrage de la synchronisation unifiée"
            sync_all_datasets
            ;;
        "download")
            local dataset_key="$2"
            if [ -z "$dataset_key" ]; then
                echo "❌ Erreur: Dataset key requis"
                echo "Usage: $0 download DATASET_KEY"
                exit 1
            fi
            log "🚀 Téléchargement du dataset: $dataset_key"
            download_dataset "$dataset_key"
            ;;
        "list")
            if [ -f "$TRACKING_FILE" ]; then
                echo "📋 Datasets disponibles:"
                jq -r '.tracking | to_entries[] | "  \(.key) - \(.value.dataset_info.satellite)/\(.value.dataset_info.sector)/\(.value.dataset_info.product) (\(.value.dataset_info.enabled // false | if . then "activé" else "désactivé" end))"' "$TRACKING_FILE"
            else
                echo "❌ Fichier de tracking non trouvé"
            fi
            ;;
        "status")
            if [ -f "$TRACKING_FILE" ]; then
                echo "📊 Statut des téléchargements:"
                jq -r '.tracking | to_entries[] | "  \(.key): \(.value.total_images_downloaded // 0) images téléchargées"' "$TRACKING_FILE"
            else
                echo "❌ Fichier de tracking non trouvé"
            fi
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            echo "❌ Commande inconnue: $command"
            show_help
            exit 1
            ;;
    esac
}

# Vérification des dépendances
if ! command -v jq &> /dev/null; then
    echo "❌ jq est requis pour ce script"
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo "❌ curl est requis pour ce script"
    exit 1
fi

# Vérification du fichier de tracking
if [ ! -f "$TRACKING_FILE" ] && [ "$1" != "help" ] && [ "$1" != "-h" ] && [ "$1" != "--help" ]; then
    echo "❌ Fichier de tracking non trouvé: $TRACKING_FILE"
    exit 1
fi

# Lancement du script principal
main "$@"
