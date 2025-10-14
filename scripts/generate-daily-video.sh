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
VIDEO_CRF=19
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
                # Structure EUMETSAT: EUMETSAT/satellite/sector/product/resolution/date
                echo "$DATA_ROOT_PATH/EUMETSAT/$satellite/$sector/$product/$resolution/$date"
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

# Fonction pour vérifier si un dataset est virtuel et récupérer ses propriétés
get_virtual_dataset_info() {
    local dataset_key="$1"
    local config_file="$SCRIPT_DIR/../config/datasets-status.json"
    
    if [ ! -f "$config_file" ]; then
        echo "null"
        return 1
    fi
    
    # Vérifier si le dataset est virtuel et récupérer ses informations
    local virtual_info=$(jq -r --arg key "$dataset_key" '
        .enabled_datasets[$key] | 
        if .virtual_dataset == true then 
            {
                "is_virtual": true,
                "parent_dataset": .parent_dataset,
                "zone": .zone,
                "resolution": .resolution
            }
        else 
            {"is_virtual": false}
        end
    ' "$config_file" 2>/dev/null)
    
    echo "$virtual_info"
}

# Fonction pour générer une vidéo pour un dataset
generate_video_for_dataset() {
    local dataset_key="$1"
    local target_date="$2"
    
    log "🎬 Génération vidéo pour $dataset_key - $target_date"
    
    # Vérifier si c'est un dataset virtuel
    local virtual_info=$(get_virtual_dataset_info "$dataset_key")
    local is_virtual=$(echo "$virtual_info" | jq -r '.is_virtual // false')
    
    local images_dir=""
    local source_dataset_key="$dataset_key"
    
    if [ "$is_virtual" = "true" ]; then
        # Dataset virtuel : utiliser le parent dataset pour trouver les images
        local parent_dataset=$(echo "$virtual_info" | jq -r '.parent_dataset // ""')
        local zone_array=$(echo "$virtual_info" | jq -r '.zone // []')
        local target_resolution=$(echo "$virtual_info" | jq -r '.resolution // ""')
        
        if [ -z "$parent_dataset" ] || [ "$zone_array" = "[]" ]; then
            log "❌ Dataset virtuel mal configuré: parent_dataset ou zone manquant"
            return 1
        fi
        
        log "🔄 Dataset virtuel détecté - Parent: $parent_dataset"
        log "📐 Zone crop: $zone_array → Résolution finale: $target_resolution"
        
        source_dataset_key="$parent_dataset"
        images_dir=$(find_images_directory "$parent_dataset" "$target_date")
    else
        # Dataset normal
        images_dir=$(find_images_directory "$dataset_key" "$target_date")
    fi
    
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

    # Détection automatique de la résolution et du matériel pour adapter les paramètres FFmpeg
    local image_resolution="standard"
    local ffmpeg_threads=2
    local video_preset="medium"
    local video_crf="$VIDEO_CRF"  # Maintenir la qualité originale
    
    # Détection Raspberry Pi pour optimisations PERFORMANCE UNIQUEMENT (pas de qualité)
    local is_raspberry_pi=false
    if [ -f /proc/cpuinfo ] && grep -q "BCM283[0-9]" /proc/cpuinfo; then
        is_raspberry_pi=true
        log "🍓 Raspberry Pi détecté: optimisations performance (qualité préservée)"
    fi
    
    if [ "$is_raspberry_pi" = true ]; then
        # Optimisations Raspberry Pi 3B+ : SEULEMENT threads et preset (qualité identique)
        if [[ "$dataset_key" == *"4000x4000"* ]]; then
            image_resolution="ultra_high"
            ffmpeg_threads=1  # Un seul thread pour éviter la saturation
            video_preset="ultrafast"  # Plus rapide mais même qualité
            # video_crf reste inchangé = même qualité
            log "🍓 Raspberry Pi ultra-haute résolution (4000x4000): 1 thread, preset ultrafast, CRF $video_crf (qualité préservée)"
        elif [[ "$dataset_key" == *"2000x2000"* ]]; then
            image_resolution="high"
            ffmpeg_threads=1  # Un seul thread même pour 2K
            video_preset="ultrafast"
            # video_crf reste inchangé = même qualité
            log "🍓 Raspberry Pi haute résolution (2000x2000): 1 thread, preset ultrafast, CRF $video_crf (qualité préservée)"
        else
            # Résolution standard sur Raspberry Pi
            ffmpeg_threads=1
            video_preset="ultrafast"
            # video_crf reste inchangé = même qualité
            log "🍓 Raspberry Pi résolution standard: 1 thread, preset ultrafast, CRF $video_crf (qualité préservée)"
        fi
    else
        # Configuration standard pour serveurs/PC
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
    fi

    # Construction des filtres vidéo selon le type de dataset
    local video_filters="pad=ceil(iw/2)*2:ceil(ih/2)*2"
    
    if [ "$is_virtual" = "true" ]; then
        # Dataset virtuel : ajouter crop et redimensionnement
        local zone_array=$(echo "$virtual_info" | jq -r '.zone // []')
        local target_resolution=$(echo "$virtual_info" | jq -r '.resolution // ""')
        
        # Extraire les coordonnées du crop [x1,y1,x2,y2]
        local x1=$(echo "$zone_array" | jq -r '.[0] // 0')
        local y1=$(echo "$zone_array" | jq -r '.[1] // 0')
        local x2=$(echo "$zone_array" | jq -r '.[2] // 0')
        local y2=$(echo "$zone_array" | jq -r '.[3] // 0')
        
        # Calculer largeur et hauteur du crop
        local crop_width=$((x2 - x1))
        local crop_height=$((y2 - y1))
        
        # Extraire la résolution finale
        local final_width=$(echo "$target_resolution" | cut -d'x' -f1)
        local final_height=$(echo "$target_resolution" | cut -d'x' -f2)
        
        if [ "$crop_width" -gt 0 ] && [ "$crop_height" -gt 0 ] && [ "$final_width" -gt 0 ] && [ "$final_height" -gt 0 ]; then
            video_filters="crop=${crop_width}:${crop_height}:${x1}:${y1},scale=${final_width}:${final_height},pad=ceil(iw/2)*2:ceil(ih/2)*2"
            log "🎯 Filtres vidéo virtuels: crop(${crop_width}x${crop_height} @ ${x1},${y1}) → scale(${final_width}x${final_height})"
        else
            log "⚠️ Paramètres de crop invalides, utilisation des filtres standard"
        fi
    fi

    # Génération vidéo MP4 temporaire
    log "🔄 Génération MP4 temporaire..."
    local temp_video="/tmp/temp-$dataset_key-$target_date.mp4"
    local success=false
    
    # Détection du source pour adapter la méthode FFmpeg
    local use_pattern_input=false
    # Pour EUMETSAT (MTG ou MSG), utiliser le pattern glob
    if [[ "$dataset_key" == MTG.* || "$dataset_key" == MSG.* ]]; then
        use_pattern_input=true
        log "📊 Détection EUMETSAT (MTG/MSG): utilisation du pattern glob pour les images PNG"
    fi
    
    if [ "$use_pattern_input" = true ]; then
        # Méthode pattern pour EUMETSAT avec format pixel correct
        if ffmpeg -hide_banner -y \
            -framerate "$VIDEO_FPS" \
            -pattern_type glob \
            -i "$(dirname "$first_image")/*.png" \
            -r "$VIDEO_FPS" \
            -threads "$ffmpeg_threads" \
            -vf "$video_filters" \
            -c:v libx264 \
            -crf "$video_crf" \
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
            # Pour les images 4000x4000 : même CRF, optimisations performance uniquement
            concat_cmd="ffmpeg -hide_banner -y \
                -f concat \
                -safe 0 \
                -threads $ffmpeg_threads \
                -i <(sed \"s/^/file '/\" \"$images_list\" | sed \"s/\$/'/\" ) \
                -r $VIDEO_FPS \
                -vf \"$video_filters\" \
                -c:v libx264 \
                -crf $video_crf \
                -preset $video_preset \
                -pix_fmt yuv420p \
                -color_range tv \
                -colorspace bt709 \
                -movflags +faststart \
                -max_muxing_queue_size 1024 \
                \"$temp_video\""
            log "🔧 Optimisation ultra-haute résolution: CRF $video_crf (qualité préservée), preset $video_preset"
        else
            # Méthode standard pour les autres résolutions
            concat_cmd="ffmpeg -hide_banner -y \
                -f concat \
                -safe 0 \
                -threads $ffmpeg_threads \
                -i <(sed \"s/^/file '/\" \"$images_list\" | sed \"s/\$/'/\" ) \
                -r $VIDEO_FPS \
                -vf \"$video_filters\" \
                -c:v libx264 \
                -crf $video_crf \
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
