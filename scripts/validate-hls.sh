#!/bin/bash

# Script de validation des segments HLS
echo "=== Validation des segments HLS générés ==="

DATA_ROOT="/home/johann/developpement/earthimagery/public/data"

echo "Date | Segment | Start Time | Duration | Status"
echo "------|---------|------------|----------|-------"

for date in 2025-07-22 2025-07-23 2025-07-24 2025-07-25 2025-07-26 2025-07-27 2025-07-28; do
    HLS_DIR="$DATA_ROOT/hls/$date"
    
    if [ -d "$HLS_DIR" ]; then
        for segment in "$HLS_DIR"/segment_*.ts; do
            if [ -f "$segment" ]; then
                segment_name=$(basename "$segment")
                
                # Extraire start_time et duration avec ffprobe
                timing_info=$(ffprobe -v quiet -show_entries format=start_time,duration "$segment" 2>/dev/null)
                start_time=$(echo "$timing_info" | grep "start_time=" | cut -d'=' -f2)
                duration=$(echo "$timing_info" | grep "duration=" | cut -d'=' -f2)
                
                # Vérifier si start_time est correct pour HLS
                # Seul le premier segment doit avoir start_time=0.000000
                # Les segments suivants peuvent avoir des start_time différents (c'est normal en HLS)
                if [ "$segment_name" = "segment_000.ts" ]; then
                    if [ "$start_time" = "0.000000" ]; then
                        status="✅ OK (first segment)"
                    else
                        status="❌ BAD ($start_time - should be 0.000000)"
                    fi
                else
                    # Pour les segments suivants, vérifier juste qu'ils ont une durée valide
                    if [ -n "$duration" ] && [ "$duration" != "N/A" ]; then
                        status="✅ OK (continuation)"
                    else
                        status="❌ BAD (no duration)"
                    fi
                fi
                
                printf "%-5s | %-11s | %-10s | %-8s | %s\n" "$date" "$segment_name" "$start_time" "$duration" "$status"
            fi
        done
    else
        printf "%-5s | %-11s | %-10s | %-8s | %s\n" "$date" "N/A" "N/A" "N/A" "⚠️ Missing"
    fi
done

echo ""
echo "=== Validation des playlists ==="

for date in 2025-07-22 2025-07-23 2025-07-24 2025-07-25 2025-07-26 2025-07-27 2025-07-28; do
    HLS_DIR="$DATA_ROOT/hls/$date"
    PLAYLIST="$HLS_DIR/playlist.m3u8"
    
    if [ -f "$PLAYLIST" ]; then
        # Compter le nombre de segments dans la playlist
        segment_count=$(grep -c "^segment_" "$PLAYLIST" 2>/dev/null || echo "0")
        
        # Vérifier la structure de base
        if grep -q "#EXTM3U" "$PLAYLIST" && grep -q "#EXT-X-ENDLIST" "$PLAYLIST"; then
            playlist_status="✅ OK ($segment_count segments)"
        else
            playlist_status="❌ Malformed"
        fi
    else
        playlist_status="⚠️ Missing"
    fi
    
    printf "%-10s | %s\n" "$date" "$playlist_status"
done

echo ""
echo "=== Test API ==="

# Tester quelques endpoints API
for date in 2025-07-22 2025-07-24 2025-07-28; do
    api_url="http://localhost:10000/api/playlist?from=$date&to=$date"
    
    if curl -s -f "$api_url" > /dev/null; then
        api_status="✅ OK"
    else
        api_status="❌ Failed"
    fi
    
    printf "%-10s | %s\n" "$date" "$api_status"
done

echo ""
echo "=== Résumé ==="
total_segments=$(find "$DATA_ROOT/hls" -name "segment_*.ts" | wc -l)
total_playlists=$(find "$DATA_ROOT/hls" -name "playlist.m3u8" | wc -l)

echo "Segments générés: $total_segments"
echo "Playlists générées: $total_playlists"
echo "✅ Validation terminée"
