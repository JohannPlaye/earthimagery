#!/bin/bash

# =============================================================================
# EUMETSAT-DOWNLOAD.SH - Téléchargement intelligent des données EUMETSAT
# =============================================================================
# Ce script télécharge les données EUMETSAT de manière intelligente :
# - Respecte les plages de dates demandées
# - Évite de re-télécharger les données existantes
# - S'intègre avec testcomplet.sh et la logique NOAA
# - Supporte plusieurs datasets EUMETSAT
#
# Usage: 
#   ./eumetsat-download.sh dataset MTG.FullDisc.Geocolor.2000x2000 2025-08-19 2025-08-20
#   ./eumetsat-download.sh all 2025-08-19 2025-08-20
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_ROOT/public/data/EUMETSAT"
CONFIG_DIR="$PROJECT_ROOT/config"
LOG_DIR="$DATA_DIR/logs"

# Variables API EUMETSAT
WMS_URL="https://wms.eumetsat.int/eumetview-service/1.0.0/wms"
AUTH_URL="https://api.eumetsat.int/token"
CONSUMER_KEY="H9eGKf8xGR5gGqE2uAq5RkR5Zj8a"
CONSUMER_SECRET="MtdMCOZgHh77YlhqLJjj0ILIcrka"

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Compteurs globaux
TOTAL_ATTEMPTS=0
SUCCESS_COUNT=0
SKIP_COUNT=0

# =============================================================================
# FONCTIONS UTILITAIRES
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $timestamp - $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $timestamp - $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $timestamp - $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $timestamp - $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $timestamp - $message" ;;
    esac
}

# Fonction pour obtenir un token API
get_api_token() {
    local response=$(curl -s -X POST "$AUTH_URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials" \
        --user "$CONSUMER_KEY:$CONSUMER_SECRET")
    
    if [[ $? -eq 0 ]]; then
        echo "$response" | jq -r '.access_token // empty'
    else
        echo ""
    fi
}

# Fonction pour construire le chemin de sortie selon le dataset
build_dataset_path() {
    local dataset_key="$1"
    local date="$2"
    
    # Parse dataset: MTG.FullDisc.Geocolor.2000x2000 -> MTG/FullDisc/Geocolor/date
    IFS='.' read -ra PARTS <<< "$dataset_key"
    if [ ${#PARTS[@]} -eq 4 ]; then
        local satellite="${PARTS[0]}"
        local sector="${PARTS[1]}"
        local product="${PARTS[2]}"
        # Note: résolution ignorée pour EUMETSAT (contrairement à NOAA)
        echo "$DATA_DIR/$satellite/$sector/$product/$date"
    else
        echo ""
    fi
}

# Fonction pour mapper dataset vers layer WMS
map_dataset_to_layer() {
    local dataset_key="$1"
    
    case "$dataset_key" in
        "MTG.FullDisc.Geocolor.2000x2000")
            echo "meteosat.msg.channel.eumetview.fci.truecolour"
            ;;
        "MTG.FullDisc.VIS06.2000x2000")
            echo "meteosat.msg.channel.eumetview.fci.vis_0_6"
            ;;
        *)
            log "ERROR" "Dataset EUMETSAT non supporté: $dataset_key"
            return 1
            ;;
    esac
}

