#!/bin/bash

# =============================================================================
# DÉPLOIEMENT SIMPLE EARTHIMAGERY - Mode Diagnostic
# =============================================================================
# Version simplifiée pour diagnostiquer les problèmes de déploiement
# Version: 3.0 - Avec authentification unique et option --clean
# 
# Usage:
#   ./deploy-simple.sh           # Déploiement rapide (défaut)
#   ./deploy-simple.sh --clean   # Déploiement avec nettoyage complet
# =============================================================================

set -euo pipefail

# Configuration
SERVER_HOST="88.174.193.236"
SERVER_PORT="2221"
SERVER_USER="johann"
SERVER_PATH="developpement/earthimagery"

# Options de déploiement
CLEAN_INSTALL=false

# Analyse des arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean)
                CLEAN_INSTALL=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "❌ Argument inconnu: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Affichage de l'aide
show_help() {
    echo "🔧 EarthImagery - Script de Déploiement Simple"
    echo "=============================================="
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --clean    Force la suppression et réinstallation de node_modules"
    echo "  -h, --help Affiche cette aide"
    echo ""
    echo "Exemples:"
    echo "  $0           # Déploiement rapide (défaut)"
    echo "  $0 --clean  # Déploiement avec nettoyage complet"
    echo ""
}

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Demande du mot de passe une seule fois
prompt_password() {
    echo "🔐 Authentification SSH"
    echo "======================="
    read -s -p "Mot de passe SSH pour $SERVER_USER@$SERVER_HOST: " SSH_PASSWORD
    echo ""
    export SSHPASS="$SSH_PASSWORD"
    log "Mot de passe configuré pour la session"
}

log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

echo "🔧 EarthImagery - Déploiement Mode Diagnostic"
echo "============================================"

# Analyse des arguments
parse_arguments "$@"

if [ "$CLEAN_INSTALL" = true ]; then
    echo "🧹 Mode nettoyage complet activé"
fi
echo ""

# Authentification unique
prompt_password

# Test connexion
log "Test de connexion SSH..."
if ! sshpass -e ssh -p $SERVER_PORT -o ConnectTimeout=10 $SERVER_USER@$SERVER_HOST "echo 'Connexion OK'"; then
    error "Impossible de se connecter au serveur"
    exit 1
fi

