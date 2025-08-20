#!/bin/bash

# =============================================================================
# SATELLITE-DISCOVERY.SH - Découverte satellite optimisée
# =============================================================================
# Version finale qui fonctionne vraiment
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_ROOT/public/data/logs"
CONFIG_DIR="$PROJECT_ROOT/config"
DISCOVERY_LOG="$LOG_DIR/satellite-discovery-$(date +%Y%m%d_%H%M%S).log"
DATASETS_STATUS_FILE="$CONFIG_DIR/datasets-status.json"

# Créer les répertoires nécessaires
mkdir -p "$LOG_DIR" "$CONFIG_DIR"

# Variables globales
TOTAL_DISCOVERIES=0
DATASETS_FILE="${DISCOVERY_LOG%.log}_datasets.json"

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$level] [$timestamp] $message" | tee -a "$DISCOVERY_LOG"
}

# Test fonctionnel
test_url() {
    local url="$1"
    curl -k -L -s --max-time 3 --connect-timeout 1 "$url" 2>/dev/null | head -3 | grep -q "Index of\|href=" 2>/dev/null
}

# Ajouter un dataset découvert
add_dataset() {
    local satellite="$1"
    local instrument="$2"
    local zone="$3"
    local product="$4"
    local resolution="$5"
    
    local dataset_id="${satellite}.${instrument}.${zone}.${product}.${resolution}"
    
    # Écrire en JSON valide (une ligne par dataset pour traitement avec jq)
    local dataset_info="{\"id\":\"$dataset_id\",\"satellite\":\"$satellite\",\"instrument\":\"$instrument\",\"sector\":\"$zone\",\"product\":\"$product\",\"resolution\":\"$resolution\",\"discovery_method\":\"satellite-discovery\",\"discovered_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
    
    echo "$dataset_info" >> "$DATASETS_FILE"
    ((TOTAL_DISCOVERIES++))
    log "SUCCESS" "📥 Dataset: $dataset_id"
}

# Découvrir tous les instruments disponibles
scan_all_instruments() {
    local satellite="$1"
    local satellite_url="https://cdn.star.nesdis.noaa.gov/${satellite}/"
    
    log "INFO" "🔍 Découverte instruments: $satellite"
    
    # Lister tous les instruments disponibles
    local instruments=($(curl -k -L -s --max-time 5 "$satellite_url" 2>/dev/null | grep -o 'href="[^"]*/"' | sed 's/href="//;s/"//' | grep -v '\.\.' | sort))
    
    for instrument in "${instruments[@]}"; do
        if [[ -n "$instrument" ]]; then
            # Supprimer le slash final pour le nom propre
            local instrument_clean="${instrument%/}"
            log "INFO" "📡 Instrument trouvé: $instrument_clean"
            scan_instrument "$satellite" "$instrument_clean"
        fi
    done
}

# Scanner un instrument spécifique
scan_instrument() {
    local satellite="$1"
    local instrument="$2"
    local instrument_url="https://cdn.star.nesdis.noaa.gov/${satellite}/${instrument}/"
    
    log "INFO" "🔍 Scan $instrument: $satellite"
    
    if ! test_url "$instrument_url"; then
        log "WARNING" "❌ $instrument non accessible: $satellite"
        return 0
    fi
    
    # Lister toutes les zones/types disponibles avec protection contre les erreurs
    local content=$(curl -k -L -s --max-time 5 "$instrument_url" 2>/dev/null || echo "")
    
    if [[ -z "$content" ]]; then
        log "WARNING" "⚠️  Impossible d'accéder à l'instrument: $satellite/$instrument"
        return 0
    fi
    
    local zones_text=$(echo "$content" | grep -o 'href="[^"]*/"' 2>/dev/null || echo "")
    local zones=()
    
    if [[ -n "$zones_text" ]]; then
        zones=($(echo "$zones_text" | sed 's/href="//;s/"//' | grep -v '\.\.' | sort))
    fi
    
    for zone in "${zones[@]}"; do
        if [[ -n "$zone" ]]; then
            # Supprimer le slash final pour le nom propre
            local zone_clean="${zone%/}"
            log "INFO" "✅ Zone trouvée: $instrument/$zone_clean"
            scan_zone_products "$satellite" "$instrument" "$zone_clean"
        fi
    done
}

