#!/bin/bash

# =============================================================================
# GESTIONNAIRE PM2 EARTHIMAGERY LOCAL
# =============================================================================
# Script pour gérer l'application EarthImagery avec PM2 en local
# À exécuter directement sur le serveur de production
# =============================================================================

set -euo pipefail

# Chargement de nvm au début du script
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

# Configuration locale
APP_NAME="earthimagery"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

# Vérifier le statut de l'application
status() {
    log "📊 Statut de l'application EarthImagery"
    cd "$SCRIPT_DIR"
    pm2 show $APP_NAME 2>/dev/null || echo "Application '$APP_NAME' non trouvée dans PM2"
}

# Démarrer l'application
start() {
    log "🚀 Démarrage de l'application EarthImagery"
    cd "$SCRIPT_DIR"
    
    # Créer le répertoire logs s'il n'existe pas
    mkdir -p logs
    
    if [ ! -f "pm2.config.json" ]; then
        error "Fichier pm2.config.json non trouvé dans $SCRIPT_DIR"
        exit 1
    fi
    
    pm2 start pm2.config.json
    log "✅ Application démarrée"
}

# Arrêter l'application
stop() {
    log "⏹️ Arrêt de l'application EarthImagery"
    cd "$SCRIPT_DIR"
    pm2 stop $APP_NAME
    log "✅ Application arrêtée"
}

# Redémarrer l'application
restart() {
    log "🔄 Redémarrage de l'application EarthImagery"
    cd "$SCRIPT_DIR"
    pm2 restart $APP_NAME
    log "✅ Application redémarrée"
}

# Supprimer l'application de PM2
delete() {
    log "🗑️ Suppression de l'application EarthImagery de PM2"
    cd "$SCRIPT_DIR"
    pm2 delete $APP_NAME
    log "✅ Application supprimée de PM2"
}

# Voir les logs en temps réel
logs() {
    log "📄 Logs en temps réel de l'application EarthImagery"
    log "Appuyez sur Ctrl+C pour quitter"
    cd "$SCRIPT_DIR"
    pm2 logs $APP_NAME
}

# Voir le monitoring
monitor() {
    log "📈 Monitoring de l'application EarthImagery"
    cd "$SCRIPT_DIR"
    pm2 monit
}

# Liste des processus PM2
list() {
    log "📋 Liste des processus PM2"
    pm2 list
}

# Recharger la configuration PM2
reload() {
    log "🔄 Rechargement de la configuration PM2"
    cd "$SCRIPT_DIR"
    pm2 reload $APP_NAME
    log "✅ Configuration rechargée"
}

# Afficher l'aide
show_help() {
    echo "🌍 EarthImagery - Gestionnaire PM2 Local"
    echo "========================================"
    echo ""
    echo "Usage: $0 <commande>"
    echo ""
    echo "Commandes disponibles:"
    echo "  start    - Démarrer l'application"
    echo "  stop     - Arrêter l'application"
    echo "  restart  - Redémarrer l'application"
    echo "  reload   - Recharger l'application (sans downtime)"
    echo "  status   - Voir le statut de l'application"
    echo "  logs     - Voir les logs en temps réel"
    echo "  monitor  - Ouvrir le monitoring PM2"
    echo "  list     - Lister tous les processus PM2"
    echo "  delete   - Supprimer l'application de PM2"
    echo ""
    echo "Exemples:"
    echo "  $0 start    # Démarrer EarthImagery"
    echo "  $0 logs     # Voir les logs"
    echo "  $0 status   # Vérifier le statut"
    echo ""
    echo "ℹ️  Ce script doit être exécuté directement sur le serveur de production"
}

# Fonction principale
main() {
    if [ $# -eq 0 ]; then
        show_help
        exit 1
    fi

    local command="$1"
    
    case $command in
        "start")
            start
            ;;
        "stop")
            stop
            ;;
        "restart")
            restart
            ;;
        "reload")
            reload
            ;;
        "status")
            status
            ;;
        "logs")
            logs
            ;;
        "monitor")
            monitor
            ;;
        "list")
            list
            ;;
        "delete")
            delete
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            error "Commande inconnue: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"