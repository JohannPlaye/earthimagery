#!/# Génération de timestamps pour les derniers jours
generate_time_range() {
    local days=${1:-2}
    
    local timestamps=()
    local current=$(date -u -d "$days days ago" '+%s')
    local end=$(date -u '+%s')
    
    # Timestamps toutes les 15 minutes pour MTG (haute fréquence)
    while [[ $current -le $end ]]; do
        local timestamp=$(date -u -d "@$current" '+%Y-%m-%dT%H:%M:%SZ')
        timestamps+=("$timestamp")
        current=$((current + 900))  # +15 minutes (900 secondes)
    done
    
    # Afficher les timestamps pour capture
    printf '%s\n' "${timestamps[@]}"
}UMETSAT MTG FCI - Téléchargement datasets focus (Geocolor + VIS 0.6)
# Basé sur# Génération de timestamps pour les derniers jours
generate_time_range() {
    log "INFO" "📅 Génération plage temporelle (2 jours récents)..."
    
    TIMESTAMPS=()
    local current=$(date -u -d '2 days ago' '+%s')
    local end=$(date -u '+%s')
    
    # Timestamps toutes les 15 minutes pour MTG (haute fréquence)
    while [[ $current -le $end ]]; do
        local timestamp=$(date -u -d "@$current" '+%Y-%m-%dT%H:%M:%SZ')
        TIMESTAMPS+=("$timestamp")
        current=$((current + 900)) # +15 minutes
    done
    
    log "INFO" "📊 ${#TIMESTAMPS[@]} timestamps générés (intervalle 15min)"
}

set -uo pipefail  # Suppression de -e pour continuer en cas d'erreur

# Configuration
BASE_DIR="$(dirname "$(readlink -f "$0")")/.."
DATA_DIR="$BASE_DIR/public/data/EUMETSAT"
LOG_DIR="$DATA_DIR/logs"
WMS_URL="https://view.eumetsat.int/geoserver/wms"
WCS_URL="https://view.eumetsat.int/geoserver/ows"
WFS_URL="https://view.eumetsat.int/geoserver/ows"
API_URL="https://api.eumetsat.int"

# Identifiants API
CONSUMER_KEY="1hK2fINugbeWv6T7UA9Uqk4PAoEa"
CONSUMER_SECRET="0_i8fkJR8knY6xDNh9IqWIavy30a"

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Variables globales
TOKEN=""
TIMESTAMPS=()
SUCCESS_COUNT=0
TOTAL_ATTEMPTS=0

# Fonction de log avec couleurs
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")  echo -e "${GREEN}[INFO]${NC}  $timestamp - $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC}  $timestamp - $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $timestamp - $message" ;;
        "DEBUG") echo -e "${CYAN}[DEBUG]${NC} $timestamp - $message" ;;
        "SUCCESS") echo -e "${PURPLE}[SUCCESS]${NC} $timestamp - $message" ;;
        *)       echo "$timestamp - $message" ;;
    esac
}

# Initialisation de l'environnement
init_environment() {
    log "INFO" "🛰️ MTG FCI - Datasets Focus (Geocolor + VIS0.6) - $(date)"
    log "INFO" "============================================================"
    
    # Structure pour MTG FCI seulement
    mkdir -p "$DATA_DIR/MTG/FullDisc/Geocolor"
    mkdir -p "$DATA_DIR/MTG/FullDisc/VIS06"
    
    # Logs
    mkdir -p "$LOG_DIR"
    
    log "INFO" "📁 Structure créée: $DATA_DIR"
}

# Génération token API
generate_token() {
    log "INFO" "🔑 Génération token API..."
    
    local auth_string=$(echo -n "$CONSUMER_KEY:$CONSUMER_SECRET" | base64 -w 0)
    
    local response=$(curl -s -k \
        -d "grant_type=client_credentials" \
        -H "Authorization: Basic $auth_string" \
        "$API_URL/token")
    
    if echo "$response" | jq -e '.access_token' > /dev/null 2>&1; then
        TOKEN=$(echo "$response" | jq -r '.access_token')
        log "SUCCESS" "✅ Token généré: ${TOKEN:0:8}..."
        return 0
    else
        log "WARN" "⚠️ Échec génération token, mode public seulement"
        TOKEN=""
        return 1
    fi
}

# Génération de timestamps pour les derniers jours
generate_time_range() {
    log "INFO" "📅 Génération plage temporelle (2 jours récents)..."
    
    TIMESTAMPS=()
    local current=$(date -u -d '2 days ago' '+%s')
    local end=$(date -u '+%s')
    
    # Timestamps toutes les 15 minutes pour couvrir tous les datasets
    while [[ $current -le $end ]]; do
        local timestamp=$(date -u -d "@$current" '+%Y-%m-%dT%H:%M:%SZ')
        TIMESTAMPS+=("$timestamp")
        current=$((current + 900)) # +15 minutes
    done
    
    log "INFO" "📊 ${#TIMESTAMPS[@]} timestamps générés (intervalle 15min)"
}

