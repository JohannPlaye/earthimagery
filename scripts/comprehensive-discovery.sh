#!/bin/bash

# =============================================================================
# COMPREHENSIVE-DISCOVERY.SH - Découverte complète des datasets GOES
# =============================================================================
# Ce script explore systématiquement tous les satellites GOES, secteurs, 
# produits et résolutions disponibles sur le serveur NOAA
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_ROOT/config/datasets-status.json"
DISCOVERY_LOG="$PROJECT_ROOT/discovery-$(date +%Y%m%d_%H%M%S).log"

# Configuration de découverte
BASE_URL="https://cdn.star.nesdis.noaa.gov"
SATELLITES=("GOES16" "GOES17" "GOES18" "GOES19")
STRUCTURES=("SECTOR" "CONUS" "FD" "MESO")
PRODUCTS=("GEOCOLOR" "FireTemperature" "Sandwich" "AirMass" "WaterVapor")

# Fonction de logging
log() {
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$DISCOVERY_LOG"
}

# Fonction pour tester une URL avec timeout
test_url() {
    local url="$1"
    curl -k -L -s --max-time 8 --connect-timeout 3 "$url" 2>/dev/null || echo ""
}

# Fonction pour extraire les résolutions d'une page
extract_resolutions() {
    local content="$1"
    echo "$content" | grep -o '[0-9]\+x[0-9]\+\.jpg' | sed 's/\.jpg$//' | sort -u
}

# Fonction pour découvrir les datasets d'un satellite
discover_satellite() {
    local satellite="$1"
    log "🛰️ === Découverte $satellite ==="
    
    local satellite_url="$BASE_URL/$satellite/ABI"
    local available_structures=$(test_url "$satellite_url/" | grep -o 'href="[^"]*/"' | sed 's/href="//;s/"//' | grep -v '\.\.' | sort)
    
    if [ -z "$available_structures" ]; then
        log "❌ $satellite - Aucune structure ABI trouvée"
        return
    fi
    
    log "📡 $satellite structures disponibles: $(echo "$available_structures" | tr '\n' ' ')"
    
    local total_found=0
    
    while read -r structure; do
        if [ -n "$structure" ]; then
            structure=$(echo "$structure" | tr -d '/')
            log "📂 Test structure: $satellite/$structure"
            
            case "$structure" in
                "SECTOR")
                    # Découvrir les secteurs
                    local sectors=$(test_url "$satellite_url/SECTOR/" | grep -o 'href="[^"]*/"' | sed 's/href="//;s/"//' | grep -v '\.\.' | sort)
                    
                    while read -r sector; do
                        if [ -n "$sector" ]; then
                            sector=$(echo "$sector" | tr -d '/')
                            local found_datasets=$(discover_sector "$satellite" "$sector")
                            total_found=$((total_found + found_datasets))
                        fi
                    done <<< "$sectors"
                    ;;
                "CONUS"|"FD"|"MESO")
                    # Découvrir les produits pour cette structure
                    local found_datasets=$(discover_structure "$satellite" "$structure")
                    total_found=$((total_found + found_datasets))
                    ;;
            esac
        fi
    done <<< "$available_structures"
    
    log "✅ $satellite - Total datasets découverts: $total_found"
    echo $total_found
}

# Fonction pour découvrir les datasets d'un secteur
discover_sector() {
    local satellite="$1"
    local sector="$2"
    
    local found=0
    
    for product in "${PRODUCTS[@]}"; do
        local product_url="$BASE_URL/$satellite/ABI/SECTOR/$sector/$product/"
        local content=$(test_url "$product_url")
        
        if echo "$content" | grep -q "Index of"; then
            local resolutions=$(extract_resolutions "$content")
            
            if [ -n "$resolutions" ]; then
                log "  ✅ $satellite.SECTOR.$sector.$product"
                
                while read -r resolution; do
                    if [ -n "$resolution" ]; then
                        local dataset_key="$satellite.$sector.$product.$resolution"
                        log "    📐 $dataset_key"
                        
                        # Enregistrer le dataset découvert
                        register_dataset "$dataset_key" "$satellite" "$sector" "$product" "$resolution" "SECTOR"
                        found=$((found + 1))
                    fi
                done <<< "$resolutions"
            fi
        fi
    done
    
    return $found
}

