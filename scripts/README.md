# Scripts de Test EarthImagery

Ce dossier contient les scripts pour tester et valider le pipeline complet d'EarthImagery.

## Scripts Disponibles

### 🧪 `testcomplet.sh` - Test de bout en bout

**Usage :** `./testcomplet.sh`

Script principal qui effectue un test complet du pipeline :

1. **🧹 Nettoyage** - Supprime toutes les données existantes (images, vidéos, playlists)
2. **📥 Téléchargement** - Récupère 10 jours de données pour tous les datasets actifs
3. **🎬 Génération** - Crée les fragments vidéo journaliers avec ffmpeg
4. **📋 Playlists** - Génère les playlists HLS pour le streaming
5. **📊 Rapport** - Affiche un rapport final avec les statistiques

**Prérequis :**
- `jq` pour le parsing JSON
- `ffmpeg` pour la génération vidéo
- `curl` pour les téléchargements

### 🛠️ `test-helper.sh` - Assistant de test interactif

**Usage :** `./test-helper.sh`

Interface menu interactive pour :
- Exécuter le test complet
- Nettoyer seulement les données
- Télécharger 1 jour de test
- Vérifier les dépendances
- Consulter les logs récents

### 📥 `unified-download.sh` - Téléchargement unifié

**Usage :** `./unified-download.sh --satellite GOES18 --sector hi --product GEOCOLOR --resolution 600x600 --date 2025-01-15 --max-images 24`

Script de téléchargement avec support pour :
- NOAA GOES (vraies données satellitaires)
- Sources simulées pour le développement
- Tracking automatique des téléchargements
- Validation des paramètres

### 🎬 `generate-daily-video.sh` - Génération vidéo

**Usage :** `./generate-daily-video.sh 2025-01-15 GOES18.hi.GEOCOLOR.600x600`

Génère une vidéo time-lapse à partir des images d'une journée :
- Tri chronologique des images
- Création de fragments HLS (.ts)
- Génération de playlist (.m3u8)
- Optimisation pour le streaming web

### ⚙️ `dataset-toggle.sh` - Gestion des datasets

**Usage :** `./dataset-toggle.sh`

Interface pour activer/désactiver les datasets dans le fichier de tracking.

## Configuration

### Fichier de Tracking

Le fichier `config/download-tracking.json` contient :
- Configuration des datasets (satellite, secteur, produit, résolution)
- État d'activation (`enabled: true/false`)
- Historique des téléchargements
- Statistiques par jour

### Structure des Données

```
public/data/
├── images/          # Images satellitaires organisées par dataset/date
├── videos/          # Vidéos MP4 journalières
├── hls/            # Playlists et segments HLS pour streaming
└── logs/           # Logs des opérations
```

## Workflow Typique

1. **Configuration initiale :**
   ```bash
   # Activer les datasets souhaités
   ./dataset-toggle.sh
   ```

2. **Test complet :**
   ```bash
   # Test de bout en bout
   ./testcomplet.sh
   ```

3. **Développement interactif :**
   ```bash
   # Assistant pour tests ciblés
   ./test-helper.sh
   ```

4. **Validation frontend :**
   ```bash
   # Démarrer l'application
   cd ..
   npm run dev
   # Ouvrir http://localhost:10000
   ```

## Logs et Debugging

- Les logs sont automatiquement créés dans `public/data/logs/`
- Format : `testcomplet-YYYYMMDD-HHMMSS.log`
- Codes couleur pour faciliter la lecture
- Niveaux : INFO, WARN, ERROR, DEBUG

## Dépannage

### Dépendances manquantes
```bash
sudo apt install jq ffmpeg curl
```

### Permissions
```bash
chmod +x scripts/*.sh
```

### Espace disque
Le test complet peut générer plusieurs centaines de Mo de données. Vérifiez l'espace disponible.

### Datasets inactifs
Si aucun dataset n'est téléchargé, vérifiez `config/download-tracking.json` et activez au moins un dataset avec `enabled: true`.
