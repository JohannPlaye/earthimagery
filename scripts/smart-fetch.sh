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

# Fonction pour construire le chemin de données satellite avec structure NOAA/EUMETSAT
build_satellite_data_path() {
    local satellite="$1"
    local sector="$2"
    local product="$3"
    local resolution="$4"
    local date="$5"
    
    # Récupérer la source du dataset depuis la configuration
    local dataset_key="$satellite.$sector.$product.$resolution"
    local source=$(jq -r ".enabled_datasets[\"$dataset_key\"].source // \"UNKNOWN\"" "$DATASETS_STATUS_FILE" 2>/dev/null)
    
    case "$source" in
        "NOAA")
            # Structure NOAA: NOAA/satellite/sector/product/resolution/date
            echo "$DATA_ROOT_PATH/NOAA/$satellite/$sector/$product/$resolution/$date"
            ;;
        "EUMETSAT")
            # Structure EUMETSAT: EUMETSAT/satellite/sector/product/date
            echo "$DATA_ROOT_PATH/EUMETSAT/$satellite/$sector/$product/$date"
            ;;
        *)
            # Fallback vers structure NOAA pour satellites GOES (rétrocompatibilité)
            if [[ "$satellite" =~ ^GOES[0-9]+$ ]]; then
                echo "$DATA_ROOT_PATH/NOAA/$satellite/$sector/$product/$resolution/$date"
            else
                # Autres satellites gardent la structure actuelle
                echo "$DATA_ROOT_PATH/$satellite/$sector/$product/$resolution/$date"
            fi
            ;;
    esac
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
            local output_dir=$(build_satellite_data_path "$satellite" "$sector" "$product" "$resolution" "$target_date")
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