# Fonction pour découvrir les datasets d'une structure (CONUS/FD/MESO)
discover_structure() {
    local satellite="$1"
    local structure="$2"
    
    local found=0
    
    for product in "${PRODUCTS[@]}"; do
        local product_url="$BASE_URL/$satellite/ABI/$structure/$product/"
        local content=$(test_url "$product_url")
        
        if echo "$content" | grep -q "Index of"; then
            local resolutions=$(extract_resolutions "$content")
            
            if [ -n "$resolutions" ]; then
                log "  ✅ $satellite.$structure.$product"
                
                while read -r resolution; do
                    if [ -n "$resolution" ]; then
                        local dataset_key="$satellite.$structure.$product.$resolution"
                        log "    📐 $dataset_key"
                        
                        # Enregistrer le dataset découvert
                        register_dataset "$dataset_key" "$satellite" "$structure" "$product" "$resolution" "$structure"
                        found=$((found + 1))
                    fi
                done <<< "$resolutions"
            fi
        fi
    done
    
    return $found
}

# Fonction pour enregistrer un dataset découvert
register_dataset() {
    local dataset_key="$1"
    local satellite="$2"
    local sector="$3"
    local product="$4"
    local resolution="$5"
    local structure="$6"
    
    # Description lisible
    local description="$satellite $sector $product $resolution"
    if [ "$structure" != "SECTOR" ]; then
        description="$satellite $structure $product $resolution"
    fi
    
    # Ajouter au fichier de configuration s'il n'existe pas déjà
    if ! jq -e ".discovered_datasets[\"$dataset_key\"]" "$CONFIG_FILE" >/dev/null 2>&1; then
        jq --arg key "$dataset_key" \
           --arg satellite "$satellite" \
           --arg sector "$sector" \
           --arg product "$product" \
           --arg resolution "$resolution" \
           --arg description "$description" \
           --arg timestamp "$(date -Iseconds)" \
           '.discovered_datasets[$key] = {
             "satellite": $satellite,
             "sector": $sector,
             "product": $product,
             "resolution": $resolution,
             "auto_download": false,
             "status": "available",
             "description": $description,
             "discovered_date": $timestamp
           }' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    fi
}

# Fonction principale
main() {
    log "🌍 === DÉCOUVERTE COMPLÈTE DES DATASETS GOES ==="
    log "Base URL: $BASE_URL"
    log "Satellites à explorer: ${SATELLITES[*]}"
    log "Produits à chercher: ${PRODUCTS[*]}"
    log ""
    
    # Sauvegarder la configuration actuelle
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        log "📋 Configuration sauvegardée"
    fi
    
    local total_discovered=0
    
    # Découvrir chaque satellite
    for satellite in "${SATELLITES[@]}"; do
        local satellite_found=$(discover_satellite "$satellite")
        total_discovered=$((total_discovered + satellite_found))
    done
    
    # Mettre à jour les métadonnées
    jq --arg timestamp "$(date -Iseconds)" \
       --argjson total "$total_discovered" \
       '.last_discovery = $timestamp | .total_discovered = $total' \
       "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    
    log ""
    log "🎉 === DÉCOUVERTE TERMINÉE ==="
    log "📊 Total datasets découverts: $total_discovered"
    log "📄 Log détaillé: $DISCOVERY_LOG"
    log "📁 Configuration mise à jour: $CONFIG_FILE"
    
    # Afficher un résumé
    log ""
    log "📋 Résumé par satellite:"
    jq -r '.discovered_datasets | to_entries | group_by(.value.satellite) | .[] | "\(.[0].value.satellite): \(length) datasets"' "$CONFIG_FILE" | while read -r line; do
        log "  $line"
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
