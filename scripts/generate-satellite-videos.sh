#!/bin/bash

# Génération automatique de vidéos HLS depuis les datasets satellitaires
# Intégration avec le pipeline existant

# Configuration
OUTPUT_DIR="${OUTPUT_DIR:-public/data/hls}"
SATELLITE_DATA_DIR="${SATELLITE_DATA_DIR:-public/data}"
LOG_DIR="${LOG_DIR:-public/data/logs}"

# Fonction de logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_DIR/video-auto-generation-$(date +'%Y%m%d').log"
}

# Créer les répertoires nécessaires
mkdir -p "$OUTPUT_DIR" "$LOG_DIR"

# Générer des fragments vidéo depuis un dataset satellitaire
generate_satellite_video() {
    local satellite="$1"
    local sector="$2"
    local product="$3"
    local resolution="$4"
    local date_str="$5"  # Format: YYYY-MM-DD
    
    local dataset_dir="$SATELLITE_DATA_DIR/$satellite/$sector/$product/$resolution"
    local dataset_key="$satellite.$sector.$product.$resolution"
    local output_date_dir="$OUTPUT_DIR/$dataset_key/$date_str"
    
    log "🎬 Génération vidéo: $satellite/$sector/$product/$resolution pour $date_str"
    
    # Vérifier si le dataset existe
    if [ ! -d "$dataset_dir" ]; then
        log "❌ Dataset non trouvé: $dataset_dir"
        return 1
    fi
    
    # Créer le répertoire de sortie
    mkdir -p "$output_date_dir"
    
    # Lister uniquement les images du jour
    local image_list=$(mktemp)
    find "$dataset_dir/$date_str" -name "*.jpg" -type f | sort > "$image_list"
    local image_count=$(wc -l < "$image_list")
    if [ "$image_count" -eq 0 ]; then
        log "⚠️ Aucune image trouvée pour $dataset_dir/$date_str"
        rm -f "$image_list"
        return 1
    fi

    log "📁 Trouvé $image_count images à traiter pour $date_str"

    # Forcer la création du dossier de sortie HLS
    mkdir -p "$output_date_dir"

    # Générer un unique segment vidéo à 24 fps
    local fps=24
    local segment_file="$output_date_dir/segment_000.ts"
    local temp_video=$(mktemp --suffix=.mp4)

    # Créer la vidéo mp4 temporaire
    if ffmpeg -y -f image2 -framerate $fps -pattern_type glob -i "$dataset_dir/$date_str/*.jpg" \
        -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" \
        -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$temp_video" 2>/dev/null; then
        # Convertir en segment TS
        if ffmpeg -y -i "$temp_video" -c copy -f mpegts "$segment_file" 2>/dev/null; then
            log "✅ Segment unique créé: $(basename "$segment_file")"
        else
            log "❌ Erreur lors de la conversion TS pour le segment du jour ($segment_file)"
        fi
    else
        log "❌ Erreur lors de la création vidéo pour le segment du jour ($temp_video)"
    fi

    # Vérifier la présence du segment avant de générer la playlist
    local playlist_file="$output_date_dir/playlist.m3u8"
    if [ -f "$segment_file" ]; then
        # Calculer la durée du segment AVANT d'écrire la playlist
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
        } > "$playlist_file"
        log "✅ Playlist générée: $playlist_file"
    else
        log "❌ Aucun segment généré, playlist non créée pour $output_date_dir"
    fi

    # Nettoyer
    rm -f "$image_list" "$temp_video"

    # Statistiques
    local total_size=$(du -sh "$output_date_dir" | cut -f1)
    log "📊 Génération terminée - Taille: $total_size, Segment unique."
    return 0
}

