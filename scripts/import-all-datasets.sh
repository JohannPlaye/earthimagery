#!/bin/bash

# =============================================================================
# IMPORT-ALL-DATASETS.SH - Import automatique de tous les datasets NOAA disponibles
# =============================================================================
# Ce script découvre automatiquement tous les datasets disponibles sur la NOAA
# et les ajoute à la configuration de l'application
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_ROOT/config/datasets-status.json"
TRACKING_FILE="$PROJECT_ROOT/config/download-tracking.json"

# Fonction pour découvrir et importer tous les datasets
import_all_datasets() {
    echo "🔍 Découverte et import de tous les datasets NOAA disponibles..."
    
    # Sauvegarder la configuration actuelle
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        echo "📋 Configuration sauvegardée"
    fi
    
    # Initialiser la nouvelle configuration
    cat > "$CONFIG_FILE" << 'EOF'
{
  "enabled_datasets": {},
  "disabled_datasets": {},
  "discovered_datasets": {},
  "last_discovery": null,
  "last_updated": null
}
EOF
    
    # Découvrir les datasets pour chaque satellite
    local satellites=("GOES18" "GOES16")
    local total_discovered=0
    
    for satellite in "${satellites[@]}"; do
        echo "🛰️ Découverte $satellite..."
        
        # Obtenir la liste des secteurs
        local sectors=$(curl -k -L -s --max-time 15 "https://cdn.star.nesdis.noaa.gov/$satellite/ABI/SECTOR/" 2>/dev/null | \
                       grep -o 'href="[^"]*/"' | sed 's/href="//;s/"//' | grep -v '\.\.' | sort -u)
        
        if [ -n "$sectors" ]; then
            while read -r sector; do
                if [ -n "$sector" ]; then
                    sector=$(echo "$sector" | tr -d '/')
                    echo "  📡 Test secteur: $sector"
                    
                    # Tester différents produits et résolutions
                    local products=("GEOCOLOR" "FireTemperature" "Sandwich")
                    local resolutions=("300x300" "600x600" "1000x1000" "1200x1200" "1808x1808" "2400x2400")
                    
                    for product in "${products[@]}"; do
                        # Tester si le produit existe pour ce secteur
                        local product_url="https://cdn.star.nesdis.noaa.gov/$satellite/ABI/SECTOR/$sector/$product/"
                        local content=$(curl -k -L -s --max-time 10 --connect-timeout 5 "$product_url" 2>/dev/null || echo "")
                        
                        if echo "$content" | grep -q "Index of"; then
                            echo "    🎯 Produit $product disponible"
                            
                            for resolution in "${resolutions[@]}"; do
                                if echo "$content" | grep -q "href.*${resolution}\.jpg"; then
                                    local dataset_key="${satellite}.${sector}.${product}.${resolution}"
                                    echo "      ✅ $dataset_key"
                                    
                                    # Ajouter à la configuration comme disabled par défaut
                                    jq --arg key "$dataset_key" \
                                       --arg satellite "$satellite" \
                                       --arg sector "$sector" \
                                       --arg product "$product" \
                                       --arg resolution "$resolution" \
                                       --arg timestamp "$(date -Iseconds)" \
                                       '.discovered_datasets[$key] = {
                                         "satellite": $satellite,
                                         "sector": $sector,
                                         "product": $product,
                                         "resolution": $resolution,
                                         "auto_download": false,
                                         "discovered_date": $timestamp,
                                         "status": "available",
                                         "description": "\($satellite) \($sector | ascii_upcase) \($product) \($resolution)"
                                       }' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
                                    
                                    total_discovered=$((total_discovered + 1))
                                fi
                            done
                        fi
                    done
                fi
            done <<< "$sectors"
        fi
    done
    
    # Mettre à jour les métadonnées
    jq --arg timestamp "$(date -Iseconds)" \
       --argjson total "$total_discovered" \
       '.last_discovery = $timestamp | .last_updated = $timestamp | .total_discovered = $total' \
       "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    
    echo ""
    echo "🎉 Découverte terminée !"
    echo "📊 Total datasets découverts: $total_discovered"
    echo ""
    echo "💡 Pour activer un dataset, utilisez:"
    echo "   bash scripts/dataset-toggle.sh enable SATELLITE SECTOR PRODUCT RESOLUTION"
    echo ""
    echo "🌐 Ou utilisez l'interface web à http://localhost:10000"
}

# Fonction pour activer les datasets recommandés
activate_recommended() {
    echo "🚀 Activation des datasets recommandés..."
    
    # Datasets recommandés (variété géographique et qualité)
    local recommended=(
        "GOES18.hi.GEOCOLOR.600x600"      # Hawaii - bon pour les tests
        "GOES18.psw.GEOCOLOR.1000x1000"   # Pacific Southwest 
        "GOES18.pnw.GEOCOLOR.1000x1000"   # Pacific Northwest
        "GOES18.cak.GEOCOLOR.600x600"     # Central Alaska
    )
    
    for dataset in "${recommended[@]}"; do
        IFS='.' read -r satellite sector product resolution <<< "$dataset"
        echo "  ✅ Activation: $dataset"
        
        # Déplacer de discovered vers enabled
        jq --arg key "$dataset" \
           '.enabled_datasets[$key] = .discovered_datasets[$key] | 
            .enabled_datasets[$key].auto_download = true |
            del(.discovered_datasets[$key])' \
           "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    done
    
    echo "✅ Datasets recommandés activés"
}

# Fonction principale
main() {
    echo ""
    echo "🌍 EarthImagery - Import automatique des datasets NOAA"
    echo "======================================================"
    echo ""
    
    case "${1:-discover}" in
        "discover")
            import_all_datasets
            ;;
        "recommended")
            import_all_datasets
            activate_recommended
            ;;
        "help")
            echo "Usage: $0 [discover|recommended|help]"
            echo ""
            echo "  discover     - Découvre tous les datasets disponibles (défaut)"
            echo "  recommended  - Découvre et active les datasets recommandés"
            echo "  help         - Affiche cette aide"
            ;;
        *)
            echo "❌ Option inconnue: $1"
            echo "Utilisez: $0 help"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