# Fonction pour télécharger une image WMS
download_wms_image() {
    local layer="$1"
    local bbox="$2"
    local output_dir="$3"
    local filename_prefix="$4"
    local timestamp="$5"
    local token="$6"
    local width="${7:-2000}"
    local height="${8:-2000}"
    
    # Créer le répertoire de sortie
    mkdir -p "$output_dir"
    
    local formatted_time=$(echo "$timestamp" | sed 's/:/%3A/g')
    local filename="${filename_prefix}_$(echo "$timestamp" | sed 's/[:-]//g' | cut -c1-15).png"
    local output_path="$output_dir/$filename"
    
    # Vérifier si le fichier existe déjà
    if [[ -f "$output_path" ]]; then
        log "DEBUG" "⏩ $filename déjà téléchargé"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        return 0
    fi
    
    # Construction URL WMS
    local url="${WMS_URL}?service=WMS&version=1.3.0&request=GetMap"
    url+="&layers=$layer"
    url+="&styles="
    url+="&format=image/png"
    url+="&transparent=true"
    url+="&width=$width"
    url+="&height=$height"
    url+="&crs=EPSG:4326"
    url+="&bbox=$bbox"
    url+="&time=$formatted_time"
    url+="&access_token=$token"
    
    TOTAL_ATTEMPTS=$((TOTAL_ATTEMPTS + 1))
    
    if curl -s -f "$url" -o "$output_path"; then
        local size=$(du -h "$output_path" | cut -f1)
        log "INFO" "✅ $filename ($size)"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        return 0
    else
        log "WARN" "❌ Échec téléchargement: $filename"
        rm -f "$output_path"
        return 1
    fi
}

# Fonction pour générer les timestamps d'une journée
generate_daily_timestamps() {
    local date="$1"
    local interval_minutes="${2:-15}"  # Par défaut 15 minutes
    
    local timestamps=()
    
    # Générer les créneaux de 00:00 à 23:59
    for hour in {0..23}; do
        for minute in $(seq 0 $interval_minutes $((60 - interval_minutes))); do
            printf -v timestamp "%s-%02d:%02dT%02d:%02d:00Z" \
                "$date" \
                $(echo "$date" | cut -d'-' -f2) \
                $(echo "$date" | cut -d'-' -f3) \
                "$hour" \
                "$minute"
            timestamps+=("$timestamp")
        done
    done
    
    printf '%s\n' "${timestamps[@]}"
}

# Fonction pour télécharger un dataset pour une date
download_dataset_for_date() {
    local dataset_key="$1"
    local date="$2"
    local token="$3"
    
    log "INFO" "📥 Téléchargement $dataset_key pour $date"
    
    # Obtenir le layer WMS
    local layer=$(map_dataset_to_layer "$dataset_key")
    if [[ -z "$layer" ]]; then
        return 1
    fi
    
    # Construire le chemin de sortie
    local output_dir=$(build_dataset_path "$dataset_key" "$date")
    if [[ -z "$output_dir" ]]; then
        log "ERROR" "Impossible de construire le chemin pour $dataset_key"
        return 1
    fi
    
    # Paramètres selon le dataset
    local bbox filename_prefix
    case "$dataset_key" in
        "MTG.FullDisc.Geocolor.2000x2000")
            bbox="-80,-80,80,80"  # Disque complet
            filename_prefix="mtg_geocolor"
            ;;
        "MTG.FullDisc.VIS06.2000x2000")
            bbox="-80,-80,80,80"
            filename_prefix="mtg_vis06"
            ;;
        *)
            log "ERROR" "Configuration manquante pour $dataset_key"
            return 1
            ;;
    esac
    
    # Vérifier si on a déjà des images pour cette date
    local existing_count=$(find "$output_dir" -name "${filename_prefix}_*.png" 2>/dev/null | wc -l)
    log "DEBUG" "Images existantes pour $date: $existing_count"
    
    # Générer les timestamps pour cette date
    local timestamps=($(generate_daily_timestamps "$date"))
    local before_count=$SUCCESS_COUNT
    
    # Télécharger les images manquantes
    for timestamp in "${timestamps[@]}"; do
        download_wms_image "$layer" "$bbox" "$output_dir" "$filename_prefix" "$timestamp" "$token"
    done
    
    local downloaded_count=$((SUCCESS_COUNT - before_count))
    log "INFO" "📊 $dataset_key - $date: $downloaded_count nouvelles images téléchargées"
}

# =============================================================================
# FONCTION PRINCIPALE
# =============================================================================