# Scanner et traiter tous les datasets activés avec auto-génération
auto_generate_videos() {
    log "🔄 Scan automatique des datasets pour génération vidéo..."
    
    # Lire la configuration des datasets
    local datasets_status="config/datasets-status.json"
    
    if [ ! -f "$datasets_status" ]; then
        log "❌ Fichier de statut des datasets non trouvé: $datasets_status"
        return 1
    fi
    
    # Utiliser jq si disponible, sinon parsing manuel
    if command -v jq >/dev/null 2>&1; then
        # Lire tous les datasets dans un array
        local datasets_array=()
        while IFS= read -r dataset_key; do
            if [ -n "$dataset_key" ]; then
                datasets_array+=("$dataset_key")
            fi
        done < <(jq -r '[
            (.enabled_datasets // {} | to_entries[]),
            (.disabled_datasets // {} | to_entries[]),
            (.discovered_datasets // {} | to_entries[])
        ] | .[] | select(.value.auto_download == true) | .key' "$datasets_status")
        
        # Traiter chaque dataset depuis l'array
        for dataset_key in "${datasets_array[@]}"; do
            log "🔍 Processing dataset key: '$dataset_key'"

            # Parser la clé du dataset - méthode plus robuste
            IFS='.' read -ra PARTS <<< "$dataset_key"
            local satellite="${PARTS[0]}"
            local sector="${PARTS[1]}"
            local product="${PARTS[2]}"
            local resolution="${PARTS[3]}"

            log "🎬 Traitement dataset: $satellite/$sector/$product/$resolution"

            # Lister toutes les dates où il y a des images
            local dataset_dir="$SATELLITE_DATA_DIR/$satellite/$sector/$product/$resolution"
            if [ -d "$dataset_dir" ]; then
                for date_dir in "$dataset_dir"/*/; do
                    date_str=$(basename "$date_dir")
                    # Vérifier qu'il y a des images dans ce dossier
                    if compgen -G "$date_dir*.jpg" > /dev/null; then
                        generate_satellite_video "$satellite" "$sector" "$product" "$resolution" "$date_str"
                    fi
                done
            else
                log "⚠️ Dossier dataset absent: $dataset_dir"
            fi

            # Nettoyer les images traitées si en environnement de production
            if [ "${NODE_ENV:-development}" = "production" ]; then
                log "🧹 Nettoyage des images sources en production: $dataset_dir"
                find "$dataset_dir" -name "*.jpg" -mtime +1 -delete 2>/dev/null || true
            fi
        done
    else
        log "⚠️ jq non disponible, génération manuelle nécessaire"
    fi
}

# Génération d'une séquence temporelle depuis un dataset
generate_timelapse_from_sequence() {
    local satellite="$1"
    local sector="$2"
    local product="$3"
    local resolution="$4"
    local start_date="$5"  # YYYY-MM-DD
    local end_date="$6"    # YYYY-MM-DD
    
    log "🎥 Génération timelapse: $satellite/$sector/$product/$resolution ($start_date → $end_date)"
    
    local dataset_dir="$SATELLITE_DATA_DIR/$satellite/$sector/$product/$resolution"
    local output_name="timelapse-$satellite-$sector-$product-${start_date}-to-${end_date}"
    local output_dir="$OUTPUT_DIR/$output_name"
    
    mkdir -p "$output_dir"
    
    # Collecter toutes les images dans la période
    local temp_sequence=$(mktemp)
    
    # Créer une séquence d'images pour la période donnée
    local current_date=$(date -d "$start_date" +'%Y-%m-%d')
    local end_timestamp=$(date -d "$end_date" +'%s')
    
    while [ $(date -d "$current_date" +'%s') -le $end_timestamp ]; do
        # Chercher des images pour cette date dans l'historique
        local date_pattern=$(date -d "$current_date" +'%Y%m%d')
        find "$dataset_dir" -name "*${date_pattern}*.jpg" 2>/dev/null >> "$temp_sequence"
        
        current_date=$(date -d "$current_date + 1 day" +'%Y-%m-%d')
    done
    
    # Trier les images par timestamp
    sort "$temp_sequence" > "${temp_sequence}.sorted"
    mv "${temp_sequence}.sorted" "$temp_sequence"
    
    local image_count=$(wc -l < "$temp_sequence")
    
    if [ "$image_count" -eq 0 ]; then
        log "❌ Aucune image trouvée pour la période $start_date → $end_date"
        rm -f "$temp_sequence"
        return 1
    fi
    
    log "📸 Traitement de $image_count images pour le timelapse"
    
    # Générer le timelapse avec un framerate plus élevé
    local fps=8  # Plus rapide pour un timelapse
    local segment_duration=15
    
    # Appeler la fonction de génération standard
    generate_satellite_video "$satellite" "$sector" "$product" "$resolution" "timelapse-$(date +'%Y%m%d')"
    
    rm -f "$temp_sequence"
}

# Fonction d'optimisation - compression des anciens segments
optimize_old_segments() {
    local retention_days="${1:-7}"  # Par défaut 7 jours
    
    log "🗜️ Optimisation des segments anciens (>$retention_days jours)..."
    
    find "$OUTPUT_DIR" -name "*.ts" -mtime +$retention_days | while read old_segment; do
        local compressed="${old_segment%.ts}.compressed.ts"
        
        # Recompresser avec une qualité moindre
        if ffmpeg -y -i "$old_segment" -c:v libx264 -crf 28 -c:a copy "$compressed" 2>/dev/null; then
            local old_size=$(stat -f%z "$old_segment" 2>/dev/null || stat -c%s "$old_segment" 2>/dev/null)
            local new_size=$(stat -f%z "$compressed" 2>/dev/null || stat -c%s "$compressed" 2>/dev/null)
            local saved=$((old_size - new_size))
            
            if [ $saved -gt 0 ]; then
                mv "$compressed" "$old_segment"
                log "✅ Segment optimisé: $(basename "$old_segment") - Économie: $((saved / 1024))KB"
            else
                rm -f "$compressed"
            fi
        fi
    done
}

# ================================
# INTERFACE CLI
# ================================

show_video_help() {
    echo "🎬 Génération automatique de vidéos satellitaires"
    echo ""
    echo "Commandes:"
    echo "  auto                   - Génération automatique des datasets activés"
    echo "  generate SATELLITE SECTOR PRODUCT RESOLUTION DATE"
    echo "                         - Générer une vidéo pour une date spécifique"
    echo "  timelapse SATELLITE SECTOR PRODUCT RESOLUTION START_DATE END_DATE"
    echo "                         - Générer un timelapse pour une période"
    echo "  optimize [DAYS]        - Optimiser les anciens segments (défaut: 7 jours)"
    echo ""
    echo "Exemples:"
    echo "  $0 auto"
    echo "  $0 generate GOES18 hi GEOCOLOR 1200x1200 2025-07-29"
    echo "  $0 timelapse GOES18 hi GEOCOLOR 1200x1200 2025-07-20 2025-07-29"
    echo "  $0 optimize 14"
}

# Point d'entrée CLI
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        "auto")
            auto_generate_videos
            ;;
        "generate")
            if [ $# -ge 6 ]; then
                generate_satellite_video "$2" "$3" "$4" "$5" "$6"
            else
                echo "❌ Usage: $0 generate SATELLITE SECTOR PRODUCT RESOLUTION DATE"
                exit 1
            fi
            ;;
        "timelapse")
            if [ $# -ge 7 ]; then
                generate_timelapse_from_sequence "$2" "$3" "$4" "$5" "$6" "$7"
            else
                echo "❌ Usage: $0 timelapse SATELLITE SECTOR PRODUCT RESOLUTION START_DATE END_DATE"
                exit 1
            fi
            ;;
        "optimize")
            optimize_old_segments "${2:-7}"
            ;;
        "help"|*)
            show_video_help
            ;;
    esac
fi
