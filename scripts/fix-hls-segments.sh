#!/bin/bash

# Script de correction des segments HLS pour résoudre les problèmes de lecture avec HLS.js

echo "=== Correction des segments HLS ==="

DATA_ROOT="/home/johann/developpement/earthimagery/public/data"

for date in 2025-07-21 2025-07-22 2025-07-23 2025-07-24 2025-07-25 2025-07-26 2025-07-27 2025-07-28; do
    echo "Correction du segment pour $date..."
    
    HLS_DIR="$DATA_ROOT/hls/$date"
    VIDEO_MP4="$DATA_ROOT/videos/day-$date.mp4"
    
    if [ -f "$VIDEO_MP4" ]; then
        # Régénérer le segment HLS avec des paramètres optimisés pour HLS.js
        mkdir -p "$HLS_DIR"
        ffmpeg -y -i "$VIDEO_MP4" \
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
        
        if [ $? -eq 0 ]; then
            echo "✓ Segment corrigé pour $date"
        else
            echo "✗ Erreur correction pour $date"
        fi
    else
        echo "⚠ Vidéo MP4 manquante pour $date"
    fi
done

echo "=== Correction terminée ==="
