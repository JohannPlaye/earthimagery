#!/bin/bash

# Script de test complet end-to-end pour EarthImagery
# Teste l'ensemble de la chaîne : téléchargement → traitement → génération HLS → vérification

set -e  # Arrêt en cas d'erreur

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction de logging avec couleurs
log() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] $message${NC}"
}

# Variables de test
TEST_START_DATE="2025-01-01"
TEST_END_DATE="2025-01-10"
TEST_DURATION="10 derniers jours"

log $BLUE "🚀 DÉBUT DU TEST COMPLET EARTHIMAGERY 🚀"
log $BLUE "=============================================="
log $YELLOW "Période de test: $TEST_DURATION ($TEST_START_DATE à $TEST_END_DATE)"
log $YELLOW "Mode: Production authentique avec téléchargement de TOUTES les images disponibles"
echo

# Phase 1: Nettoyage préparatoire
log $BLUE "🧹 Phase 1/5: Nettoyage préparatoire..."
if [ -d "public/data/images" ]; then
    rm -rf public/data/images/*
    log $GREEN "✅ Nettoyage des images existantes"
else
    mkdir -p public/data/images
    log $GREEN "✅ Création du dossier images"
fi

if [ -d "public/data/hls" ]; then
    rm -rf public/data/hls/*
    log $GREEN "✅ Nettoyage des playlists HLS existantes"
else
    mkdir -p public/data/hls
    log $GREEN "✅ Création du dossier HLS"
fi
echo

# Phase 2: Téléchargement avec TOUTES les images disponibles
log $BLUE "📥 Phase 2/5: Téléchargement des données satellitaires..."
log $YELLOW "Configuration: Téléchargement de TOUTES les images disponibles par jour (jusqu'à 150 images/jour)"
log $YELLOW "Note: Les satellites GOES produisent ~96-144 images par jour (1 image toutes les 10-15 min)"

# Utiliser 150 images/jour pour capturer toutes les images disponibles
# sync [PROFONDEUR_JOURS] [IMAGES_PAR_JOUR]
./scripts/smart-fetch.sh sync 10 150

if [ $? -eq 0 ]; then
    log $GREEN "✅ Téléchargement terminé avec succès"
    
    # Compter les images téléchargées
    if [ -d "public/data/images" ]; then
        image_count=$(find public/data/images -name "*.jpg" -o -name "*.png" | wc -l)
        log $GREEN "📊 Images téléchargées: $image_count"
        
        # Afficher le détail par dataset
        for dataset_dir in public/data/images/*/*/*/*; do
            if [ -d "$dataset_dir" ]; then
                dataset_name=$(basename "$(dirname "$(dirname "$(dirname "$(dirname "$dataset_dir")")")")")/$(basename "$(dirname "$(dirname "$(dirname "$dataset_dir")")")")/$(basename "$(dirname "$(dirname "$dataset_dir")")")/$(basename "$(dirname "$dataset_dir")")
                date_folder=$(basename "$dataset_dir")
                day_count=$(find "$dataset_dir" -name "*.jpg" -o -name "*.png" | wc -l)
                log $YELLOW "  📅 $date_folder: $day_count images"
            fi
        done
    fi
else
    log $RED "❌ Erreur lors du téléchargement"
    exit 1
fi
echo

# Phase 3: Génération des vidéos avec 24fps (standard production)
log $BLUE "🎬 Phase 3/5: Génération des vidéos (24fps standard)..."
log $YELLOW "Configuration: 24fps pour lecture fluide, indépendamment du nombre d'images source"

./scripts/generate-satellite-videos.sh

if [ $? -eq 0 ]; then
    log $GREEN "✅ Génération vidéo terminée avec succès"
    
    # Vérifier les vidéos générées
    if [ -d "public/data/videos" ]; then
        video_count=$(find public/data/videos -name "*.mp4" | wc -l)
        log $GREEN "📹 Vidéos générées: $video_count"
    fi
else
    log $RED "❌ Erreur lors de la génération vidéo"
    exit 1
fi
echo

# Phase 4: Génération des playlists HLS
log $BLUE "📡 Phase 4/5: Génération des playlists HLS..."

# Vérifier que nous avons des vidéos à traiter
if [ ! -d "public/data/videos" ] || [ -z "$(find public/data/videos -name "*.mp4" | head -1)" ]; then
    log $RED "❌ Aucune vidéo trouvée pour générer les playlists HLS"
    exit 1
fi

# Traiter chaque vidéo pour créer les playlists HLS
playlist_count=0
for video_file in public/data/videos/**/*.mp4; do
    if [ -f "$video_file" ]; then
        # Extraire le nom du dataset et de la date
        relative_path="${video_file#public/data/videos/}"
        dataset_path=$(dirname "$relative_path")
        video_name=$(basename "$video_file" .mp4)
        
        # Créer le dossier HLS correspondant
        hls_dir="public/data/hls/$dataset_path"
        mkdir -p "$hls_dir"
        
        # Générer la playlist HLS
        ffmpeg -i "$video_file" \
               -c:v libx264 -c:a aac \
               -hls_time 2 \
               -hls_list_size 0 \
               -f hls "$hls_dir/${video_name}.m3u8" \
               -y -loglevel error
        
        if [ $? -eq 0 ]; then
            playlist_count=$((playlist_count + 1))
            log $GREEN "  ✓ Playlist créée: $dataset_path/${video_name}.m3u8"
        else
            log $RED "  ✗ Échec playlist: $dataset_path/${video_name}.m3u8"
        fi
    fi
