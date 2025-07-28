#!/bin/bash

# Amélioration du script fetch-images.sh pour les données réelles

# Fonction de téléchargement avec authentification
fetch_image_with_auth() {
    local url="$1"
    local output_path="$2"
    local api_key="$3"
    local max_retries=3
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        # Support pour différents types d'authentification
        if [ -n "$api_key" ]; then
            # Option 1: API Key dans les headers
            curl_cmd="curl -s -H \"X-API-Key: $api_key\" -o \"$output_path\" \"$url\""
            # Option 2: API Key dans l'URL (selon l'API)
            # curl_cmd="curl -s -o \"$output_path\" \"${url}?api_key=${api_key}\""
            # Option 3: Bearer token
            # curl_cmd="curl -s -H \"Authorization: Bearer $api_key\" -o \"$output_path\" \"$url\""
        else
            curl_cmd="curl -s -o \"$output_path\" \"$url\""
        fi

        if eval $curl_cmd; then
            # Vérifier que le fichier n'est pas vide et est une vraie image
            if [ -s "$output_path" ] && file "$output_path" | grep -q "image"; then
                log "✓ Image téléchargée et validée: $output_path"
                return 0
            else
                log "⚠ Fichier invalide ou vide: $output_path"
                rm -f "$output_path"
            fi
        else
            log "✗ Erreur de téléchargement: $url"
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            log "Retry $retry_count/$max_retries dans 10 secondes..."
            sleep 10
        fi
    done

    log "✗ Échec définitif pour: $url"
    return 1
}

# Validation de la taille et du format d'image
validate_image() {
    local file_path="$1"
    local max_size_mb=10
    
    # Vérifier la taille
    local file_size_mb=$(du -m "$file_path" | cut -f1)
    if [ "$file_size_mb" -gt "$max_size_mb" ]; then
        log "⚠ Fichier trop volumineux: $file_path ($file_size_mb MB)"
        return 1
    fi
    
    # Vérifier le format
    if ! file "$file_path" | grep -q "image"; then
        log "⚠ Format de fichier invalide: $file_path"
        return 1
    fi
    
    return 0
}
