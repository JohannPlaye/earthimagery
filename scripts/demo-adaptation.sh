#!/bin/bash

# =============================================================================
# DEMO-ADAPTATION.SH - Démonstration de l'adaptation automatique des datasets
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TRACKING_FILE="$PROJECT_ROOT/config/download-tracking.json"

echo "🧪 Démonstration de l'adaptation automatique des datasets"
echo "=========================================================="
echo ""

# Fonction pour lire les datasets actifs (même logique que testcomplet.sh)
get_active_datasets() {
    jq -r '.tracking | to_entries[] | select(.value.dataset_info.enabled == true) | .key' "$TRACKING_FILE" 2>/dev/null || echo ""
}

# Fonction pour compter les datasets
count_datasets() {
    local enabled=$(jq -r '.tracking | to_entries[] | select(.value.dataset_info.enabled == true) | .key' "$TRACKING_FILE" 2>/dev/null | wc -l)
    local total=$(jq -r '.tracking | keys[]' "$TRACKING_FILE" 2>/dev/null | wc -l)
    echo "$enabled/$total"
}

# État actuel
echo "📊 État actuel :"
echo "Datasets actifs/total: $(count_datasets)"
echo ""
echo "Datasets qui seront traités par testcomplet.sh :"
get_active_datasets | while read -r dataset; do
    if [ -n "$dataset" ]; then
        echo "  ✅ $dataset"
    fi
done

echo ""
echo "🔄 Pour modifier l'activation des datasets :"
echo "  1. Utilisez: ./dataset-toggle.sh"
echo "  2. Ou éditez manuellement: config/download-tracking.json"
echo "  3. Changez 'enabled: true/false'"
echo ""
echo "📈 Impact sur testcomplet.sh :"
echo "  - Plus de datasets activés = Plus de téléchargements + Plus de vidéos"
echo "  - Moins de datasets activés = Moins de téléchargements + Moins de vidéos"
echo "  - Changement immédiat au prochain lancement"
echo ""

# Simulation de différents scénarios
echo "🎭 Simulation de scénarios :"
echo ""

# Scénario 1: Tous activés
total_datasets=$(jq -r '.tracking | keys[]' "$TRACKING_FILE" 2>/dev/null | wc -l)
echo "Scénario 1 - Tous les datasets activés ($total_datasets datasets):"
echo "  → testcomplet.sh téléchargerait 10 jours × 24 images × $total_datasets datasets"
echo "  → Soit environ $((10 * 24 * total_datasets)) images au total"
echo ""

# Scénario 2: État actuel
current_count=$(get_active_datasets | wc -l)
echo "Scénario 2 - État actuel ($current_count datasets actifs):"
echo "  → testcomplet.sh téléchargera 10 jours × 24 images × $current_count datasets" 
echo "  → Soit environ $((10 * 24 * current_count)) images au total"
echo ""

# Scénario 3: Aucun activé
echo "Scénario 3 - Aucun dataset activé (0 datasets):"
echo "  → testcomplet.sh afficherait: 'Aucun dataset actif trouvé'"
echo "  → Passerait directement à la génération des vidéos (qui ne ferait rien)"
echo ""

echo "✨ Le script s'adapte automatiquement sans modification de code !"
