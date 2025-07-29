#!/bin/bash

# Script d'exploration complète des sources NOAA GOES

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Test d'accès aux différents buckets NOAA
test_bucket_access() {
    local bucket="$1"
    local prefix="$2"
    
    log "Test d'accès: s3://$bucket/$prefix"
    
    # Test simple d'existence
    response=$(curl -s -w "%{http_code}" -o /dev/null "https://$bucket.s3.amazonaws.com/$prefix")
    
    case $response in
        200) echo "✅ Accessible" ;;
        403) echo "🔒 Accès refusé" ;;
        404) echo "❌ Non trouvé" ;;
        *) echo "❓ Code: $response" ;;
    esac
}

# Test d'accès aux différents répertoires
test_noaa_buckets() {
    log "=== Test d'accès aux buckets NOAA GOES ==="
    
    # Buckets principaux
    for satellite in "goes16" "goes17" "goes18"; do
        log "\n--- NOAA-$satellite ---"
        
        # Produits principaux à tester
        products=(
            "ABI-L1b-RadF"
            "ABI-L1b-RadC" 
            "ABI-L2-CMIPF"
            "ABI-L2-CMIPC"
            "ABI-L2-MCMIPF"
            "GLM-L2-LCFA"
        )
        
        for product in "${products[@]}"; do
            printf "  %-15s : " "$product"
            test_bucket_access "noaa-$satellite" "$product/"
        done
    done
}

# Test avec une année récente
test_recent_data() {
    log "\n=== Test de données récentes ==="
    
    # Test des données les plus récentes possibles
    for year in 2024 2023 2022; do
        log "Test année $year"
        for satellite in "goes16" "goes17" "goes18"; do
            printf "  NOAA-$satellite ABI-L1b-RadC/$year: "
            test_bucket_access "noaa-$satellite" "ABI-L1b-RadC/$year"
        done
    done
}

# Test d'accès via AWS CLI public (si disponible)
test_aws_public_access() {
    log "\n=== Test AWS CLI (sans authentification) ==="
    
    if command -v aws >/dev/null 2>&1; then
        # Configuration pour accès public
        export AWS_NO_SIGN_REQUEST=YES
        
        log "Test listing avec AWS CLI..."
        timeout 10 aws s3 ls s3://noaa-goes18/ --no-sign-request 2>/dev/null | head -10
        
        unset AWS_NO_SIGN_REQUEST
    else
        log "AWS CLI non disponible"
    fi
}

# Test d'autres sources de données publiques
test_alternative_sources() {
    log "\n=== Sources alternatives ==="
    
    # NOAA CLASS (Comprehensive Large Array-data Stewardship System)
    log "Test NOAA CLASS API..."
    curl -s -w "%{http_code}" -o /dev/null "https://www.avl.class.noaa.gov/saa/products/search"
    
    # NOAA Real-time feeds
    log "\nTest NOAA Real-time..."
    curl -s -w "%{http_code}" -o /dev/null "https://cdn.star.nesdis.noaa.gov/GOES16/"
    
    # University datasets
    log "\nTest UCAR/UNIDATA..."
    curl -s -w "%{http_code}" -o /dev/null "https://thredds.ucar.edu/thredds/catalog/satellite/goes/"
}

# Recherche d'endpoints alternatifs
search_alternative_endpoints() {
    log "\n=== Recherche d'endpoints publics ==="
    
    # URLs alternatives connues
    urls=(
        "https://cdn.star.nesdis.noaa.gov/GOES16/ABI/SECTOR/GMM/"
        "https://cdn.star.nesdis.noaa.gov/GOES17/ABI/SECTOR/GWM/"
        "https://cdn.star.nesdis.noaa.gov/GOES18/ABI/SECTOR/WPM/"
        "https://satepsanone.nesdis.noaa.gov/pub/"
        "https://nomads.ncep.noaa.gov/pub/"
    )
    
    for url in "${urls[@]}"; do
        printf "%-60s : " "$url"
        response=$(curl -s -w "%{http_code}" -o /dev/null "$url")
        case $response in
            200) echo "✅ Disponible" ;;
            404) echo "❌ Non trouvé" ;;
            403) echo "🔒 Accès refusé" ;;
            *) echo "❓ Code: $response" ;;
        esac
    done
}

# Fonction principale
main() {
    log "🛰️ Exploration complète des sources NOAA GOES"
    log "========================================"
    
    test_noaa_buckets
    test_recent_data
    test_aws_public_access
    test_alternative_sources
    search_alternative_endpoints
    
    log "\n=== Résumé ==="
    log "Exploration terminée. Consultez les résultats ci-dessus."
}

# Exécution
main