# Scanner les résolutions d'un produit
scan_product_resolutions() {
    local satellite="$1"
    local instrument="$2"
    local zone="$3"
    local product="$4"
    local product_url="https://cdn.star.nesdis.noaa.gov/${satellite}/${instrument}/${zone}/${product}/"
    
    # Récupérer le contenu du répertoire avec protection contre les erreurs
    local content=$(curl -k -L -s --max-time 5 "$product_url" 2>/dev/null || echo "")
    
    if [[ -z "$content" ]]; then
        log "WARNING" "⚠️  Impossible d'accéder au produit: $satellite/$instrument/$zone/$product"
        return 0
    fi
    
    # Stratégie différente selon le type de zone
    if [[ "$zone" == "FD" ]]; then
        # Full Disk : chercher des sous-dossiers numériques (bandes spectrales)
        local bands=$(echo "$content" | grep -o 'href="[0-9]\+/"' | sed 's/href="//;s/\/"$//' | sort -n)
        
        if [[ -n "$bands" ]]; then
            # Prendre la première bande pour découvrir les résolutions
            local first_band=$(echo "$bands" | head -1)
            local band_url="${product_url}${first_band}/"
            local band_content=$(curl -k -L -s --max-time 5 "$band_url" 2>/dev/null || echo "")
            
            # Extraire les résolutions des noms de fichiers
            local resolutions_text=$(echo "$band_content" | grep -o '[0-9]\+x[0-9]\+\.jpg' 2>/dev/null || echo "")
            
            if [[ -n "$resolutions_text" ]]; then
                local resolutions=($(echo "$resolutions_text" | sed 's/\.jpg$//' | sort -u))
                for resolution in "${resolutions[@]}"; do
                    add_dataset "$satellite" "$instrument" "$zone" "$product" "$resolution"
                done
                log "SUCCESS" "✅ Résolutions FD détectées: ${resolutions[*]} pour $satellite/$instrument/$zone/$product"
                return 0
            fi
        fi
    fi
    
    # Pour SECTOR, MESO, etc. : chercher directement les résolutions dans les fichiers
    local resolutions_text=$(echo "$content" | grep -o '[0-9]\+x[0-9]\+\.jpg' 2>/dev/null || echo "")
    local resolutions=()
    
    if [[ -n "$resolutions_text" ]]; then
        resolutions=($(echo "$resolutions_text" | sed 's/\.jpg$//' | sort -u))
        for resolution in "${resolutions[@]}"; do
            add_dataset "$satellite" "$instrument" "$zone" "$product" "$resolution"
        done
        log "SUCCESS" "✅ Résolutions directes détectées: ${resolutions[*]} pour $satellite/$instrument/$zone/$product"
        return 0
    fi
    
    # Résolutions prédéfinies pour certains types de secteurs
    local default_resolution=""
    case "$zone" in
        "SECTOR")
            case "$product" in
                "GEOCOLOR"|"geocolor") default_resolution="10848x10848" ;;
                "cam"|"can"|"car") default_resolution="2500x1500" ;;
                *) default_resolution="1808x1808" ;;
            esac
            ;;
        "MESO")
            default_resolution="1000x1000"
            ;;
        "CONUS")
            default_resolution="5424x5424"
            ;;
    esac
    
    if [[ -n "$default_resolution" ]]; then
        add_dataset "$satellite" "$instrument" "$zone" "$product" "$default_resolution"
        log "INFO" "📐 Résolution par défaut: $default_resolution pour $satellite/$instrument/$zone/$product"
    else
        # Vérifier s'il y a au moins des fichiers dans le répertoire
        local has_files=$(echo "$content" | grep -c 'href="[^"]*\.[^"]*"' 2>/dev/null || echo "0")
        if [[ "$has_files" -gt 0 ]]; then
            add_dataset "$satellite" "$instrument" "$zone" "$product" "unknown"
            log "WARNING" "⚠️  Résolution inconnue pour $satellite/$instrument/$zone/$product"
        else
            log "WARNING" "⚠️  Produit vide: $satellite/$instrument/$zone/$product"
        fi
    fi
}

