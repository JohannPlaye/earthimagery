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
mkdir -p "$DATA_ROOT_PATH/videos"
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

# Fonction pour trouver le dossier d'images selon le dataset
find_images_directory() {
    local dataset_key="$1"
    local date="$2"
    
    # Conversion du dataset key en chemin: GOES18.hi.GEOCOLOR.600x600 -> GOES18/hi/GEOCOLOR/600x600
    IFS='.' read -ra PARTS <<< "$dataset_key"
    if [ ${#PARTS[@]} -eq 4 ]; then
        local satellite="${PARTS[0]}"
        local sector="${PARTS[1]}"
        local product="${PARTS[2]}"
        local resolution="${PARTS[3]}"
        echo "$DATA_ROOT_PATH/$satellite/$sector/$product/$resolution/$date"
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
    local video_output="$DATA_ROOT_PATH/videos/$dataset_key-$target_date.mp4"
    local hls_output_dir="$DATA_ROOT_PATH/hls/$dataset_key/$target_date"
    local hls_playlist="$hls_output_dir/playlist.m3u8"
    
    mkdir -p "$hls_output_dir"
    
    # Création de la liste d'images triées chronologiquement
    local images_list="/tmp/images-$dataset_key-$target_date.txt"
    find "$images_dir" -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" | sort > "$images_list"
    
    # Vérification du tri
    local first_image=$(head -n1 "$images_list")
    local last_image=$(tail -n1 "$images_list")
    log "🎞️ Première image: $(basename "$first_image")"
    log "🎞️ Dernière image: $(basename "$last_image")"
    
    # Génération vidéo MP4
    log "🔄 Génération MP4..."
    local temp_video="/tmp/temp-$dataset_key-$target_date.mp4"
    
    if ffmpeg -y \
        -f concat \
        -safe 0 \
        -i <(sed 's/^/file /' "$images_list") \
        -r "$VIDEO_FPS" \
        -c:v libx264 \
        -crf "$VIDEO_CRF" \
        -preset "$VIDEO_PRESET" \
        -pix_fmt yuv420p \
        -movflags +faststart \
        "$temp_video" &>> "$LOG_FILE"; then
        
        # Génération HLS
        log "🔄 Génération HLS..."
        if ffmpeg -y \
            -i "$temp_video" \
            -c:v libx264 \
            -preset ultrafast \
            -pix_fmt yuv420p \
            -g 4 \
            -keyint_min 4 \
            -sc_threshold 0 \
            -b:v 500k \
            -maxrate 500k \
            -bufsize 1000k \
            -avoid_negative_ts make_zero \
            -muxdelay 0 \
            -muxpreload 0 \
            -start_number 0 \
            -hls_time "$HLS_SEGMENT_TIME" \
            -hls_list_size 0 \
            -hls_segment_filename "$hls_output_dir/segment_%03d.ts" \
            -f hls \
            "$hls_playlist" &>> "$LOG_FILE"; then
            
            # Finalisation
            mv "$temp_video" "$video_output"
            rm -f "$images_list"
            
            local video_size=$(du -h "$video_output" | cut -f1)
            local duration=$(echo "scale=1; $image_count / $VIDEO_FPS" | bc -l)
            
            log "✅ Vidéo générée: $video_output ($video_size)"
            log "🎯 Durée: ${duration}s à ${VIDEO_FPS}fps"
            log "📺 HLS: $hls_playlist"
            
            return 0
        else
            log "❌ Échec génération HLS"
            rm -f "$temp_video" "$images_list"
            return 1
        fi
    else
        log "❌ Échec génération MP4"
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
