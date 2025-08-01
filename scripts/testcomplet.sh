    local datasets=($(jq -r '[.enabled_datasets // {} | to_entries[]] | .[] | select(.value.auto_download == true) | .key' "$CONFIG_DIR/datasets-status.json"))
#!/bin/bash

# =============================================================================
# TESTCOMPLET.SH - Test de bout en bout pour EarthImagery
# =============================================================================
# Ce script effectue un test complet du pipeline EarthImagery :
# 1. Nettoyage de toutes les données existantes
# 2. Téléchargement de 10 jours de données pour les datasets actifs
# 3. Génération des fragments vidéo journaliers
# 4. Création des playlists HLS
#
# Usage: ./testcomplet.sh
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_ROOT/public/data"
CONFIG_DIR="$PROJECT_ROOT/config"
TRACKING_FILE="$CONFIG_DIR/download-tracking.json"
LOG_FILE="$DATA_DIR/logs/testcomplet-$(date +%Y%m%d-%H%M%S).log"

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# FONCTIONS UTILITAIRES
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $timestamp - $message" | tee -a "$LOG_FILE" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $timestamp - $message" | tee -a "$LOG_FILE" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $timestamp - $message" | tee -a "$LOG_FILE" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $timestamp - $message" | tee -a "$LOG_FILE" ;;
    esac
}

create_directories() {
    log "INFO" "Création des répertoires nécessaires..."
    mkdir -p "$DATA_DIR/logs"
    mkdir -p "$DATA_DIR/images"
    mkdir -p "$DATA_DIR/hls"
    mkdir -p "$CONFIG_DIR"
}

check_dependencies() {
    log "INFO" "Vérification des dépendances..."
    
    local missing_deps=()
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if ! command -v ffmpeg &> /dev/null; then
        missing_deps+=("ffmpeg")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log "ERROR" "Dépendances manquantes: ${missing_deps[*]}"
        log "ERROR" "Veuillez installer: sudo apt install ${missing_deps[*]}"
        exit 1
    fi
    
    log "INFO" "Toutes les dépendances sont présentes"
}

# =============================================================================
# PHASE 1: DÉTECTION DES JOURS À TRAITER
# =============================================================================

detect_days_to_process() {
    log "INFO" "🔎 PHASE 1: Détection des jours à traiter (fragments/playlists manquants)"
    DAYS_TO_PROCESS=()
    local today=$(date +%Y-%m-%d)
    local yesterday=$(date -d "yesterday" +%Y-%m-%d)
    for i in {0..9}; do
        local day=$(date -d "$today -$i day" +%Y-%m-%d)
        local has_playlist=$(find "$DATA_DIR/hls" -type f -path "*/$day/playlist.m3u8" | grep -q . && echo 1 || echo 0)
        local has_segments=$(find "$DATA_DIR/hls" -type f -path "*/$day/*.ts" | grep -q . && echo 1 || echo 0)
        if [ "$has_playlist" -eq 0 ] || [ "$has_segments" -eq 0 ]; then
            DAYS_TO_PROCESS+=("$day")
        fi
    done
    # Toujours inclure aujourd'hui et la veille (même s'ils sont complets)
    [[ ! " ${DAYS_TO_PROCESS[@]} " =~ " $today " ]] && DAYS_TO_PROCESS+=("$today")
    [[ ! " ${DAYS_TO_PROCESS[@]} " =~ " $yesterday " ]] && DAYS_TO_PROCESS+=("$yesterday")
    # Unicité et tri
    DAYS_TO_PROCESS=($(printf "%s\n" "${DAYS_TO_PROCESS[@]}" | sort -u))
    log "INFO" "Jours à traiter: ${DAYS_TO_PROCESS[*]}"
}

# =============================================================================
# PHASE 2: TÉLÉCHARGEMENT DES DONNÉES (SCRIPTS DE PRODUCTION)
# =============================================================================


