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
    mkdir -p "$DATA_DIR/videos" 
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
# PHASE 1: NETTOYAGE
# =============================================================================

cleanup_all_data() {
    log "INFO" "🧹 PHASE 1: Nettoyage sélectif (préservation des images)"
    
    # Supprimer UNIQUEMENT les vidéos et playlists (préserver les images)
    if [ -d "$DATA_DIR" ]; then
        log "INFO" "Préservation des images existantes..."
        log "INFO" "Suppression des vidéos..."
        find "$DATA_DIR" -name "*.mp4" -type f -delete 2>/dev/null || true
        
        log "INFO" "Suppression des playlists et segments HLS..."
        find "$DATA_DIR" -name "*.m3u8" -type f -delete 2>/dev/null || true
        find "$DATA_DIR" -name "*.ts" -type f -delete 2>/dev/null || true
        
        log "INFO" "Nettoyage des anciens logs..."
        find "$DATA_DIR/logs" -name "*.log" -type f -mtime +1 -delete 2>/dev/null || true
        
        # Supprimer les dossiers vides (sauf ceux avec images et logs)
        find "$DATA_DIR" -type d -empty -not -path "$DATA_DIR/logs*" -delete 2>/dev/null || true
    fi
    
    log "INFO" "✅ Nettoyage terminé"
}

# =============================================================================
# PHASE 2: TÉLÉCHARGEMENT DES DONNÉES (SCRIPTS DE PRODUCTION)
# =============================================================================

download_active_datasets() {
    log "INFO" "📥 PHASE 2: Exécution des scripts de téléchargement de production"
    
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
    
    # Calculer les dates pour les scripts de production (10 derniers jours, en excluant aujourd'hui)
    local end_date=$(date -d "1 day ago" +%Y-%m-%d)         # 2025-07-29 (hier)
    local start_date=$(date -d "10 days ago" +%Y-%m-%d)     # 2025-07-20 (il y a 10 jours)
    local days_count=$(( ($(date -d "$end_date" +%s) - $(date -d "$start_date" +%s)) / 86400 + 1 ))
    
    log "INFO" "📅 Période de test: $start_date à $end_date ($days_count jours)"
    
    # Option 1: Exécuter smart-fetch.sh avec les bonnes dates (paramètres de production)
    log "INFO" "🚀 Lancement de smart-fetch.sh sync avec période $start_date à $end_date (toutes les images disponibles)"
    if bash "$SCRIPT_DIR/smart-fetch.sh" sync "$days_count" 2>&1 | tee -a "$LOG_FILE"; then
        log "INFO" "✅ smart-fetch.sh terminé avec succès"
    else
        log "WARN" "⚠️ smart-fetch.sh a rencontré des problèmes, tentative avec generate-historical-data.sh"
        
        # Option 2: Exécuter generate-historical-data.sh avec les bonnes dates
        log "INFO" "🚀 Lancement de generate-historical-data.sh avec période $start_date à $end_date"
        if bash "$SCRIPT_DIR/generate-historical-data.sh" "$start_date" "$end_date" 2>&1 | tee -a "$LOG_FILE"; then
            log "INFO" "✅ generate-historical-data.sh terminé avec succès"
        else
            log "ERROR" "❌ Échec des scripts de téléchargement de production"
            return 1
        fi
    fi
    
    # Vérifier que des données ont été téléchargées
    local image_count=$(find "$DATA_DIR" -name "*.jpg" -type f | wc -l)
    log "INFO" "📊 Images téléchargées par les scripts de production: $image_count"
    
    if [ "$image_count" -eq 0 ]; then
        log "WARN" "⚠️ Aucune image téléchargée par les scripts de production"
    fi
    
    log "INFO" "✅ Phase de téléchargement de production terminée"
}

# =============================================================================
# PHASE 3: GÉNÉRATION DES VIDÉOS (SCRIPTS DE PRODUCTION)
# =============================================================================

generate_daily_videos() {
    log "INFO" "🎬 PHASE 3: Exécution des scripts de génération vidéo de production"
    
    # Vérifier que le script de production existe
    if [ ! -f "$SCRIPT_DIR/generate-satellite-videos.sh" ]; then
        log "ERROR" "Script de production manquant: generate-satellite-videos.sh"
        exit 1
    fi
    
    # Vérifier qu'on a des images à traiter
    local image_count=$(find "$DATA_DIR" -name "*.jpg" -type f | wc -l)
    if [ "$image_count" -eq 0 ]; then
        log "WARN" "Aucune image trouvée pour générer des vidéos"
        return 0
    fi
    
    log "INFO" "📊 $image_count images disponibles pour la génération vidéo"
    
    # Lancer le script de production pour la génération de vidéos
    log "INFO" "🎬 Lancement de generate-satellite-videos.sh auto (génération automatique)"
    if bash "$SCRIPT_DIR/generate-satellite-videos.sh" auto 2>&1 | tee -a "$LOG_FILE"; then
        log "INFO" "✅ generate-satellite-videos.sh terminé avec succès"
    else
        log "WARN" "⚠️ generate-satellite-videos.sh a rencontré des problèmes"
        
        # Fallback: utiliser generate-daily-video.sh pour chaque date trouvée
        log "INFO" "🔄 Fallback: utilisation de generate-daily-video.sh"
        
        local image_dates=$(find "$DATA_DIR" -name "*.jpg" -type f | \
            grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}" | \
            sort -u)
        
        if [ -n "$image_dates" ]; then
            echo "$image_dates" | while read -r date; do
                if [ -n "$date" ]; then
                    log "INFO" "  🎬 Génération vidéo pour $date"
                    
                    # Trouver les datasets pour cette date
                    local dataset_dirs=$(find "$DATA_DIR" -path "*/$date/*.jpg" -type f | \
                        sed "s|$DATA_DIR/||" | \
                        sed 's|/[^/]*/[^/]*$||' | \
                        sort -u)
                    
                    echo "$dataset_dirs" | while read -r dataset_path; do
                        if [ -n "$dataset_path" ]; then
                            local dataset_key=$(echo "$dataset_path" | tr '/' '.')
                            log "INFO" "    📹 $dataset_key pour $date"
                            
                            bash "$SCRIPT_DIR/generate-daily-video.sh" "$date" "$dataset_key" >> "$LOG_FILE" 2>&1 || {
                                log "WARN" "Échec génération vidéo pour $dataset_key le $date"
                            }
                        fi
                    done
                fi
            done
        fi
    fi
    
    # Vérifier les résultats
    local video_count=$(find "$DATA_DIR" -name "*.mp4" -type f | wc -l)
    log "INFO" "📊 Vidéos générées par les scripts de production: $video_count"
    
    log "INFO" "✅ Phase de génération vidéo de production terminée"
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
    local total_videos=$(find "$DATA_DIR" -name "*.mp4" -type f | wc -l)
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
    echo "  📥 Phase 2: smart-fetch.sh ou generate-historical-data.sh"
    echo "  🎬 Phase 3: generate-satellite-videos.sh"
    echo "  📋 Phase 4: Validation des playlists HLS générées"
    echo ""
    
    # Initialisation
    create_directories
    check_dependencies
    
    # Exécution des phases avec les scripts de production
    cleanup_all_data
    download_active_datasets  
    generate_daily_videos
    create_playlists
    generate_report
    
    log "INFO" "🎉 Test complet terminé - Log disponible: $LOG_FILE"
}

# =============================================================================
# POINT D'ENTRÉE
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