main() {
    echo ""
    echo "🛰️ EUMETSAT Download - Téléchargement intelligent"
    echo "================================================="
    echo ""
    
    # Vérification des paramètres
    if [[ $# -lt 3 ]]; then
        echo "Usage: $0 <mode> <start_date> <end_date> [dataset_key]"
        echo ""
        echo "Modes:"
        echo "  dataset <dataset_key> <start> <end>  - Télécharger un dataset spécifique"
        echo "  all <start> <end>                    - Télécharger tous les datasets actifs"
        echo ""
        echo "Exemples:"
        echo "  $0 dataset MTG.FullDisc.Geocolor.2000x2000 2025-08-19 2025-08-20"
        echo "  $0 all 2025-08-19 2025-08-20"
        exit 1
    fi
    
    local mode="$1"
    
    if [[ "$mode" == "dataset" ]]; then
        if [[ $# -ne 4 ]]; then
            log "ERROR" "Mode dataset nécessite: dataset <dataset_key> <start_date> <end_date>"
            exit 1
        fi
        local dataset_key="$2"
        local start_date="$3"
        local end_date="$4"
        local datasets=("$dataset_key")
    elif [[ "$mode" == "all" ]]; then
        if [[ $# -ne 3 ]]; then
            log "ERROR" "Mode all nécessite: all <start_date> <end_date>"
            exit 1
        fi
        local start_date="$2"
        local end_date="$3"
        # Récupérer tous les datasets EUMETSAT actifs
        local datasets=($(jq -r '[.enabled_datasets // {} | to_entries[]] | .[] | select(.value.auto_download == true and .value.source == "EUMETSAT") | .key' "$CONFIG_DIR/datasets-status.json" 2>/dev/null || echo ""))
        if [[ ${#datasets[@]} -eq 0 ]]; then
            log "WARN" "Aucun dataset EUMETSAT actif trouvé"
            exit 0
        fi
    else
        log "ERROR" "Mode non reconnu: $mode"
        exit 1
    fi
    
    # Créer les répertoires
    mkdir -p "$DATA_DIR" "$LOG_DIR"
    
    # Obtenir le token API
    log "INFO" "🔑 Génération token API EUMETSAT..."
    local token=$(get_api_token)
    if [[ -z "$token" ]]; then
        log "ERROR" "Impossible d'obtenir le token API"
        exit 1
    fi
    log "SUCCESS" "✅ Token obtenu: ${token:0:8}..."
    
    # Générer la liste des dates
    local dates=()
    local current_date="$start_date"
    while [[ "$current_date" <= "$end_date" ]]; do
        dates+=("$current_date")
        current_date=$(date -d "$current_date + 1 day" +%Y-%m-%d)
    done
    
    log "INFO" "📅 Période: $start_date à $end_date (${#dates[@]} jour(s))"
    log "INFO" "📊 Datasets: ${datasets[*]}"
    
    # Télécharger pour chaque dataset et chaque date
    for dataset_key in "${datasets[@]}"; do
        log "INFO" "🎯 Traitement du dataset: $dataset_key"
        for date in "${dates[@]}"; do
            download_dataset_for_date "$dataset_key" "$date" "$token"
        done
    done
    
    # Rapport final
    echo ""
    echo "📊 Résumé du téléchargement:"
    echo "   ✅ Succès: $SUCCESS_COUNT"
    echo "   ⏩ Ignorés (déjà présents): $SKIP_COUNT"
    echo "   📝 Tentatives totales: $TOTAL_ATTEMPTS"
    if [[ $TOTAL_ATTEMPTS -gt 0 ]]; then
        echo "   📈 Taux de réussite: $(( SUCCESS_COUNT * 100 / TOTAL_ATTEMPTS ))%"
    fi
    echo ""
    
    if [[ $SUCCESS_COUNT -gt 0 ]]; then
        log "SUCCESS" "✅ Téléchargement terminé avec succès"
    else
        log "INFO" "ℹ️ Aucune nouvelle image téléchargée"
    fi
}

# =============================================================================
# POINT D'ENTRÉE
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
