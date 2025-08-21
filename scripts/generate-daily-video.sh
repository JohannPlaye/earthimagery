#!/bin/bash

# Script de génération des vidéos journalières et fragments HLS
# Usage: ./generate-daily-video.sh DATASET_KEY DATE
# Exemple: ./generate-daily-video.sh GOES18.hi.GEOCOLOR.600x600 2025-07-19

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_ROOT_PATH="$PROJECT_ROOT/public/data"

# Configuration FFmpeg
VIDEO_FPS=24  # 24 FPS pour les vraies données satellitaires
VIDEO_CRF=23
VIDEO_PRESET="medium"
HLS_SEGMENT_TIME=10

# Paramètres d'entrée
DATASET_KEY="$1"
TARGET_DATE="$2"

if [ -z "$DATASET_KEY" ] || [ -z "$TARGET_DATE" ]; then
    echo "❌ Usage: $0 DATASET_KEY TARGET_DATE"
    echo "   Exemple: $0 GOES18.hi.GEOCOLOR.600x600 2025-07-19"
    echo "   Ou pour tous les datasets: $0 all 2025-07-19"
    exit 1
fi

# Création des dossiers si nécessaire
mkdir -p "$DATA_ROOT_PATH/hls"
mkdir -p "$DATA_ROOT_PATH/logs"

LOG_FILE="$DATA_ROOT_PATH/logs/generate-video-$(date +%Y%m%d).log"

# Fonction de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Vérification de FFmpeg
if ! command -v ffmpeg &> /dev/null; then
    log "❌ ffmpeg n'est pas installé"
    exit 1
fi

