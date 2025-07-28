#!/bin/bash

# Script de re-génération complète des segments HLS avec timing correct

echo "=== Re-génération complète des segments HLS ==="

DATA_ROOT="/home/johann/developpement/earthimagery/public/data"

for date in 2025-07-21 2025-07-22 2025-07-23 2025-07-24 2025-07-25 2025-07-26 2025-07-27 2025-07-28; do
    echo "Re-génération complète pour $date..."
    
    YEAR=$(date -d "$date" +%Y)
    MONTH=$(date -d "$date" +%m)
    DAY=$(date -d "$date" +%d)
    IMAGES_DIR="$DATA_ROOT/images/$YEAR/$MONTH/$DAY"
    HLS_DIR="$DATA_ROOT/hls/$date"
    VIDEO_MP4="$DATA_ROOT/videos/day-$date.mp4"
    TEMP_VIDEO="/tmp/clean-$date.mp4"
    
    if [ -d "$IMAGES_DIR" ]; then
        # Étape 1: Créer une vidéo propre avec timing correct
        ffmpeg -y -r 2 \
            -pattern_type glob \
            -i "$IMAGES_DIR/*.jpg" \
            -c:v libx264 \
            -crf 23 \
            -preset medium \
            -pix_fmt yuv420p \
            -movflags +faststart \
            -video_track_timescale 90000 \
            "$TEMP_VIDEO" \
            2>/dev/null
        
        if [ -f "$TEMP_VIDEO" ]; then
            # Étape 2: Copier la vidéo propre vers le fichier final
            cp "$TEMP_VIDEO" "$VIDEO_MP4"
            
            # Étape 3: Créer les segments HLS avec timing correct
            mkdir -p "$HLS_DIR"
            ffmpeg -y -i "$TEMP_VIDEO" \
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
                -hls_time 12 \
                -hls_list_size 0 \
                -hls_segment_filename "$HLS_DIR/segment_%03d.ts" \
                -f hls \
                "$HLS_DIR/playlist.m3u8" \
                2>/dev/null
            
            rm -f "$TEMP_VIDEO"
            
            if [ $? -eq 0 ]; then
                echo "✓ Re-génération complète réussie pour $date"
            else
                echo "✗ Erreur re-génération HLS pour $date"
            fi
        else
            echo "✗ Erreur création vidéo pour $date"
        fi
    else
        echo "⚠ Dossier images manquant pour $date"
    fi
done

echo "=== Re-génération terminée ==="