# Scanner les produits d'une zone
scan_zone_products() {
    local satellite="$1"
    local instrument="$2"
    local zone="$3"
    local zone_url="https://cdn.star.nesdis.noaa.gov/${satellite}/${instrument}/${zone}/"
    
    # Lister tous les produits disponibles avec protection contre les erreurs
    local content=$(curl -k -L -s --max-time 5 "$zone_url" 2>/dev/null || echo "")
    
    if [[ -z "$content" ]]; then
        log "WARNING" "⚠️  Impossible d'accéder à la zone: $satellite/$instrument/$zone"
        return 0
    fi
    
    local products_text=$(echo "$content" | grep -o 'href="[^"]*/"' 2>/dev/null || echo "")
    local products=()
    
    if [[ -n "$products_text" ]]; then
        products=($(echo "$products_text" | sed 's/href="//;s/"//' | grep -v '\.\.' | sort))
    fi
    
    for product in "${products[@]}"; do
        if [[ -n "$product" ]]; then
            # Supprimer le slash final pour le nom propre
            local product_clean="${product%/}"
            local product_url="${zone_url}${product}/"
            
            if test_url "$product_url"; then
                # Découvrir les résolutions pour ce produit
                scan_product_resolutions "$satellite" "$instrument" "$zone" "$product_clean"
            fi
        fi
    done
}

# Scanner tous les satellites
scan_all_satellites() {
    log "INFO" "🚀 Début découverte satellites"
    
    local satellites=("GOES16" "GOES18" "GOES19")
    
    for sat in "${satellites[@]}"; do
        log "INFO" "📡 Satellite: $sat"
        scan_all_instruments "$sat"
    done
}