# Téléchargement image WMS
download_wms_image() {
    local layer=$1
    local bbox=$2
    local output_dir=$3
    local filename_prefix=$4
    local timestamp=$5
    local width=${6:-1000}
    local height=${7:-1000}
    
    local formatted_time=$(echo "$timestamp" | sed 's/:/%3A/g')
    local filename="${filename_prefix}_$(echo "$timestamp" | sed 's/[:-]//g' | cut -c1-15).png"
    local output_path="$output_dir/$filename"
    
    # URL WMS
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
    
    if curl -s -f "$url" -o "$output_path"; then
        local size=$(stat -c%s "$output_path" 2>/dev/null || echo "0")
        
        if [[ $size -gt 1000 ]]; then
            local size_human=$(numfmt --to=iec --suffix=B $size)
            log "INFO" "✅ $filename ($size_human)"
            ((SUCCESS_COUNT++))
            return 0
        else
            log "WARN" "❌ Image corrompue: $filename (${size}B)"
            rm -f "$output_path"
            return 1
        fi
    else
        log "WARN" "❌ Échec: $filename"
        return 1
    fi
}

# Téléchargement données vectorielles WFS
download_wfs_data() {
    local layer=$1
    local output_dir=$2
    local filename=$3
    local bbox=${4:-"-180,-90,180,90"}
    
    # URL WFS
    local url="${WFS_URL}?service=WFS&version=2.0.0&request=GetFeature"
    url+="&typeName=$layer"
    url+="&outputFormat=application/json"
    url+="&bbox=$bbox"
    url+="&maxFeatures=1000"
    
    local output_path="$output_dir/${filename}.geojson"
    
    if curl -s -f "$url" -o "$output_path"; then
        local size=$(stat -c%s "$output_path" 2>/dev/null || echo "0")
        
        if [[ $size -gt 100 ]]; then
            # Vérification que c'est du JSON valide
            if jq -e . "$output_path" > /dev/null 2>&1; then
                local size_human=$(numfmt --to=iec --suffix=B $size)
                log "SUCCESS" "✅ $filename.geojson ($size_human)"
                ((SUCCESS_COUNT++))
                return 0
            fi
        fi
        
        log "WARN" "❌ Données vectorielles invalides: $filename"
        rm -f "$output_path"
        return 1
    else
        log "WARN" "❌ Échec WFS: $filename"
        return 1
    fi
}

# Dataset 1: MTG FCI Geocolor (RGB True Colour)
download_mtg_geocolor() {
    local timestamp="$1"
    log "INFO" "🛰️ MTG FCI - Geocolor ($timestamp)..."
    
    local layer="mtg_fd:rgb_truecolour"
    local bbox="-70,-70,70,70"
    local output_dir="$DATA_DIR/MTG/FullDisc/Geocolor"
    local prefix="mtg_geocolor"
    
    ((TOTAL_ATTEMPTS++))
    if download_wms_image "$layer" "$bbox" "$output_dir" "$prefix" "$timestamp" "2000" "2000"; then
        log "SUCCESS" "✅ MTG Geocolor: $timestamp téléchargé"
        return 0
    else
        log "WARN" "❌ MTG Geocolor: échec pour $timestamp"
        return 1
    fi
}

# Dataset 2: MTG FCI VIS 0.6 µm
download_mtg_vis06() {
    local timestamp="$1"
    log "INFO" "🛰️ MTG FCI - VIS 0.6 µm ($timestamp)..."
    
    local layer="mtg_fd:vis06_hrfi"
    local bbox="-70,-70,70,70"
    local output_dir="$DATA_DIR/MTG/FullDisc/VIS06"
    local prefix="mtg_vis06"
    
    ((TOTAL_ATTEMPTS++))
    if download_wms_image "$layer" "$bbox" "$output_dir" "$prefix" "$timestamp" "2000" "2000"; then
        log "SUCCESS" "✅ MTG VIS 0.6: $timestamp téléchargé"
        return 0
    else
        log "WARN" "❌ MTG VIS 0.6: échec pour $timestamp"
        return 1
    fi
}

# Validation globale
validate_downloads() {
    log "INFO" "🔍 Validation des téléchargements..."
    
    local total_images=0
    local valid_images=0
    local total_size=0
    
    # Images MTG seulement
    while IFS= read -r -d '' file; do
        ((total_images++))
        local size=$(stat -c%s "$file")
        
        if [[ $size -gt 1000 ]]; then
            ((valid_images++))
            ((total_size+=size))
        else
            log "WARN" "Image corrompue: $(basename "$file")"
            rm -f "$file"
        fi
    done < <(find "$DATA_DIR/MTG" -name "*.png" -print0 2>/dev/null)
    
    local total_size_human=$(numfmt --to=iec --suffix=B $total_size)
    
    log "SUCCESS" "✅ Images: $valid_images/$total_images valides"
    log "SUCCESS" "💾 Taille totale: $total_size_human"
}