# Fonction pour trouver le dossier d'images selon le dataset avec support NOAA/EUMETSAT
find_images_directory() {
    local dataset_key="$1"
    local date="$2"
    
    # Récupérer la source du dataset depuis la configuration
    local config_file="$(dirname "$SCRIPT_DIR")/config/datasets-status.json"
    local source=$(jq -r ".enabled_datasets[\"$dataset_key\"].source // \"UNKNOWN\"" "$config_file" 2>/dev/null)
    
    # Conversion du dataset key en chemin: GOES18.hi.GEOCOLOR.600x600 -> NOAA/GOES18/hi/GEOCOLOR/600x600
    IFS='.' read -ra PARTS <<< "$dataset_key"
    if [ ${#PARTS[@]} -eq 4 ]; then
        local satellite="${PARTS[0]}"
        local sector="${PARTS[1]}"
        local product="${PARTS[2]}"
        local resolution="${PARTS[3]}"
        
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
    else
        echo ""
    fi
}

# Fonction pour générer une vidéo pour un dataset
generate_video_for_dataset() {
    local dataset_key="$1"
    local target_date="$2"
    
    log "🎬 Génération vidéo pour $dataset_key - $target_date"
    
    # Détermination du dossier d'images
    local images_dir=$(find_images_directory "$dataset_key" "$target_date")
    
    if [ -z "$images_dir" ] || [ ! -d "$images_dir" ]; then
        log "❌ Dossier d'images non trouvé: $images_dir"
        return 1
    fi
    
    # Comptage des images
    local image_count=$(find "$images_dir" -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" | wc -l)
    if [ "$image_count" -eq 0 ]; then
        log "❌ Aucune image trouvée dans $images_dir"
        return 1
    fi
    
    log "📊 $image_count images trouvées dans $images_dir"
    
    # Chemins de sortie
    local hls_output_dir="$DATA_ROOT_PATH/hls/$dataset_key/$target_date"
    local hls_playlist="$hls_output_dir/playlist.m3u8"
    local segment_file="$hls_output_dir/segment_000.ts"
    mkdir -p "$hls_output_dir"

    # Nettoyer les anciens segments et playlist
    rm -f "$hls_output_dir"/*.ts "$hls_playlist"

    # Création de la liste d'images triées chronologiquement
    local images_list="/tmp/images-$dataset_key-$target_date.txt"
    find "$images_dir" -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" | sort > "$images_list"

    # Vérification du tri
    local first_image=$(head -n1 "$images_list")
    local last_image=$(tail -n1 "$images_list")
    log "🎞️ Première image: $(basename "$first_image")"
    log "🎞️ Dernière image: $(basename "$last_image")"

    # Détection automatique de la résolution pour adapter les paramètres FFmpeg
    local image_resolution="standard"
    local ffmpeg_threads=2
    local video_preset="medium"
    
    if [[ "$dataset_key" == *"4000x4000"* ]]; then
        image_resolution="ultra_high"
        ffmpeg_threads=1  # Limiter les threads pour économiser la mémoire
        video_preset="ultrafast"  # Preset plus rapide pour éviter les timeouts
        log "📊 Détection ultra-haute résolution (4000x4000): optimisation mémoire activée"
    elif [[ "$dataset_key" == *"2000x2000"* ]]; then
        image_resolution="high"
        ffmpeg_threads=2
        video_preset="fast"
        log "📊 Détection haute résolution (2000x2000): optimisation modérée"
    fi

    # Génération vidéo MP4 temporaire
    log "🔄 Génération MP4 temporaire..."
    local temp_video="/tmp/temp-$dataset_key-$target_date.mp4"
    local success=false
    
    # Détection du source pour adapter la méthode FFmpeg
    local use_pattern_input=false
    if [[ "$dataset_key" == MTG.* ]]; then
        # Pour EUMETSAT, utiliser le pattern d'entrée pour forcer la framerate
        use_pattern_input=true
        log "📊 Détection EUMETSAT: utilisation du pattern d'entrée pour corriger les timestamps"
    fi
    
    if [ "$use_pattern_input" = true ]; then
        # Méthode pattern pour EUMETSAT avec format pixel correct
        if ffmpeg -hide_banner -y \
            -framerate "$VIDEO_FPS" \
            -pattern_type glob \
            -i "$(dirname "$first_image")/*.png" \
            -r "$VIDEO_FPS" \
            -threads "$ffmpeg_threads" \
            -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" \
            -c:v libx264 \
            -crf "$VIDEO_CRF" \
            -preset "$video_preset" \
            -pix_fmt yuv420p \
            -color_range tv \
            -colorspace bt709 \
            -movflags +faststart \
            "$temp_video" &>> "$LOG_FILE"; then
            success=true
        fi
    else
        # Méthode concat pour NOAA avec optimisations selon la résolution
        local concat_cmd=""
        if [ "$image_resolution" = "ultra_high" ]; then
            # Pour les images 4000x4000 : paramètres optimisés sans downscale
            concat_cmd="ffmpeg -hide_banner -y \
                -f concat \
                -safe 0 \
                -threads $ffmpeg_threads \
                -i <(sed \"s/^/file '/\" \"$images_list\" | sed \"s/\$/'/\" ) \
                -r $VIDEO_FPS \
                -vf \"pad=ceil(iw/2)*2:ceil(ih/2)*2\" \
                -c:v libx264 \
                -crf $((VIDEO_CRF + 2)) \
                -preset $video_preset \
                -pix_fmt yuv420p \
                -color_range tv \
                -colorspace bt709 \
                -movflags +faststart \
                -max_muxing_queue_size 1024 \
                \"$temp_video\""
            log "🔧 Optimisation ultra-haute résolution: format pixel correct, CRF+2, muxing_queue étendu"
        else
            # Méthode standard pour les autres résolutions
            concat_cmd="ffmpeg -hide_banner -y \
                -f concat \
                -safe 0 \
                -threads $ffmpeg_threads \
                -i <(sed \"s/^/file '/\" \"$images_list\" | sed \"s/\$/'/\" ) \
                -r $VIDEO_FPS \
                -vf \"pad=ceil(iw/2)*2:ceil(ih/2)*2\" \
                -c:v libx264 \
                -crf $VIDEO_CRF \
                -preset $video_preset \
                -pix_fmt yuv420p \
                -color_range tv \
                -colorspace bt709 \
                -movflags +faststart \
                \"$temp_video\""
        fi
        
        if eval "$concat_cmd" &>> "$LOG_FILE"; then
            success=true
        fi
    fi
    
    if [ "$success" = true ]; then
        # Générer un unique segment TS
        if ffmpeg -y -i "$temp_video" -c copy -f mpegts "$segment_file" &>> "$LOG_FILE"; then
            log "✅ Segment unique créé: $(basename "$segment_file")"
            # Générer la playlist HLS qui référence uniquement ce segment
            local duration_raw=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$segment_file")
            local duration_int=$(echo "$duration_raw" | awk '{print int($1+0.5)}')
            local duration_fmt=$(echo "$duration_raw" | awk '{printf "%.3f", $1}')
            {
                echo "#EXTM3U"
                echo "#EXT-X-VERSION:3"
                echo "#EXT-X-TARGETDURATION:$duration_int"
                echo "#EXT-X-MEDIA-SEQUENCE:0"
                echo "#EXTINF:$duration_fmt,"
                echo "$(basename "$segment_file")"
                echo "#EXT-X-ENDLIST"
            } > "$hls_playlist"
            log "✅ Playlist générée: $hls_playlist"
            rm -f "$temp_video" "$images_list"
            return 0
        else
            log "❌ Erreur lors de la conversion TS pour le segment du jour ($segment_file)"
            rm -f "$temp_video" "$images_list"
            return 1
        fi
    else
        log "❌ Échec génération MP4 temporaire"
        rm -f "$images_list"
        return 1
    fi
}

# Script principal
if [ "$DATASET_KEY" = "all" ]; then
    log "🔄 Traitement de tous les datasets pour $TARGET_DATE"
    
    # Recherche de tous les datasets disponibles
    find "$DATA_ROOT_PATH" -type d -name "$TARGET_DATE" | while read -r date_dir; do
        # Extraire le dataset key du chemin
        local path_parts=$(echo "$date_dir" | sed "s|$DATA_ROOT_PATH/||" | sed "s|/$TARGET_DATE||")
        local dataset_key=$(echo "$path_parts" | tr '/' '.')
        
        if [[ "$dataset_key" =~ ^[A-Z0-9]+\.[a-z]+\.[A-Z]+\.[0-9x]+$ ]]; then
            log "📹 Traitement: $dataset_key"
            generate_video_for_dataset "$dataset_key" "$TARGET_DATE"
        fi
    done
    
    log "✅ Traitement terminé"
else
    # Mode single dataset
    generate_video_for_dataset "$DATASET_KEY" "$TARGET_DATE"
fi