# Fonction pour télécharger les images EUMETSAT pour une date
download_eumetsat_images() {
    local dataset_key="$1"
    local satellite="$2"
    local sector="$3"
    local product="$4"
    local resolution="$5"
    local target_date="$6"
    
    log "📥 Téléchargement EUMETSAT: $dataset_key pour $target_date"
    
    # Générer le token EUMETSAT
    local token=""
    if [[ -n "$EUMETSAT_CONSUMER_KEY" && -n "$EUMETSAT_CONSUMER_SECRET" ]]; then
        log "🔑 Génération token EUMETSAT..."
        local token_response=$(curl -s -X POST \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=client_credentials" \
            -u "$EUMETSAT_CONSUMER_KEY:$EUMETSAT_CONSUMER_SECRET" \
            "$EUMETSAT_API_URL/token")
        
        if [[ -n "$token_response" ]] && echo "$token_response" | grep -q "access_token"; then
            token=$(echo "$token_response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
            log "✅ Token EUMETSAT généré"
        else
            log "⚠️ Échec génération token, tentative en mode public"
        fi
    fi
    
    # Vérifier les variables de base
    if [ -z "$EUMETSAT_BASE_URL" ]; then
        log "❌ Variable EUMETSAT_BASE_URL manquante"
        update_tracking "$dataset_key" "$target_date" "download" "failed" "Configuration incomplète"
        return 1
    fi
    
    # Configuration spécifique selon le produit
    local layer=""
    local bbox=""
    local width=2000
    local height=2000
    
    case "$product" in
        "Geocolor")
            layer="mtg_fd:rgb_geocolour"
            bbox="-80,-60,80,80"  # Europe/Afrique
            ;;
        "VIS06")
            layer="mtg_fd:vis06_hrfi"
            bbox="-80,-60,80,80"
            ;;
        *)
            log "❌ Produit EUMETSAT non supporté: $product"
            update_tracking "$dataset_key" "$target_date" "download" "failed" "Produit non supporté"
            return 1
            ;;
    esac
    
    # Créer le dossier de destination
    local output_dir=$(build_satellite_data_path "$satellite" "$sector" "$product" "$resolution" "$target_date")
    mkdir -p "$output_dir"
    
    # Générer les timestamps pour la journée (toutes les 15 minutes)
    local downloaded_count=0
    local temp_file=$(mktemp)
    echo "0" > "$temp_file"
    
    # Calculer l'heure limite : 1h avant l'heure actuelle UTC (équivaut à 3h en heure locale UTC+2)
    local current_utc_time=$(date -u +%s)
    local cutoff_time=$((current_utc_time - 1 * 3600))  # 1 heure = 1 * 3600 secondes
    local cutoff_timestamp=$(date -u -d "@$cutoff_time" +%Y-%m-%dT%H:%M:%SZ)
    
    # Commencer à minuit de la date cible
    local start_timestamp="${target_date}T00:00:00Z"
    local start_time=$(date -d "$start_timestamp" +%s)
    
    # Déterminer l'heure de fin : soit 23:45 de la date cible, soit l'heure limite (le plus petit)
    local end_of_day_timestamp="${target_date}T23:45:00Z"
    local end_of_day_time=$(date -d "$end_of_day_timestamp" +%s)
    local effective_end_time=$((end_of_day_time < cutoff_time ? end_of_day_time : cutoff_time))
    
    log "📋 Images EUMETSAT de $start_timestamp jusqu'à $(date -u -d "@$effective_end_time" +%Y-%m-%dT%H:%M:%SZ) (limite -1h UTC)"
    
    # Si l'heure de fin effective est avant le début de la journée, pas d'images à télécharger
    if [ $effective_end_time -lt $start_time ]; then
        log "⏰ Aucune image à télécharger - toutes les heures sont dans la 1h future"
        update_tracking "$dataset_key" "$target_date" "download" "success" "0"
        return 0
    fi
    
    # Générer toutes les 15 minutes jusqu'à l'heure limite
    local current_time=$start_time
    local interval_seconds=$((15 * 60))  # 15 minutes
    
    while [ $current_time -le $effective_end_time ]; do
        
        local timestamp=$(date -d "@$current_time" -u +%Y-%m-%dT%H:%M:%SZ)
        local filename_prefix="mtg_$(echo "$product" | tr '[:upper:]' '[:lower:]')"
        local filename="${filename_prefix}_$(echo "$timestamp" | sed 's/[:-]//g' | cut -c1-15).png"
        local output_path="$output_dir/$filename"
        
        # Vérifier si déjà téléchargé
        if [ -f "$output_path" ]; then
            current_time=$((current_time + interval_seconds))
            continue
        fi
        
        # Construction URL WMS EUMETSAT
        local formatted_time=$(echo "$timestamp" | sed 's/:/%3A/g')
        local wms_url="${EUMETSAT_BASE_URL}?service=WMS&version=1.3.0&request=GetMap"
        wms_url+="&layers=$layer"
        wms_url+="&styles="
        wms_url+="&format=image/png"
        wms_url+="&transparent=true"
        wms_url+="&width=$width"
        wms_url+="&height=$height"
        wms_url+="&crs=EPSG:4326"
        wms_url+="&bbox=$bbox"
        wms_url+="&time=$formatted_time"
        if [[ -n "$token" ]]; then
            wms_url+="&access_token=$token"
        fi
        
        # Télécharger avec retry
        local max_retries=3
        local retry_count=0
        local success=false
        
        while [ $retry_count -lt $max_retries ] && [ "$success" = false ]; do
            if curl -s -f "$wms_url" -o "$output_path" 2>/dev/null; then
                if [ -s "$output_path" ]; then
                    log "  ✓ $filename"
                    echo $(($(cat "$temp_file") + 1)) > "$temp_file"
                    success=true
                else
                    log "  ⚠️ Fichier vide téléchargé: $filename"
                    rm -f "$output_path"
                fi
            else
                log "  ⚠️ Échec curl EUMETSAT pour: $timestamp"
            fi
            
            if [ "$success" = false ]; then
                retry_count=$((retry_count + 1))
                if [ $retry_count -lt $max_retries ]; then
                    sleep 2
                fi
            fi
        done
        
        if [ "$success" = false ]; then
            log "  ✗ Échec: $filename"
        fi
        
        # Pause pour éviter la surcharge
        sleep 0.5
        current_time=$((current_time + interval_seconds))
    done
    
    # Lire le compteur final
    downloaded_count=$(cat "$temp_file")
    rm -f "$temp_file"
    
    # Mise à jour du tracking
    if [ $downloaded_count -gt 0 ]; then
        update_tracking "$dataset_key" "$target_date" "download" "success" "$downloaded_count"
        log "📊 Téléchargé EUMETSAT: $downloaded_count images pour $dataset_key - $target_date"
    else
        # Vérifier si des fichiers existent déjà
        local existing_files=$(find "$output_dir" -name "*.png" 2>/dev/null | wc -l)
        if [ $existing_files -gt 0 ]; then
            update_tracking "$dataset_key" "$target_date" "download" "success" "$existing_files"
            log "📁 Images EUMETSAT déjà présentes: $existing_files fichiers pour $dataset_key - $target_date"
        else
            update_tracking "$dataset_key" "$target_date" "download" "failed" "0"
            log "❌ Aucune image EUMETSAT téléchargée pour $dataset_key - $target_date"
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
    
    # Déterminer la source du dataset
    local source=$(jq -r ".enabled_datasets[\"$dataset_key\"].source // \"UNKNOWN\"" "$DATASETS_STATUS_FILE" 2>/dev/null)
    
    # Générer les dates à traiter
    local current_date="$start_date"
    while [[ "$current_date" != "$end_date" ]]; do
        case "$source" in
            "NOAA")
                download_dataset_images "$dataset_key" "$satellite" "$sector" "$product" "$resolution" "$current_date"
                ;;
            "EUMETSAT")
                download_eumetsat_images "$dataset_key" "$satellite" "$sector" "$product" "$resolution" "$current_date"
                ;;
            *)
                log "⚠️ Source inconnue '$source' pour $dataset_key, utilisation de NOAA par défaut"
                download_dataset_images "$dataset_key" "$satellite" "$sector" "$product" "$resolution" "$current_date"
                ;;
        esac
        current_date=$(date -d "$current_date + 1 day" +%Y-%m-%d)
    done
    
    # Traiter aussi la date de fin
    case "$source" in
        "NOAA")
            download_dataset_images "$dataset_key" "$satellite" "$sector" "$product" "$resolution" "$end_date"
            ;;
        "EUMETSAT")
            download_eumetsat_images "$dataset_key" "$satellite" "$sector" "$product" "$resolution" "$end_date"
            ;;
        *)
            log "⚠️ Source inconnue '$source' pour $dataset_key, utilisation de NOAA par défaut"
            download_dataset_images "$dataset_key" "$satellite" "$sector" "$product" "$resolution" "$end_date"
            ;;
    esac
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