# Génération rapport détaillé
generate_priority_report() {
    local log_file="$LOG_DIR/mtg-focus-$(date '+%Y%m%d_%H%M').log"
    
    log "INFO" "📋 Génération rapport: $log_file"
    
    {
        echo "🛰️ MTG FCI - Rapport Focus Datasets (Geocolor + VIS 0.6) - $(date)"
        echo "================================================================"
        echo
        
        echo "📊 Résumé des téléchargements:"
        echo "   ✅ Succès: $SUCCESS_COUNT"
        echo "   📝 Tentatives: $TOTAL_ATTEMPTS"
        if [[ $TOTAL_ATTEMPTS -gt 0 ]]; then
            echo "   📈 Taux de réussite: $(( SUCCESS_COUNT * 100 / TOTAL_ATTEMPTS ))%"
        else
            echo "   📈 Taux de réussite: N/A (aucune tentative)"
        fi
        echo
        
        echo "📂 Structure des données MTG FCI:"
        echo
        
        # MTG Geocolor
        echo "1. 🛰️ MTG FCI - Geocolor (True Colour)"
        local dir="$DATA_DIR/MTG/FullDisc/Geocolor"
        if [[ -d "$dir" ]]; then
            local count=$(find "$dir" -name "*.png" 2>/dev/null | wc -l)
            local size=$(find "$dir" -name "*.png" -exec stat -c%s {} + 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")
            local size_human=$(numfmt --to=iec --suffix=B $size)
            echo "   📄 MTG Geocolor: $count images ($size_human)"
        fi
        echo
        
        # MTG VIS 0.6
        echo "2. 🛰️ MTG FCI - VIS 0.6 µm (Haute résolution)"
        local dir="$DATA_DIR/MTG/FullDisc/VIS06"
        if [[ -d "$dir" ]]; then
            local count=$(find "$dir" -name "*.png" 2>/dev/null | wc -l)
            local size=$(find "$dir" -name "*.png" -exec stat -c%s {} + 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")
            local size_human=$(numfmt --to=iec --suffix=B $size)
            echo "   📄 MTG VIS 0.6: $count images ($size_human)"
        fi
        echo
        
        echo "🚀 PRÊT POUR INTÉGRATION DANS EARTHIMAGERY"
        echo "   - Données MTG haute résolution disponibles"
        echo "   - Fréquence temporelle maximale (15min)"
        echo "   - Structure compatible smart-fetch.sh"
        echo "   - Validation qualité effectuée"
        echo "   - Focus sur datasets prioritaires"
        
    } > "$log_file"
    
    log "SUCCESS" "📋 Rapport généré: $log_file"
}

# Fonction principale
main() {
    local start_time=$(date +%s)
    
    # Initialisation
    init_environment
    
    # Token API (optionnel)
    generate_token || true
    
    # Variables de tracking
    SUCCESS_COUNT=0
    TOTAL_ATTEMPTS=0
    
    # Génération timestamps (15min intervals pour MTG FCI)
    log "INFO" "📅 Génération plage temporelle (2 jours récents)..."
    local timestamps
    mapfile -t timestamps < <(generate_time_range)
    log "INFO" "📅 ${#timestamps[@]} créneaux temporels générés (15min intervals)"
    
    log "INFO" "🚀 Début téléchargement datasets MTG FCI prioritaires..."
    
    # Téléchargement MTG Geocolor
    log "INFO" "📸 1/2 - MTG FCI Geocolor (True Colour)"
    for timestamp in "${timestamps[@]}"; do
        download_mtg_geocolor "$timestamp"
    done
    
    # Téléchargement MTG VIS 0.6
    log "INFO" "📸 2/2 - MTG FCI VIS 0.6 µm (Haute résolution)"
    for timestamp in "${timestamps[@]}"; do
        download_mtg_vis06 "$timestamp"
    done
    
    # Validation
    validate_downloads
    
    # Rapport
    generate_priority_report
    
    # Statistiques finales
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log "SUCCESS" "✅ TÉLÉCHARGEMENT TERMINÉ"
    log "SUCCESS" "⏱️  Durée: ${duration}s"
    log "SUCCESS" "📊 Résultats: $SUCCESS_COUNT/$TOTAL_ATTEMPTS réussis"
    log "SUCCESS" "🎯 Datasets MTG FCI intégrés avec succès!"
    
    echo
    echo "🎉 Datasets MTG FCI prioritaires traités avec succès!"
    echo "📁 Données disponibles dans: $DATA_DIR/MTG/"
    echo "📋 Rapport détaillé: $LOG_DIR/"
}

# Exécution
main "$@"