# Arrêt de l'application si elle tourne
log "Vérification et arrêt de l'application en cours..."
sshpass -e ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST "
    cd $SERVER_PATH 2>/dev/null || { echo 'Répertoire $SERVER_PATH inexistant, première installation'; exit 0; }
    
    # Chargement de nvm pour PM2
    export NVM_DIR=\"\$HOME/.nvm\"
    [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
    [ -s \"\$NVM_DIR/bash_completion\" ] && . \"\$NVM_DIR/bash_completion\"
    
    # Vérifier si PM2 et l'application existent
    if command -v pm2 >/dev/null 2>&1; then
        if pm2 describe earthimagery >/dev/null 2>&1; then
            echo '🛑 Application EarthImagery détectée, arrêt en cours...'
            ./pm2-manager.sh stop 2>/dev/null || pm2 stop earthimagery 2>/dev/null || echo 'Arrêt manuel de PM2'
            echo '✅ Application arrêtée'
        else
            echo 'ℹ️  Aucune application EarthImagery en cours d'\''exécution'
        fi
    else
        echo 'ℹ️  PM2 non installé ou non accessible'
    fi
"

# Préparation serveur
log "Préparation du répertoire serveur..."
sshpass -e ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST "
    mkdir -p $SERVER_PATH
    echo 'Espace disque:'
    df -h | head -2
    echo ''
    echo 'Permissions:'
    ls -ld $SERVER_PATH
    echo ''
    echo 'Contenu existant:'
    ls -la $SERVER_PATH/ 2>/dev/null || echo 'Répertoire vide'
"

# Déploiement par étapes avec diagnostic
deploy_step() {
    local source="$1"
    local description="$2"
    local use_delete="$3"
    
    log "Copie de $description..."
    
    if [ ! -e "$source" ]; then
        warn "$source n'existe pas, ignoré"
        return 0
    fi
    
    local delete_option=""
    if [ "$use_delete" = "true" ]; then
        delete_option="--delete"
    fi
    
    # Rsync avec options détaillées
    if sshpass -e rsync -avz --progress --partial --inplace $delete_option \
              --exclude='*.log' --exclude='.cache' --exclude='data/' \
              -e "ssh -p $SERVER_PORT" \
              "$source" $SERVER_USER@$SERVER_HOST:$SERVER_PATH/; then
        log "✅ $description copié avec succès"
    else
        local exit_code=$?
        if [ $exit_code -eq 23 ]; then
            warn "Code 23 pour $description - copie partielle (c'est souvent normal)"
        else
            error "Erreur critique pour $description (code: $exit_code)"
            return $exit_code
        fi
    fi
}

# Déploiement étape par étape
echo ""
deploy_step "package.json" "Configuration package.json" false
deploy_step "pm2.config.json" "Configuration PM2" false
deploy_step "pm2-manager.sh" "Script de gestion PM2" false
deploy_step "next.config.ts" "Configuration Next.js" false
deploy_step "package-lock.json" "Lock file" false
deploy_step ".env.local" "Variables d'environnement" false

deploy_step "config" "Configuration de l'application" true
deploy_step "public" "Assets statiques" true
# IMPORTANT: scripts sans slash final pour copier le répertoire lui-même  
deploy_step "scripts" "Scripts" true

# Déploiement de .next en dernier (le plus gros)
# IMPORTANT: .next sans slash final pour copier le répertoire lui-même
deploy_step ".next" "Build Next.js" true

# Node_modules en dernier (le plus risqué)
echo ""
log "Déploiement de node_modules (peut prendre du temps)..."
# IMPORTANT: node_modules sans slash final pour copier le répertoire lui-même
if sshpass -e rsync -avz --progress --partial --inplace --delete \
          --exclude='*.log' --exclude='.cache' --exclude='node_modules/.cache' --exclude='data/' \
          -e "ssh -p $SERVER_PORT" \
          node_modules $SERVER_USER@$SERVER_HOST:$SERVER_PATH/; then
    log "✅ node_modules copié"
else
    warn "Problème avec node_modules (code: $?), mais souvent non critique"
fi

# Installation des dépendances après transfert
echo ""
if [ "$CLEAN_INSTALL" = true ]; then
    log "Nettoyage et réinstallation complète des dépendances..."
    if sshpass -e ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST "
        # Chargement de nvm et activation de la version courante
        export NVM_DIR=\"\$HOME/.nvm\"
        [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
        [ -s \"\$NVM_DIR/bash_completion\" ] && . \"\$NVM_DIR/bash_completion\"
        
        # Nettoyage complet et réinstallation
        cd $SERVER_PATH && rm -rf node_modules package-lock.json && npm install --production
    "; then
        log "✅ Dépendances réinstallées avec succès (mode propre)"
    else
        warn "Erreur lors de l'installation propre des dépendances (code: $?)"
    fi
else
    log "Installation des dépendances sur le serveur..."
    if sshpass -e ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST "
        # Chargement de nvm et activation de la version courante
        export NVM_DIR=\"\$HOME/.nvm\"
        [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
        [ -s \"\$NVM_DIR/bash_completion\" ] && . \"\$NVM_DIR/bash_completion\"
        
        # Aller dans le répertoire et installer les dépendances
        cd $SERVER_PATH && npm install --production
    "; then
        log "✅ Dépendances installées avec succès"
    else
        warn "Erreur lors de l'installation des dépendances (code: $?)"
    fi
fi

# Vérification finale
echo ""
log "Vérification finale..."
sshpass -e ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST "
    cd $SERVER_PATH
    echo 'Contenu final:'
    ls -la
    echo ''
    echo 'Vérifications critiques:'
    [ -f 'package.json' ] && echo '✅ package.json' || echo '❌ package.json'
    [ -d '.next' ] && echo '✅ .next/' || echo '❌ .next/'
    [ -d 'node_modules' ] && echo '✅ node_modules/' || echo '❌ node_modules/'
    [ -f '.env.local' ] && echo '✅ .env.local' || echo '❌ .env.local'
    [ -d 'config' ] && echo '✅ config/' || echo '❌ config/'
    [ -d 'public' ] && echo '✅ public/' || echo '❌ public/'
    [ -d 'scripts' ] && echo '✅ scripts/' || echo '❌ scripts/'
    [ -f 'pm2.config.json' ] && echo '✅ pm2.config.json' || echo '❌ pm2.config.json'
    [ -x 'pm2-manager.sh' ] && echo '✅ pm2-manager.sh (exécutable)' || echo '❌ pm2-manager.sh'
    [ -f 'node_modules/next/package.json' ] && echo '✅ node_modules/next (installé)' || echo '❌ node_modules/next'
    
    echo ''
    echo '🔧 Configuration des permissions...'
    chmod +x pm2-manager.sh 2>/dev/null && echo '✅ pm2-manager.sh rendu exécutable' || echo '⚠️ Erreur permissions'
"

echo ""
log "🎉 Déploiement terminé !"
echo ""
echo "🚀 Pour démarrer l'application avec PM2:"
echo "  ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST"
echo "  cd $SERVER_PATH"
echo "  ./pm2-manager.sh start"
echo ""
echo "� Redémarrage automatique de l'application..."
sshpass -e ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST "
    cd $SERVER_PATH
    
    # Chargement de nvm pour PM2
    export NVM_DIR=\"\$HOME/.nvm\"
    [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
    [ -s \"\$NVM_DIR/bash_completion\" ] && . \"\$NVM_DIR/bash_completion\"
    
    # Redémarrer l'application
    echo '🚀 Redémarrage de l'\''application...'
    ./pm2-manager.sh start
    sleep 2
    echo '📊 Statut final:'
    ./pm2-manager.sh status
"
echo ""
echo "✅ Application redémarrée automatiquement !"
echo ""
echo "📋 Autres commandes PM2 utiles:"
echo "  ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST 'cd $SERVER_PATH && ./pm2-manager.sh logs'"
echo "  ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST 'cd $SERVER_PATH && ./pm2-manager.sh restart'"