done

log $GREEN "📺 Playlists HLS générées: $playlist_count"
echo

# Phase 5: Vérification et rapport final
log $BLUE "📋 Phase 5/5: Vérification et rapport final..."

# Compter tous les éléments générés
total_images=$(find public/data/images -name "*.jpg" -o -name "*.png" 2>/dev/null | wc -l)
total_videos=$(find public/data/videos -name "*.mp4" 2>/dev/null | wc -l)
total_playlists=$(find public/data/hls -name "*.m3u8" 2>/dev/null | wc -l)
total_segments=$(find public/data/hls -name "*.ts" 2>/dev/null | wc -l)

# Calculer les tailles
if command -v du &> /dev/null; then
    images_size=$(du -sh public/data/images 2>/dev/null | cut -f1 || echo "N/A")
    videos_size=$(du -sh public/data/videos 2>/dev/null | cut -f1 || echo "N/A")
    hls_size=$(du -sh public/data/hls 2>/dev/null | cut -f1 || echo "N/A")
else
    images_size="N/A"
    videos_size="N/A"
    hls_size="N/A"
fi

# Rapport final
log $GREEN "🎉 TEST COMPLET TERMINÉ AVEC SUCCÈS 🎉"
log $GREEN "=========================================="
echo
log $BLUE "📊 RAPPORT FINAL:"
log $YELLOW "  📸 Images téléchargées: $total_images (Taille: $images_size)"
log $YELLOW "  🎬 Vidéos générées: $total_videos (Taille: $videos_size)"  
log $YELLOW "  📺 Playlists HLS: $total_playlists (Taille: $hls_size)"
log $YELLOW "  🧩 Segments vidéo: $total_segments"
echo

# Vérification de cohérence
if [ $total_images -gt 0 ] && [ $total_videos -gt 0 ] && [ $total_playlists -gt 0 ]; then
    log $GREEN "✅ Pipeline complet fonctionnel: Images → Vidéos → HLS"
    
    # Instructions pour tester l'interface web
    echo
    log $BLUE "🌐 INSTRUCTIONS POUR TESTER L'INTERFACE WEB:"
    log $YELLOW "1. Démarrer le serveur de développement:"
    log $YELLOW "   npm run dev"
    log $YELLOW ""
    log $YELLOW "2. Ouvrir http://localhost:3000 dans votre navigateur"
    log $YELLOW ""
    log $YELLOW "3. Vérifier que les datasets sont listés et les vidéos se lancent"
    echo
    
    exit 0
else
    log $RED "❌ Pipeline incomplet détecté"
    if [ $total_images -eq 0 ]; then
        log $RED "  - Aucune image téléchargée"
    fi
    if [ $total_videos -eq 0 ]; then
        log $RED "  - Aucune vidéo générée"
    fi
    if [ $total_playlists -eq 0 ]; then
        log $RED "  - Aucune playlist HLS créée"
    fi
    exit 1
fi
