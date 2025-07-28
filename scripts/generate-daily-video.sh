#!/bin/bash

# Script de génération des vidéos journalières et fragments HLS
# À exécuter quotidiennement pour traiter les images du jour précédent

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Variables d'environnement
DATA_ROOT_PATH="$PROJECT_ROOT/public/data"
IMAGES_DIR="images"
VIDEOS_DIR="videos"
HLS_DIR="hls"
LOGS_DIR="logs"

# Configuration FFmpeg
VIDEO_FPS=2  # 2 FPS pour que 24 images durent 12 secondes
VIDEO_CRF=23
VIDEO_PRESET="medium"
HLS_SEGMENT_TIME=10

LOG_FILE="$DATA_ROOT_PATH/$LOGS_DIR/generate-video-$(date +%Y%m%d).log"

# Date à traiter (par défaut: hier)
TARGET_DATE=${1:-$(date -d "yesterday" +%Y-%m-%d)}

# Création des dossiers si nécessaire
mkdir -p "$DATA_ROOT_PATH/$VIDEOS_DIR"
mkdir -p "$DATA_ROOT_PATH/$HLS_DIR"
mkdir -p "$DATA_ROOT_PATH/$LOGS_DIR"

# Fonction de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Vérification de la présence de ffmpeg
if ! command -v ffmpeg &> /dev/null; then
    log "✗ Erreur: ffmpeg n'est pas installé"
    exit 1
fi

log "Début de génération vidéo pour $TARGET_DATE"

# Chemins avec structure YYYY/MM/DD
YEAR=$(echo "$TARGET_DATE" | cut -d'-' -f1)
MONTH=$(echo "$TARGET_DATE" | cut -d'-' -f2)
DAY=$(echo "$TARGET_DATE" | cut -d'-' -f3)
IMAGES_DIR_DATE="$DATA_ROOT_PATH/$IMAGES_DIR/$YEAR/$MONTH/$DAY"
VIDEO_OUTPUT="$DATA_ROOT_PATH/$VIDEOS_DIR/day-$TARGET_DATE.mp4"
HLS_OUTPUT_DIR="$DATA_ROOT_PATH/$HLS_DIR/$TARGET_DATE"
HLS_PLAYLIST="$HLS_OUTPUT_DIR/playlist.m3u8"

# Vérification de l'existence des images
if [ ! -d "$IMAGES_DIR_DATE" ]; then
    log "✗ Aucun dossier d'images trouvé pour $TARGET_DATE"
    exit 1
fi

# Comptage des images
IMAGE_COUNT=$(find "$IMAGES_DIR_DATE" -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" | wc -l)
if [ "$IMAGE_COUNT" -eq 0 ]; then
    log "✗ Aucune image trouvée dans $IMAGES_DIR_DATE"
    exit 1
fi

log "Trouvé $IMAGE_COUNT images pour $TARGET_DATE"

# Création du dossier HLS
mkdir -p "$HLS_OUTPUT_DIR"

# Génération de la vidéo MP4 temporaire
log "Génération de la vidéo MP4..."
TEMP_VIDEO="/tmp/temp-$TARGET_DATE.mp4"

if ffmpeg -y \
    -framerate "$VIDEO_FPS" \
    -pattern_type glob \
    -i "$IMAGES_DIR_DATE/*.jpg" \
    -c:v libx264 \
    -crf "$VIDEO_CRF" \
    -preset "$VIDEO_PRESET" \
    -movflags +faststart \
    -pix_fmt yuv420p \
    "$TEMP_VIDEO" 2>>"$LOG_FILE"; then
    log "✓ Vidéo MP4 générée: $TEMP_VIDEO"
else
    log "✗ Erreur lors de la génération MP4"
    exit 1
fi

# Génération des fragments HLS
log "Génération des fragments HLS..."
if ffmpeg -y \
    -i "$TEMP_VIDEO" \
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
    -hls_segment_filename "$HLS_OUTPUT_DIR/segment_%03d.ts" \
    -f hls \
    "$HLS_PLAYLIST" 2>>"$LOG_FILE"; then
    log "✓ Fragments HLS générés dans $HLS_OUTPUT_DIR"
else
    log "✗ Erreur lors de la génération HLS"
    rm -f "$TEMP_VIDEO"
    exit 1
fi

# Déplacement de la vidéo finale
mv "$TEMP_VIDEO" "$VIDEO_OUTPUT"
log "✓ Vidéo finale: $VIDEO_OUTPUT"

# Calcul de la taille des fichiers
VIDEO_SIZE=$(du -h "$VIDEO_OUTPUT" | cut -f1)
HLS_SIZE=$(du -sh "$HLS_OUTPUT_DIR" | cut -f1)

log "Taille vidéo MP4: $VIDEO_SIZE"
log "Taille dossier HLS: $HLS_SIZE"

# Nettoyage des vidéos anciennes (garde 90 jours)
find "$DATA_ROOT_PATH/$VIDEOS_DIR" -name "day-*.mp4" -mtime +90 -delete 2>/dev/null
find "$DATA_ROOT_PATH/$HLS_DIR" -type d -name "20*" -mtime +90 -exec rm -rf {} \; 2>/dev/null

# Nettoyage des logs anciens
find "$DATA_ROOT_PATH/$LOGS_DIR" -name "generate-video-*.log" -mtime +7 -delete 2>/dev/null

log "Génération terminée pour $TARGET_DATE"