download_active_datasets() {
    log "INFO" "📥 PHASE 2: Téléchargement ciblé pour les jours à traiter"
    # Vérifier que les scripts de production existent
    local required_scripts=(
        "$SCRIPT_DIR/smart-fetch.sh"
        "$SCRIPT_DIR/generate-historical-data.sh"
    )
    for script in "${required_scripts[@]}"; do
        if [ ! -f "$script" ]; then
            log "ERROR" "Script de production manquant: $script"
            exit 1
        fi
    done
    log "INFO" "✅ Tous les scripts de production sont disponibles"
    # Récupérer la liste des datasets actifs (auto_download: true)
    local datasets=($(jq -r '[.enabled_datasets // {} | to_entries[]] | .[] | select(.value.auto_download == true) | .key' "$CONFIG_DIR/datasets-status.json"))
    if [ ${#datasets[@]} -eq 0 ]; then
        log "WARN" "Aucun dataset actif trouvé pour le téléchargement."
        return 1
    fi
    for day in "${DAYS_TO_PROCESS[@]}"; do
        local smartfetch_failed=0
        for dataset_key in "${datasets[@]}"; do
            # Conversion dataset_key (points) -> chemin relatif (slashs)
            local dataset_path=$(echo "$dataset_key" | tr '.' '/')
            local images_dir="$DATA_DIR/$dataset_path/$day"
            # Suppression des images corrompues (taille nulle) avant téléchargement
            local corrupted_count=$(find "$images_dir" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" \) -size 0 -delete -print | wc -l)
            if [ "$corrupted_count" -gt 0 ]; then
                log "WARN" "    🧹 $corrupted_count image(s) corrompue(s) supprimée(s) dans $images_dir (avant téléchargement)"
            fi
            log "INFO" "📥 Téléchargement des images pour $dataset_key le $day"
            if bash "$SCRIPT_DIR/smart-fetch.sh" dataset "$dataset_key" "$day" "$day" 2>&1 | tee -a "$LOG_FILE"; then
                log "INFO" "✅ Images téléchargées pour $dataset_key le $day"
            else
                log "WARN" "⚠️ smart-fetch.sh a échoué pour $dataset_key le $day"
                smartfetch_failed=1
            fi
        done
        if [ "$smartfetch_failed" -eq 1 ]; then
            log "INFO" "↪️ Tentative de génération de profondeur temporelle pour $day (au moins un dataset en échec)"
            if bash "$SCRIPT_DIR/generate-historical-data.sh" "$day" "$day" 2>&1 | tee -a "$LOG_FILE"; then
                log "INFO" "✅ generate-historical-data.sh terminé pour $day"
            else
                log "ERROR" "❌ Échec du téléchargement pour au moins un dataset le $day"
            fi
        fi
    done
    # Vérifier que des données ont été téléchargées
    local image_count=$(find "$DATA_DIR" -name "*.jpg" -type f | wc -l)
    log "INFO" "📊 Images téléchargées: $image_count"
    if [ "$image_count" -eq 0 ]; then
        log "WARN" "⚠️ Aucune image téléchargée"
    fi
    log "INFO" "✅ Phase de téléchargement terminée"
}

# =============================================================================
# PHASE 3: GÉNÉRATION DES VIDÉOS (SCRIPTS DE PRODUCTION)
# =============================================================================


generate_daily_videos() {
    log "INFO" "🎬 PHASE 3: Génération vidéo ciblée pour les jours à traiter"
    if [ ! -f "$SCRIPT_DIR/generate-daily-video.sh" ]; then
        log "ERROR" "Script de production manquant: generate-daily-video.sh"
        exit 1
    fi
    local image_count=$(find "$DATA_DIR" -name "*.jpg" -type f | wc -l)
    if [ "$image_count" -eq 0 ]; then
        log "WARN" "Aucune image trouvée pour générer des vidéos"
        return 0
    fi
    # Récupérer la liste des datasets actifs (comme pour le téléchargement)
    local datasets=($(jq -r '[.enabled_datasets // {} | to_entries[]] | .[] | select(.value.auto_download == true) | .key' "$CONFIG_DIR/datasets-status.json"))
    for day in "${DAYS_TO_PROCESS[@]}"; do
        log "INFO" "  🎬 Génération vidéo et playlist pour $day"
        for dataset_key in "${datasets[@]}"; do
            # Conversion dataset_key (points) -> chemin relatif (slashs)
            local dataset_path=$(echo "$dataset_key" | tr '.' '/')
            local images_dir="$DATA_DIR/$dataset_path/$day"
            # Suppression des images corrompues (taille nulle)
            local corrupted_count=$(find "$images_dir" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" \) -size 0 -delete -print | wc -l)
            if [ "$corrupted_count" -gt 0 ]; then
                log "WARN" "    🧹 $corrupted_count image(s) corrompue(s) supprimée(s) dans $images_dir"
            fi
            local img_count=$(find "$images_dir" -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -type f 2>/dev/null | wc -l)
            if [ "$img_count" -eq 0 ]; then
                log "INFO" "    ⏩ Aucune image pour $dataset_key le $day, génération vidéo sautée."
                continue
            fi
            log "INFO" "    📹 $dataset_key pour $day (chemin: $images_dir)"
            bash "$SCRIPT_DIR/generate-daily-video.sh" "$dataset_key" "$day" >> "$LOG_FILE" 2>&1 || {
                log "WARN" "Échec génération vidéo pour $dataset_key le $day (chemin: $images_dir)"
            }
        done
    done
    # Nouveau compteur : nombre de couples segment_000.ts + playlist.m3u8
    local hls_dirs=$(find "$DATA_DIR/hls" -type d)
    local video_count=0
    for dir in $hls_dirs; do
        if [ -f "$dir/segment_000.ts" ] && [ -f "$dir/playlist.m3u8" ]; then
            video_count=$((video_count+1))
        fi
    done
    log "INFO" "📊 Vidéos générées (couples ts/m3u8): $video_count"
    log "INFO" "✅ Phase de génération vidéo terminée"
}

# =============================================================================
# PHASE 4: CRÉATION DES PLAYLISTS
# =============================================================================

create_playlists() {
    log "INFO" "📋 PHASE 4: Création des playlists HLS"
    
    # Les playlists sont normalement créées par generate-daily-video.sh
    # Vérifions qu'elles existent et comptons-les
    
    local playlist_count=$(find "$DATA_DIR/hls" -name "playlist.m3u8" -type f | wc -l)
    local segment_count=$(find "$DATA_DIR/hls" -name "*.ts" -type f | wc -l)
    
    log "INFO" "Playlists HLS créées: $playlist_count"
    log "INFO" "Segments vidéo créés: $segment_count"
    
    if [ "$playlist_count" -gt 0 ]; then
        log "INFO" "Structure des playlists:"
        find "$DATA_DIR/hls" -name "playlist.m3u8" -type f | head -5 | while read -r playlist; do
            local rel_path=$(echo "$playlist" | sed "s|$DATA_DIR/||")
            log "INFO" "  - $rel_path"
        done
        
        if [ "$playlist_count" -gt 5 ]; then
            log "INFO" "  ... et $((playlist_count - 5)) autres"
        fi
    fi
    
    log "INFO" "✅ Playlists HLS disponibles"
}

# =============================================================================
# PHASE 5: VALIDATION ET RAPPORT
# =============================================================================

generate_report() {
    log "INFO" "📊 PHASE 5: Génération du rapport final"
    
    # Statistiques finales
    local total_images=$(find "$DATA_DIR" -name "*.jpg" -type f | wc -l)
    local total_videos=0
    for day in "$@"; do
        for dataset_key in "${datasets[@]}"; do
            local hls_dir="$DATA_DIR/hls/$dataset_key/$day"
            if [ -f "$hls_dir/segment_000.ts" ] && [ -f "$hls_dir/playlist.m3u8" ]; then
                total_videos=$((total_videos+1))
            fi
        done
    done
    local total_playlists=$(find "$DATA_DIR/hls" -name "playlist.m3u8" -type f | wc -l)
    local total_segments=$(find "$DATA_DIR/hls" -name "*.ts" -type f | wc -l)
    local data_size=$(du -sh "$DATA_DIR" 2>/dev/null | cut -f1)
    
    echo ""
    echo "========================================="
    echo "📊 RAPPORT FINAL - TEST COMPLET"
    echo "========================================="
    echo "🖼️  Images téléchargées: $total_images"
    echo "🎬 Vidéos générées: $total_videos"  
    echo "📋 Playlists HLS: $total_playlists"
    echo "🎞️  Segments vidéo: $total_segments"
    echo "💾 Taille totale des données: $data_size"
    echo ""
    
    if [ "$total_images" -gt 0 ] && [ "$total_playlists" -gt 0 ]; then
        echo "✅ TEST COMPLET RÉUSSI!"
        echo ""
        echo "🚀 L'application frontend peut maintenant:"
        echo "   - Afficher les datasets disponibles"
        echo "   - Lire les vidéos satellitaires"
        echo "   - Naviguer dans les playlists HLS"
        echo ""
        echo "🌐 Démarrez le serveur avec: npm run dev"
        echo "📱 Accédez à: http://localhost:10000"
    else
        echo "❌ TEST INCOMPLET"
        echo "   Vérifiez les logs pour plus de détails: $LOG_FILE"
    fi
    
    echo "========================================="
    echo ""
}

# =============================================================================
# FONCTION PRINCIPALE
# =============================================================================


main() {
    echo ""
    echo "🌍 EarthImagery - Test de bout en bout (Scripts de Production)"
    echo "============================================================="
    echo ""
    echo "Ce test exécute directement les scripts qui tourneront en production:"
    echo "  📥 Phase 2: Téléchargement ciblé"
    echo "  🎬 Phase 3: Génération vidéo ciblée"
    echo "  📋 Phase 4: Validation des playlists HLS générées"
    echo ""
    # Initialisation
    create_directories
    check_dependencies
    # Détection des jours à traiter
    detect_days_to_process
    # Exécution des phases avec les scripts de production
    download_active_datasets
    generate_daily_videos
    create_playlists
    # Compteur strictement local : nombre de couples HLS générés dans cette exécution
    local local_video_count=0
    local datasets=($(jq -r '[.enabled_datasets // {} | to_entries[]] | .[] | select(.value.auto_download == true) | .key' "$CONFIG_DIR/datasets-status.json"))
    for day in "${DAYS_TO_PROCESS[@]}"; do
        for dataset_key in "${datasets[@]}"; do
            local hls_dir="$DATA_DIR/hls/$dataset_key/$day"
            if [ -f "$hls_dir/segment_000.ts" ] && [ -f "$hls_dir/playlist.m3u8" ]; then
                local_video_count=$((local_video_count+1))
            fi
        done
    done
    log "INFO" "📊 Couples HLS générés dans cette exécution: $local_video_count"
    generate_report "${DAYS_TO_PROCESS[@]}"
    # Suppression des images sauf aujourd'hui et la veille
    local today=$(date +%Y-%m-%d)
    local yesterday=$(date -d "yesterday" +%Y-%m-%d)
    log "INFO" "🧹 Suppression de toutes les images sauf celles du jour courant ($today) et de la veille ($yesterday) dans DATA_DIR"
    find "$DATA_DIR" -name "*.jpg" -type f | while read -r img; do
        # Extraire la date du chemin (suppose /YYYY-MM-DD/ dans le chemin)
        img_date=$(echo "$img" | grep -oE "/[0-9]{4}-[0-9]{2}-[0-9]{2}/" | tr -d "/")
        if [ "$img_date" != "$today" ] && [ "$img_date" != "$yesterday" ]; then
            rm -f "$img"
        fi
    done
    log "INFO" "🎉 Test complet terminé - Log disponible: $LOG_FILE"
}

# =============================================================================
# POINT D'ENTRÉE
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
