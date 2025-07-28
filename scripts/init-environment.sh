#!/bin/bash

# Script d'initialisation de l'environnement EarthImagery
# Crée tous les dossiers nécessaires et configure l'environnement

# Chargement des variables d'environnement
if [ -f ".env.local" ]; then
    source ".env.local"
else
    echo "⚠ Fichier .env.local non trouvé. Utilisation des valeurs par défaut."
    DATA_ROOT_PATH="./public/data"
    IMAGES_DIR="images"
    VIDEOS_DIR="videos"
    HLS_DIR="hls"
    LOGS_DIR="logs"
fi

echo "🚀 Initialisation de l'environnement EarthImagery"
echo "📁 Dossier racine des données: $DATA_ROOT_PATH"

# Création de la structure de dossiers
echo "📂 Création de la structure de dossiers..."

mkdir -p "$DATA_ROOT_PATH/$IMAGES_DIR"
mkdir -p "$DATA_ROOT_PATH/$VIDEOS_DIR"
mkdir -p "$DATA_ROOT_PATH/$HLS_DIR"
mkdir -p "$DATA_ROOT_PATH/$LOGS_DIR"

# Création d'un dossier components s'il n'existe pas
mkdir -p "src/components"

echo "✅ Structure de dossiers créée:"
echo "   - $DATA_ROOT_PATH/$IMAGES_DIR (images satellitaires)"
echo "   - $DATA_ROOT_PATH/$VIDEOS_DIR (vidéos MP4 journalières)"
echo "   - $DATA_ROOT_PATH/$HLS_DIR (fragments HLS)"
echo "   - $DATA_ROOT_PATH/$LOGS_DIR (logs des scripts)"

# Vérification des dépendances système
echo ""
echo "🔍 Vérification des dépendances système..."

# FFmpeg
if command -v ffmpeg &> /dev/null; then
    echo "✅ FFmpeg installé: $(ffmpeg -version | head -n1)"
else
    echo "❌ FFmpeg non installé"
    echo "   Installation Ubuntu/Debian: sudo apt install ffmpeg"
    echo "   Installation macOS: brew install ffmpeg"
fi

# ImageMagick (optionnel)
if command -v convert &> /dev/null; then
    echo "✅ ImageMagick installé: $(convert -version | head -n1)"
else
    echo "⚠ ImageMagick non installé (optionnel pour les données de test)"
    echo "   Installation Ubuntu/Debian: sudo apt install imagemagick"
    echo "   Installation macOS: brew install imagemagick"
fi

# jq (optionnel)
if command -v jq &> /dev/null; then
    echo "✅ jq installé: $(jq --version)"
else
    echo "⚠ jq non installé (optionnel pour traiter les sources JSON)"
    echo "   Installation Ubuntu/Debian: sudo apt install jq"
    echo "   Installation macOS: brew install jq"
fi

# Node.js
if command -v node &> /dev/null; then
    echo "✅ Node.js installé: $(node --version)"
else
    echo "❌ Node.js non installé"
fi

# npm
if command -v npm &> /dev/null; then
    echo "✅ npm installé: $(npm --version)"
else
    echo "❌ npm non installé"
fi

echo ""
echo "📋 Instructions de démarrage:"
echo "1. Installer les dépendances: npm install"
echo "2. Générer des données de test: ./scripts/generate-test-data.sh"
echo "3. Démarrer le serveur: npm run dev"
echo "4. Ouvrir http://localhost:10000"

echo ""
echo "🔧 Configuration de production (Raspberry Pi):"
echo "1. Modifier .env.local avec DATA_ROOT_PATH=/mnt/data"
echo "2. Configurer les tâches cron pour récupération automatique"
echo "3. Utiliser PM2 pour la gestion du processus"

echo ""
echo "🎉 Initialisation terminée !"
