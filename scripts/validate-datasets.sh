#!/bin/bash

# =============================================================================
# VALIDATE-DATASETS.SH - Validation de la disponibilité des datasets
# =============================================================================
# Ce script teste la disponibilité de tous les datasets configurés et 
# met à jour leur statut (available/unavailable) dans la configuration
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_ROOT/config/datasets-status.json"
TRACKING_FILE="$PROJECT_ROOT/config/download-tracking.json"

# Fonction pour tester la disponibilité d'un dataset
test_dataset_availability() {
    local satellite="$1"
    local sector="$2" 
    local product="$3"
    local resolution="$4"
    
    local url="https://cdn.star.nesdis.noaa.gov/$satellite/ABI/SECTOR/$sector/$product/"
    echo "    🧪 Test URL: $url (résolution: $resolution)"
    
    # Test de connexion avec timeout de 10 secondes et ignore SSL
    local content=$(curl -k -L -s --max-time 10 --connect-timeout 5 "$url" 2>/dev/null)
    local matches=$(echo "$content" | grep "href.*${resolution}\.jpg" | wc -l)
    echo "    📊 Contenu reçu: $(echo "$content" | wc -l) lignes, matches: $matches"
    
    if [ "$matches" -gt 0 ]; then
        echo "    ✅ Trouvé $matches fichiers ${resolution}"
        return 0  # Disponible
    else
        echo "    ❌ Aucun fichier ${resolution} trouvé"
        echo "    🔍 Premier échantillon du contenu:"
        echo "$content" | head -3 | sed 's/^/      /'
        return 1  # Indisponible
    fi
}

# Fonction pour découvrir les datasets disponibles
discover_available_datasets() {
    echo "🔍 Découverte des datasets disponibles..."
    
    local satellites=("GOES18" "GOES16")
    local available_datasets=()
    
    for satellite in "${satellites[@]}"; do
        echo "  🛰️ Test $satellite..."
        
        # Obtenir la liste des secteurs pour ce satellite
        local sectors=$(curl -k -L -s --max-time 10 "https://cdn.star.nesdis.noaa.gov/$satellite/ABI/SECTOR/" 2>/dev/null | \
                       grep -o 'href="[^"]*/"' | sed 's/href="//;s/"//' | grep -v '\.\.' | tr '[:upper:]' '[:lower:]' | sort -u)
        
        if [ -n "$sectors" ]; then
            while read -r sector; do
                if [ -n "$sector" ]; then
                    # Tester GEOCOLOR pour ce secteur
                    if test_dataset_availability "$satellite" "$sector" "GEOCOLOR" "600x600" >/dev/null 2>&1; then
                        available_datasets+=("$satellite.$sector.GEOCOLOR.600x600")
                        echo "    ✅ $satellite.$sector.GEOCOLOR.600x600"
                    fi
                    
                    # Tester d'autres résolutions pour ce secteur
                    for resolution in "1000x1000" "1200x1200" "300x300"; do
                        if test_dataset_availability "$satellite" "$sector" "GEOCOLOR" "$resolution" >/dev/null 2>&1; then
                            available_datasets+=("$satellite.$sector.GEOCOLOR.$resolution")
                            echo "    ✅ $satellite.$sector.GEOCOLOR.$resolution"
                        fi
                    done
                fi
            done <<< "$sectors"
        fi
    done
    
    echo "📊 Datasets disponibles découverts: ${#available_datasets[@]}"
    printf '  - %s\n' "${available_datasets[@]}"
}

