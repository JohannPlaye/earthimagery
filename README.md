# 🌍 EarthImagery

Application web d'observation de phénomènes météorologiques via imagerie satellitaire.

## 📋 Description

EarthImagery permet de :
- Récupérer automatiquement des images satellitaires à intervalles réguliers
- Générer des vidéos journalières au format HLS (HTTP Live Streaming)
- Créer des animations fluides sur des périodes sélectionnées (1 jour à 1 an)
- Visualiser les données via une interface web responsive

## 🛠️ Stack Technique

### Frontend
- **Next.js 15** avec TypeScript
- **Tailwind CSS** pour le styling
- **Material-UI (MUI)** pour les composants UI
- **hls.js** pour le streaming vidéo
- **Day.js** pour la gestion des dates

### Backend
- **Next.js API Routes** pour l'API REST
- **Scripts Bash** pour la récupération d'images et génération vidéo
- **FFmpeg** pour le traitement vidéo et génération HLS
- **Variables d'environnement** pour la configuration

## 🚀 Installation

### Prérequis

- Node.js 18+ et npm
- FFmpeg installé sur le système
- ImageMagick (optionnel, pour la génération de données de test)

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install ffmpeg imagemagick

# macOS
brew install ffmpeg imagemagick
```

### Configuration

1. **Cloner et installer les dépendances**
```bash
git clone <repository-url>
cd earthimagery
npm install
```

2. **Configuration des variables d'environnement**
```bash
cp .env.example .env.local
```

Éditez `.env.local` pour configurer :
- `DATA_ROOT_PATH` : Chemin racine des données
- `PORT` : Port d'écoute (10000 en dev, 11000 en prod)
- Paramètres de récupération d'images
- Configuration vidéo (FPS, qualité, etc.)

3. **Initialiser la structure de données**
```bash
# Créer les dossiers nécessaires
mkdir -p public/data/{images,videos,hls,logs}
```

## 🎯 Utilisation

### Développement

1. **Démarrer le serveur de développement**
```bash
npm run dev
```

2. **Générer des données de test**
```bash
./scripts/generate-test-data.sh
```

3. **Accéder à l'application**
Ouvrir [http://localhost:10000](http://localhost:10000)

### Production

1. **Build de l'application**
```bash
npm run build
npm start
```

2. **Configuration des tâches automatiques (cron)**
```bash
# Récupération d'images toutes les 30 minutes
*/30 * * * * /path/to/earthimagery/scripts/fetch-images.sh

# Génération vidéo quotidienne à 2h du matin
0 2 * * * /path/to/earthimagery/scripts/generate-daily-video.sh
```

## 📁 Structure du Projet

```
earthimagery/
├── src/
│   ├── app/
│   │   ├── api/playlist/     # API de génération de playlists HLS
│   │   └── page.tsx          # Page principale
│   └── components/
│       ├── DateSelector.tsx  # Sélecteur de période
│       └── VideoPlayer.tsx   # Lecteur vidéo HLS
├── scripts/
│   ├── fetch-images.sh       # Récupération des images
│   ├── generate-daily-video.sh # Génération vidéo
│   └── generate-test-data.sh # Données de test
├── config/
│   └── image-sources.json    # Configuration des sources
├── public/data/              # Stockage des données (dev)
│   ├── images/              # Images par date
│   ├── videos/              # Vidéos MP4 journalières
│   ├── hls/                 # Fragments HLS
│   └── logs/                # Logs des scripts
└── .env.local               # Variables d'environnement
```

## 🔧 Scripts Disponibles

### Scripts npm
- `npm run dev` : Serveur de développement (port 10000)
- `npm run build` : Build de production
- `npm run start` : Serveur de production (port 11000)
- `npm run lint` : Vérification ESLint

### Scripts système
- `./scripts/fetch-images.sh` : Récupérer les images
- `./scripts/generate-daily-video.sh [date]` : Générer vidéo pour une date
- `./scripts/generate-test-data.sh` : Créer des données de test

## 🌐 API Endpoints

### `GET /api/playlist`
Génère une playlist HLS pour une période donnée.

**Paramètres :**
- `from` : Date de début (YYYY-MM-DD)
- `to` : Date de fin (YYYY-MM-DD)

**Exemple :**
```
GET /api/playlist?from=2025-01-01&to=2025-01-07
```

### `POST /api/playlist`
Obtient des informations sur une période de données.

**Body :**
```json
{
  "from": "2025-01-01",
  "to": "2025-01-07"
}
```

## 📊 Configuration des Sources

Éditez `config/image-sources.json` pour configurer les sources d'images :

```json
{
  "sources": [
    {
      "name": "Meteosat Europe",
      "url": "https://example.com/meteosat/{date}/{timestamp}.jpg",
      "interval_minutes": 15,
      "active": true
    }
  ]
}
```

Variables disponibles dans les URLs :
- `{date}` : Date au format YYYY-MM-DD
- `{timestamp}` : Timestamp au format YYYYMMDD_HHMM

## 🔒 Sécurité et Limites

- **Plage maximale** : 365 jours par défaut
- **Validation des dates** : Vérification côté client et serveur
- **Nettoyage automatique** : Suppression des données anciennes
- **Gestion d'erreurs** : Retry automatique et logs détaillés

## 🌟 Fonctionnalités

### Interface Utilisateur
- ✅ Sélection de période avec calendrier
- ✅ Aperçu des données disponibles
- ✅ Lecteur vidéo HLS avec contrôles
- ✅ Interface responsive (mobile/desktop)
- ✅ Indicateurs de chargement et erreurs

### Traitement Vidéo
- ✅ Génération HLS automatique
- ✅ Streaming fluide sans re-encoding
- ✅ Support multi-navigateurs
- ✅ Optimisation des performances

### Automation
- ✅ Scripts de récupération automatique
- ✅ Génération vidéo programmable
- ✅ Nettoyage automatique des données
- ✅ Logs et monitoring

## 🚀 Déploiement

### Configuration du Serveur de Production

#### Prérequis Serveur
- Ubuntu/Debian avec accès SSH
- Node.js installé via nvm (recommandé)
- PM2 pour la gestion des processus
- Port ouvert pour l'application

#### Installation Node.js via nvm
```bash
# Sur le serveur de production
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc
nvm install --lts
nvm use --lts
npm install -g pm2
```

### Scripts de Déploiement Automatisés

Le projet inclut deux scripts de déploiement automatisés :

#### `./deploy.sh` - Déploiement Principal
Script complet avec vérifications et gestion d'erreurs avancée.

**Usage :**
```bash
# Déploiement rapide (défaut)
./deploy.sh

