#!/bin/bash

# =============================================================================
# TEST-HELPER.SH - Script d'aide pour tester testcomplet.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🧪 EarthImagery - Test Helper"
echo "=============================="
echo ""

# Fonction pour afficher l'état actuel
show_current_state() {
    echo "📊 État actuel du système:"
    echo ""
    
    local images_count=$(find "$PROJECT_ROOT/public/data" -name "*.jpg" -type f 2>/dev/null | wc -l)
    local videos_count=$(find "$PROJECT_ROOT/public/data" -name "*.mp4" -type f 2>/dev/null | wc -l)
    local playlists_count=$(find "$PROJECT_ROOT/public/data/hls" -name "playlist.m3u8" -type f 2>/dev/null | wc -l)
    
    echo "🖼️  Images: $images_count"
    echo "🎬 Vidéos: $videos_count"
    echo "📋 Playlists: $playlists_count"
    echo ""
    
    if [ -f "$PROJECT_ROOT/config/download-tracking.json" ]; then
        echo "📝 Datasets actifs:"
        jq -r '.tracking | to_entries[] | select(.value.dataset_info.enabled == true) | "  - " + .key' "$PROJECT_ROOT/config/download-tracking.json" 2>/dev/null || echo "  Erreur lors de la lecture du fichier de tracking"
    else
        echo "⚠️  Fichier de tracking manquant"
    fi
    echo ""
}

# Menu principal
main_menu() {
    while true; do
        show_current_state
        
        echo "Que voulez-vous faire ?"
        echo "1) Exécuter le test complet (testcomplet.sh)"
        echo "2) Nettoyer seulement les données"
        echo "3) Télécharger 1 jour de test"
        echo "4) Vérifier les dépendances"
        echo "5) Voir les logs récents"
        echo "6) Quitter"
        echo ""
        
        read -p "Votre choix [1-6]: " choice
        echo ""
        
        case $choice in
            1)
                echo "🚀 Lancement du test complet..."
                bash "$SCRIPT_DIR/testcomplet.sh"
                ;;
            2)
                echo "🧹 Nettoyage des données..."
                rm -rf "$PROJECT_ROOT/public/data/images"/* 2>/dev/null || true
                rm -rf "$PROJECT_ROOT/public/data/videos"/* 2>/dev/null || true
                rm -rf "$PROJECT_ROOT/public/data/hls"/* 2>/dev/null || true
                echo "✅ Nettoyage terminé"
                ;;
            3)
                echo "📥 Téléchargement d'un jour de test..."
                local test_date=$(date -d "1 day ago" +%Y-%m-%d)
                bash "$SCRIPT_DIR/unified-download.sh" \
                    --satellite "GOES18" \
                    --sector "hi" \
                    --product "GEOCOLOR" \
                    --resolution "600x600" \
                    --date "$test_date" \
                    --max-images 6
                echo "✅ Test de téléchargement terminé"
                ;;
            4)
                echo "🔍 Vérification des dépendances..."
                for cmd in jq ffmpeg curl; do
                    if command -v $cmd &> /dev/null; then
                        echo "✅ $cmd: installé"
                    else
                        echo "❌ $cmd: manquant"
                    fi
                done
                ;;
            5)
                echo "📋 Logs récents:"
                find "$PROJECT_ROOT/public/data/logs" -name "*.log" -type f -mtime -1 2>/dev/null | head -3 | while read -r log_file; do
                    echo ""
                    echo "📄 $(basename "$log_file"):"
                    tail -10 "$log_file"
                done
                ;;
            6)
                echo "👋 Au revoir !"
                exit 0
                ;;
            *)
                echo "❌ Choix invalide"
                ;;
        esac
        
        echo ""
        read -p "Appuyez sur Entrée pour continuer..."
        clear
    done
}

# Point d'entrée
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    clear
    main_menu
fi