# Fonction pour valider les datasets configurés
validate_configured_datasets() {
    echo "🧪 Validation des datasets configurés..."
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "❌ Fichier de configuration non trouvé: $CONFIG_FILE"
        return 1
    fi
    
    # Créer un fichier temporaire pour les modifications
    local temp_file=$(mktemp)
    cp "$CONFIG_FILE" "$temp_file"
    
    # Tester chaque dataset activé
    jq -r '.enabled_datasets | to_entries[] | "\(.key) \(.value.satellite) \(.value.sector) \(.value.product) \(.value.resolution)"' "$CONFIG_FILE" | \
    while read -r dataset_key satellite sector product resolution; do
        echo "  🧪 Test $dataset_key..."
        
        if test_dataset_availability "$satellite" "$sector" "$product" "$resolution"; then
            echo "    ✅ $dataset_key - Disponible"
            # Marquer comme disponible dans le tracking
            jq --arg key "$dataset_key" \
               --arg status "available" \
               --arg timestamp "$(date -Iseconds)" \
               '.tracking[$key].availability = {
                  "status": $status,
                  "last_check": $timestamp,
                  "accessible": true
                }' "$TRACKING_FILE" > "${TRACKING_FILE}.tmp" && mv "${TRACKING_FILE}.tmp" "$TRACKING_FILE"
        else
            echo "    ❌ $dataset_key - Indisponible"
            
            # Déplacer vers disabled_datasets avec raison
            jq --arg key "$dataset_key" \
               --arg reason "Server not responding or no data available" \
               --arg timestamp "$(date -Iseconds)" \
               '
               (.disabled_datasets[$key] = .enabled_datasets[$key]) |
               (.disabled_datasets[$key].auto_download = false) |
               (.disabled_datasets[$key].disabled_reason = $reason) |
               (.disabled_datasets[$key].disabled_date = $timestamp) |
               del(.enabled_datasets[$key])
               ' "$temp_file" > "${temp_file}.new" && mv "${temp_file}.new" "$temp_file"
            
            # Marquer comme indisponible dans le tracking
            jq --arg key "$dataset_key" \
               --arg status "unavailable" \
               --arg timestamp "$(date -Iseconds)" \
               '.tracking[$key].availability = {
                  "status": $status,
                  "last_check": $timestamp,
                  "accessible": false
                }' "$TRACKING_FILE" > "${TRACKING_FILE}.tmp" && mv "${TRACKING_FILE}.tmp" "$TRACKING_FILE"
        fi
    done
    
    # Tester les datasets désactivés pour voir s'ils sont redevenus disponibles
    jq -r '.disabled_datasets | to_entries[] | "\(.key) \(.value.satellite) \(.value.sector) \(.value.product) \(.value.resolution)"' "$CONFIG_FILE" | \
    while read -r dataset_key satellite sector product resolution; do
        if [ -n "$dataset_key" ]; then
            echo "  🔄 Re-test $dataset_key..."
            
            if test_dataset_availability "$satellite" "$sector" "$product" "$resolution"; then
                echo "    🔄 $dataset_key - Redevenu disponible!"
                
                # Remettre dans enabled_datasets
                jq --arg key "$dataset_key" \
                   --arg timestamp "$(date -Iseconds)" \
                   '
                   (.enabled_datasets[$key] = .disabled_datasets[$key]) |
                   (.enabled_datasets[$key].auto_download = false) |
                   del(.enabled_datasets[$key].disabled_reason) |
                   del(.enabled_datasets[$key].disabled_date) |
                   (.enabled_datasets[$key].re_enabled_date = $timestamp) |
                   del(.disabled_datasets[$key])
                   ' "$temp_file" > "${temp_file}.new" && mv "${temp_file}.new" "$temp_file"
                
                # Marquer comme disponible dans le tracking
                jq --arg key "$dataset_key" \
                   --arg status "available" \
                   --arg timestamp "$(date -Iseconds)" \
                   '.tracking[$key].availability = {
                      "status": $status,
                      "last_check": $timestamp,
                      "accessible": true
                    }' "$TRACKING_FILE" > "${TRACKING_FILE}.tmp" && mv "${TRACKING_FILE}.tmp" "$TRACKING_FILE"
            fi
        fi
    done
    
    # Appliquer les modifications
    mv "$temp_file" "$CONFIG_FILE"
    echo "✅ Validation terminée - Configuration mise à jour"
}

# Fonction principale
main() {
    echo "🌍 Validation de la disponibilité des datasets EarthImagery"
    echo "============================================================="
    
    if [ "${1:-validate}" = "discover" ]; then
        discover_available_datasets
    else
        validate_configured_datasets
    fi
    
    echo ""
    echo "📊 État final des datasets:"
    jq -r '
    "✅ Datasets activés: " + (.enabled_datasets | keys | length | tostring),
    "❌ Datasets désactivés: " + (.disabled_datasets | keys | length | tostring)
    ' "$CONFIG_FILE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