# Déploiement avec nettoyage complet des dépendances
./deploy.sh --clean

# Afficher l'aide
./deploy.sh --help
```

**Fonctionnalités :**
- ✅ Vérifications préalables (build, node_modules, SSH)
- ✅ Authentification SSH unique avec sshpass
- ✅ Arrêt automatique de l'application en cours
- ✅ Transfert rsync optimisé avec gestion d'erreurs
- ✅ Installation automatique des dépendances
- ✅ Support nvm sur le serveur distant
- ✅ Vérification post-déploiement
- ✅ Redémarrage automatique de l'application
- ✅ Affichage du statut final

#### `./deploy-simple.sh` - Déploiement Diagnostique
Version simplifiée pour diagnostiquer les problèmes de déploiement.

**Usage :**
```bash
# Déploiement avec logs détaillés (défaut)
./deploy-simple.sh

# Déploiement avec nettoyage complet
./deploy-simple.sh --clean

# Afficher l'aide
./deploy-simple.sh --help
```

**Fonctionnalités :**
- ✅ Logs détaillés étape par étape
- ✅ Arrêt automatique de l'application en cours
- ✅ Diagnostic des erreurs rsync
- ✅ Vérification de l'espace disque
- ✅ Transfert par composants séparés
- ✅ Redémarrage automatique de l'application
- ✅ Mode verbeux pour le debugging

### Options de Déploiement

#### Mode Rapide (Défaut)
```bash
./deploy.sh
```
- Utilise rsync pour transférer les fichiers existants
- Conserve node_modules pour un déploiement rapide
- Exécute `npm install --production` pour mettre à jour

#### Mode Nettoyage Complet
```bash
./deploy.sh --clean
```
- Supprime complètement `node_modules` et `package-lock.json`
- Réinstalle toutes les dépendances depuis zéro
- Plus lent mais évite les corruptions de dépendances
- **Recommandé en cas de problèmes de démarrage**

### Configuration du Serveur

#### Variables d'Environnement Serveur
Le déploiement configure automatiquement :
```json
{
  "NODE_ENV": "production",
  "PORT": "11000",
  "HOSTNAME": "0.0.0.0"
}
```

#### Fichiers Déployés
- `📁 .next/` - Build Next.js optimisé
- `📁 node_modules/` - Dépendances de production  
- `📁 config/` - Configuration de l'application (datasets, utilisateurs)
- `📁 public/` - Assets statiques (exclut `data/`)
- `📁 scripts/` - Scripts de traitement vidéo
- `📄 package.json` - Configuration npm
- `📄 next.config.ts` - Configuration Next.js
- `📄 pm2.config.json` - Configuration PM2
- `📄 pm2-manager.sh` - Gestionnaire PM2

#### Exclusions de Déploiement
- `data/` - Préserve les données satellitaires existantes
- `*.log` - Évite les fichiers de logs locaux
- `.cache` - Exclut les caches temporaires

### Gestion PM2 en Production

#### Script de Gestion PM2
Utilisez `pm2-manager.sh` sur le serveur pour gérer l'application :

```bash
# Démarrer l'application
./pm2-manager.sh start

# Vérifier le statut
./pm2-manager.sh status

# Voir les logs en temps réel
./pm2-manager.sh logs

# Redémarrer l'application
./pm2-manager.sh restart

# Recharger sans downtime
./pm2-manager.sh reload

