#!/bin/bash

# Script de test pour valider la migration NOAA
# Teste que les chemins sont correctement construits avec la nouvelle structure

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🧪 Test de validation de la migration NOAA"
echo "=========================================="

# Test 1: Vérifier que la structure NOAA existe
echo "📂 Test 1: Structure des répertoires"
if [[ -d "$PROJECT_ROOT/public/data/NOAA/GOES18" ]]; then
    echo "✅ NOAA/GOES18 existe"
else
    echo "❌ NOAA/GOES18 manquant"
    exit 1
fi

if [[ -d "$PROJECT_ROOT/public/data/NOAA/GOES19" ]]; then
    echo "✅ NOAA/GOES19 existe"
else
    echo "❌ NOAA/GOES19 manquant"
    exit 1
fi

# Test 2: Vérifier que les anciens répertoires n'existent plus
echo "📂 Test 2: Nettoyage des anciens répertoires"
if [[ ! -d "$PROJECT_ROOT/public/data/GOES18" ]]; then
    echo "✅ Ancien GOES18 supprimé"
else
    echo "❌ Ancien GOES18 encore présent"
    exit 1
fi

if [[ ! -d "$PROJECT_ROOT/public/data/GOES19" ]]; then
    echo "✅ Ancien GOES19 supprimé"
else
    echo "❌ Ancien GOES19 encore présent"
    exit 1
fi

# Test 3: Syntaxe des scripts modifiés
echo "📝 Test 3: Syntaxe des scripts"
scripts_to_test=(
    "smart-fetch.sh"
    "generate-satellite-videos.sh"
    "generate-daily-video.sh"
    "testcomplet.sh"
)

for script in "${scripts_to_test[@]}"; do
    if bash -n "$PROJECT_ROOT/scripts/$script"; then
        echo "✅ $script: syntaxe OK"
    else
        echo "❌ $script: erreur de syntaxe"
        exit 1
    fi
done

# Test 4: Test fonctionnel avec un exemple
echo "🚀 Test 4: Test fonctionnel"

# Créer un répertoire de test temporaire
test_dataset="GOES18.hi.GEOCOLOR.600x600"
test_date="2025-08-20"

# Sourcer le script smart-fetch pour utiliser la fonction
source "$PROJECT_ROOT/scripts/smart-fetch.sh"

# Construire le chemin avec la nouvelle fonction
if command -v build_satellite_data_path >/dev/null 2>&1; then
    test_path=$(build_satellite_data_path "GOES18" "hi" "GEOCOLOR" "600x600" "$test_date")
    expected_path="$PROJECT_ROOT/public/data/NOAA/GOES18/hi/GEOCOLOR/600x600/$test_date"
    
    if [[ "$test_path" == "$expected_path" ]]; then
        echo "✅ build_satellite_data_path: chemin correct"
    else
        echo "❌ build_satellite_data_path: chemin incorrect"
        echo "   Attendu: $expected_path"
        echo "   Obtenu:  $test_path"
        exit 1
    fi
else
    echo "❌ Fonction build_satellite_data_path non trouvée"
    exit 1
fi

echo ""
echo "🎉 Tous les tests sont passés avec succès !"
echo "🛰️ La migration NOAA est fonctionnelle"
echo ""
echo "📋 Résumé de la migration:"
echo "  • GOES18 et GOES19 déplacés vers NOAA/"
echo "  • Scripts modifiés: smart-fetch.sh, generate-satellite-videos.sh, generate-daily-video.sh"
echo "  • Fonction build_satellite_data_path ajoutée"
echo "  • Compatibilité maintenue avec les autres satellites"