# Intégrer les datasets découverts dans datasets-status.json
integrate_datasets() {
    log "INFO" "🔄 Intégration dans datasets-status.json"
    
    if [[ ! -f "$DATASETS_FILE" || ! -s "$DATASETS_FILE" ]]; then
        log "WARNING" "Aucun dataset à intégrer"
        return
    fi
    
    # Créer une sauvegarde du fichier de configuration existant
    if [[ -f "$DATASETS_STATUS_FILE" ]]; then
        cp "$DATASETS_STATUS_FILE" "${DATASETS_STATUS_FILE}.backup-$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Lire la configuration existante ou créer une nouvelle
    local enabled_datasets='{}'
    local disabled_datasets='{}'
    
    if [[ -f "$DATASETS_STATUS_FILE" && -s "$DATASETS_STATUS_FILE" ]]; then
        enabled_datasets=$(jq -c '.enabled_datasets // {}' "$DATASETS_STATUS_FILE" 2>/dev/null || echo '{}')
        disabled_datasets=$(jq -c '.disabled_datasets // {}' "$DATASETS_STATUS_FILE" 2>/dev/null || echo '{}')
    fi
    
    # Créer un fichier temporaire pour les datasets découverts
    local temp_discovered=$(mktemp)
    cat "$DATASETS_FILE" | jq -s '
        map(
            {
                key: .id,
                value: {
                    satellite: .satellite,
                    instrument: .instrument,
                    sector: .sector,
                    product: .product,
                    resolution: .resolution,
                    auto_download: false,
                    status: "available",
                    description: (.satellite + " " + .instrument + " " + .sector + " " + .product + " " + .resolution),
                    source: (.discovery_method // "satellite-discovery"),
                    discovered_date: (.discovered_at // (now | strftime("%Y-%m-%dT%H:%M:%S%z")))
                }
            }
        ) |
        from_entries
    ' > "$temp_discovered" 2>/dev/null || {
        log "ERROR" "Erreur lors de la conversion des datasets avec jq"
        rm -f "$temp_discovered"
        return 1
    }
    
    # Construire le fichier final avec traitement par fichiers temporaires
    local temp_final=$(mktemp)
    local temp_enabled=$(mktemp)
    local temp_disabled=$(mktemp)
    
    # Écrire les sections dans des fichiers temporaires
    echo "$enabled_datasets" > "$temp_enabled"
    echo "$disabled_datasets" > "$temp_disabled"
    
    # Construire le fichier final avec jq en lecture de fichiers
    jq -n \
        --slurpfile enabled "$temp_enabled" \
        --slurpfile disabled "$temp_disabled" \
        --slurpfile discovered "$temp_discovered" \
        '{
            enabled_datasets: $enabled[0],
            disabled_datasets: $disabled[0],
            discovered_datasets: $discovered[0]
        }' > "$temp_final" 2>/dev/null || {
        log "ERROR" "Erreur lors de la création du fichier final"
        rm -f "$temp_final" "$temp_enabled" "$temp_disabled" "$temp_discovered"
        return 1
    }
    
    # Copier le résultat final
    mv "$temp_final" "$DATASETS_STATUS_FILE" || {
        log "ERROR" "Erreur lors de la copie du fichier final"
        rm -f "$temp_final" "$temp_enabled" "$temp_disabled" "$temp_discovered"
        return 1
    }
    
    # Nettoyer les fichiers temporaires
    rm -f "$temp_enabled" "$temp_disabled" "$temp_discovered"
    
    # Statistiques d'intégration
    local enabled_count=$(jq '.enabled_datasets | length' "$DATASETS_STATUS_FILE")
    local disabled_count=$(jq '.disabled_datasets | length' "$DATASETS_STATUS_FILE")
    local discovered_count=$(jq '.discovered_datasets | length' "$DATASETS_STATUS_FILE")
    
    log "INFO" "✅ Intégration terminée !"
    log "INFO" "📊 Datasets activés: $enabled_count"
    log "INFO" "📊 Datasets désactivés: $disabled_count"  
    log "INFO" "📊 Datasets découverts: $discovered_count"
    log "INFO" "📊 Total: $((enabled_count + disabled_count + discovered_count))"
}

# Rapport final
generate_report() {
    echo ""
    echo "🎉 DÉCOUVERTE TERMINÉE"
    echo "======================"
    echo "📊 Total: $TOTAL_DISCOVERIES datasets"
    echo "📄 Log: $DISCOVERY_LOG"
    echo "📋 Datasets: $DATASETS_FILE"
    echo ""
    
    if [[ -f "$DATASETS_FILE" && -s "$DATASETS_FILE" ]]; then
        echo "📈 Par satellite:"
        grep -o '"satellite":"[^"]*"' "$DATASETS_FILE" | sort | uniq -c | sort -nr
        echo ""
        
        echo "📊 Exemples trouvés:"
        head -3 "$DATASETS_FILE" | jq -r '.id' 2>/dev/null || grep -o '"id":"[^"]*"' "$DATASETS_FILE" | head -3 | sed 's/"id":"//;s/"//'
    fi
}

# Fonction principale
main() {
    echo "🌍 EarthImagery - Découverte Satellite"
    echo "======================================"
    echo "📝 Logs: $DISCOVERY_LOG"
    echo ""
    
    # Initialisation
    rm -f "$DATASETS_FILE"
    
    log "INFO" "🎬 Démarrage découverte"
    
    # Découverte
    scan_all_satellites
    
    # Intégration dans datasets-status.json
    integrate_datasets
    
    # Rapport
    generate_report
    
    log "INFO" "✅ Découverte terminée avec $TOTAL_DISCOVERIES datasets"
    return 0
}

# Exécution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