# Arrêter l'application
./pm2-manager.sh stop

# Monitoring en temps réel
./pm2-manager.sh monitor

# Lister tous les processus PM2
./pm2-manager.sh list

# Supprimer de PM2
./pm2-manager.sh delete
```

#### Configuration PM2
```json
{
  "name": "earthimagery",
  "script": "npm",
  "args": "start",
  "instances": 1,
  "exec_mode": "fork",
  "env": {
    "NODE_ENV": "production",
    "PORT": "11000",
    "HOSTNAME": "0.0.0.0"
  },
  "autorestart": true,
  "max_restarts": 10,
  "min_uptime": "10s",
  "max_memory_restart": "1G"
}
```

### Processus de Déploiement Complet

#### 1. Préparation Locale
```bash
# Build de l'application
npm run build

# Vérification du build
ls -la .next/
```

#### 2. Déploiement
```bash
# Déploiement standard
./deploy.sh

# Ou en cas de problème
./deploy.sh --clean
```
**Le script va automatiquement :**
- Arrêter l'application en cours (si elle tourne)
- Transférer tous les fichiers mis à jour
- Installer/mettre à jour les dépendances
- Redémarrer l'application avec PM2
- Afficher le statut final

#### 3. Vérification du Déploiement
L'application se redémarre automatiquement après le déploiement. Pour vérifier manuellement :

```bash
# Connexion SSH (optionnel, déjà fait automatiquement)
ssh -p 2221 johann@88.174.193.236

# Navigation vers le projet (optionnel)
cd developpement/earthimagery

# Vérification du statut (déjà affiché automatiquement)
./pm2-manager.sh status
```

#### 4. Accès à l'Application
L'application sera accessible sur :
- **URL** : `http://88.174.193.236:11000`
- **Logs** : `./pm2-manager.sh logs`
- **Monitoring** : `./pm2-manager.sh monitor`

### Résolution de Problèmes

#### Problèmes de Dépendances
```bash
# Si l'application crash au démarrage
./deploy.sh --clean  # Force la réinstallation

# Ou manuellement sur le serveur
rm -rf node_modules package-lock.json
npm install --production
./pm2-manager.sh restart
```

#### Problèmes de Connexion
```bash
# Vérifier les ports ouverts
netstat -tlnp | grep 11000

# Vérifier le firewall
sudo ufw status

# Ouvrir le port si nécessaire
sudo ufw allow 11000
```

#### Logs de Débogage
```bash
# Logs PM2 détaillés
./pm2-manager.sh logs

# Fichiers de logs
cat logs/pm2-error.log
cat logs/pm2-out.log
cat logs/pm2.log
```

### Scripts de Maintenance

#### Nettoyage Automatique
```bash
# Script de nettoyage des anciens logs
find logs/ -name "*.log" -mtime +30 -delete

# Nettoyage des données anciennes (si configuré)
./scripts/cleanup-old-data.sh
```

#### Sauvegarde
```bash
# Sauvegarde de la configuration
tar -czf earthimagery-config-$(date +%Y%m%d).tar.gz \
    pm2.config.json package.json next.config.ts

# Sauvegarde des données (si besoin)
rsync -av public/data/ backup/data-$(date +%Y%m%d)/
```

### Raspberry Pi (Production)

1. **Préparer l'environnement**
```bash
# Installer Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs ffmpeg imagemagick

# Monter le disque externe
sudo mkdir /mnt/data
sudo mount /dev/sda1 /mnt/data
```

2. **Configurer l'application**
```bash
# Copier les fichiers
scp -r earthimagery/ pi@raspberry:/home/pi/

# Configurer les variables d'environnement pour la production
DATA_ROOT_PATH=/mnt/data
```

3. **Configurer les services**
```bash
# PM2 pour la gestion des processus
npm install -g pm2
pm2 start npm --name "earthimagery" -- start
pm2 startup
pm2 save
```

## 🧪 Tests et Développement

### Génération de données de test
```bash
./scripts/generate-test-data.sh
```

Cela génère :
- 7 jours de données factices
- 24 images par jour
- Vidéos et fragments HLS correspondants

### Variables d'environnement de test
```bash
DATA_ROOT_PATH=./public/data  # Développement local
VIDEO_FPS=25
HLS_SEGMENT_TIME=10
MAX_DATE_RANGE_DAYS=365
```

## 📈 Évolutions Futures

- [ ] Authentification et gestion d'utilisateurs
- [ ] Overlays météo (température, précipitations)
- [ ] Téléchargement de vidéos
- [ ] API de statistiques
- [ ] Interface d'administration
- [ ] Support multi-sources simultanées
- [ ] Compression avancée et CDN

## 🤝 Contribution

1. Fork le projet
2. Créer une branche pour votre fonctionnalité
3. Commit vos changements
4. Push vers la branche
5. Ouvrir une Pull Request

## 📄 Licence

Ce projet est sous licence MIT. Voir `LICENSE` pour plus de détails.

---

**Développé avec ❤️ pour l'observation météorologique**
