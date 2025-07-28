#!/bin/bash

# Script de génération de données de test pour EarthImagery
# Génère des images factices et vidéos pour tester l'application

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

LOG_FILE="$DATA_ROOT_PATH/$LOGS_DIR/generate-test-data-$(date +%Y%m%d).log"

# Création des dossiers si nécessaire
mkdir -p "$DATA_ROOT_PATH/$IMAGES_DIR"
mkdir -p "$DATA_ROOT_PATH/$VIDEOS_DIR"
mkdir -p "$DATA_ROOT_PATH/$HLS_DIR"
mkdir -p "$DATA_ROOT_PATH/$LOGS_DIR"

# Fonction de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Vérification de la présence d'ImageMagick
if ! command -v convert &> /dev/null; then
    log "⚠ ImageMagick non installé. Installation recommandée pour générer des images de test"
    log "Ubuntu/Debian: sudo apt install imagemagick"
    log "Génération d'images simples sans ImageMagick..."
    USE_IMAGEMAGICK=false
else
    USE_IMAGEMAGICK=true
fi

# Vérification de la présence de ffmpeg
if ! command -v ffmpeg &> /dev/null; then
    log "✗ Erreur: ffmpeg n'est pas installé"
    log "Ubuntu/Debian: sudo apt install ffmpeg"
    exit 1
fi

log "Début de génération des données de test"

# Générer des données pour les 7 derniers jours
for i in {6..0}; do
    TARGET_DATE=$(date -d "$i days ago" +%Y-%m-%d)
    log "Génération des données pour $TARGET_DATE"
    
    # Création du dossier pour la date (structure YYYY/MM/DD)
    YEAR=$(date -d "$TARGET_DATE" +%Y)
    MONTH=$(date -d "$TARGET_DATE" +%m)
    DAY=$(date -d "$TARGET_DATE" +%d)
    DATE_DIR="$DATA_ROOT_PATH/$IMAGES_DIR/$YEAR/$MONTH/$DAY"
    mkdir -p "$DATE_DIR"
    
    # Générer 24 images (une par heure simulée)
    for hour in {00..23}; do
        timestamp="${TARGET_DATE//-/}_${hour}00"
        filename="test_satellite_${timestamp}.jpg"
        filepath="$DATE_DIR/$filename"
        
        if [ "$USE_IMAGEMAGICK" = true ]; then
            # Générer une image avec un pattern qui change selon l'heure
            # Convertir en base 10 pour éviter les erreurs octales
            hour_decimal=$((10#$hour))
            hue=$((hour_decimal * 15))  # Changement de couleur selon l'heure
            saturation=$((50 + hour_decimal * 2))
            
            convert -size 800x600 \
                -define gradient:vector="0,0,800,600" \
                gradient:"hsl($hue,${saturation}%,50%)-hsl($((hue+30)),70%,70%)" \
                -swirl $((hour_decimal * 5)) \
                -font DejaVu-Sans -pointsize 24 \
                -fill white -stroke black -strokewidth 2 \
                -annotate +50+50 "EarthImagery Test\n$TARGET_DATE $hour:00\nSatellite Data" \
                "$filepath"
        else
            # Générer une image simple avec echo et base64 (très basique)
            hour_decimal=$((10#$hour))
            echo "P3 400 300 255" > "/tmp/temp.ppm"
            for ((y=0; y<300; y++)); do
                for ((x=0; x<400; x++)); do
                    r=$(( (x + y + hour_decimal * 10) % 256 ))
                    g=$(( (x * 2 + y + hour_decimal * 15) % 256 ))
                    b=$(( (x + y * 2 + hour_decimal * 20) % 256 ))
                    echo "$r $g $b"
                done
            done >> "/tmp/temp.ppm"
            
            if command -v convert &> /dev/null; then
                convert "/tmp/temp.ppm" "$filepath"
            else
                # Copier un fichier simple si aucune solution graphique
                echo "Test image data for $timestamp" > "$filepath.txt"
                # Créer un fichier JPEG minimal (header seulement)
                printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x01\x00H\x00H\x00\x00\xff\xd9' > "$filepath"
            fi
            rm -f "/tmp/temp.ppm"
        fi
        
        if [ -f "$filepath" ]; then
            log "✓ Image générée: $filename"
        else
            log "✗ Erreur génération image: $filename"
        fi
    done
    
    # Générer la vidéo pour ce jour
    log "Génération vidéo pour $TARGET_DATE"
    
    # Appeler le script de génération vidéo
    if [ -f "$SCRIPT_DIR/generate-daily-video.sh" ]; then
        bash "$SCRIPT_DIR/generate-daily-video.sh" "$TARGET_DATE"
    else
        log "⚠ Script generate-daily-video.sh non trouvé, génération manuelle"
        
        VIDEO_OUTPUT="$DATA_ROOT_PATH/$VIDEOS_DIR/day-$TARGET_DATE.mp4"
        HLS_OUTPUT_DIR="$DATA_ROOT_PATH/$HLS_DIR/$TARGET_DATE"
        HLS_PLAYLIST="$HLS_OUTPUT_DIR/playlist.m3u8"
        
        mkdir -p "$HLS_OUTPUT_DIR"
        
        # Génération MP4
        if ffmpeg -y \
            -framerate "$VIDEO_FPS" \
            -pattern_type glob \
            -i "$DATE_DIR/*.jpg" \
            -c:v libx264 \
            -crf "$VIDEO_CRF" \
            -preset "$VIDEO_PRESET" \
            -movflags +faststart \
            -pix_fmt yuv420p \
            "$VIDEO_OUTPUT" 2>>"$LOG_FILE"; then
            log "✓ Vidéo MP4 générée: $VIDEO_OUTPUT"
            
            # Génération HLS
            if ffmpeg -y \
                -i "$VIDEO_OUTPUT" \
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
                log "✓ Fragments HLS générés: $HLS_OUTPUT_DIR"
            else
                log "✗ Erreur génération HLS pour $TARGET_DATE"
            fi
        else
            log "✗ Erreur génération MP4 pour $TARGET_DATE"
        fi
    fi
done

# Générer un fichier de statut
STATUS_FILE="$DATA_ROOT_PATH/test-data-status.json"
cat > "$STATUS_FILE" << EOF
{
  "generated_at": "$(date -Iseconds)",
  "data_root": "$DATA_ROOT_PATH",
  "days_generated": 7,
  "images_per_day": 24,
  "total_images": 168,
  "video_fps": $VIDEO_FPS,
  "hls_segment_time": $HLS_SEGMENT_TIME,
  "note": "Données de test générées automatiquement"
}
EOF

log "✓ Génération des données de test terminée"
log "📊 Fichier de statut créé: $STATUS_FILE"
log "🎬 Pour tester l'application, démarrez le serveur: npm run dev"
