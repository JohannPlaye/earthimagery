#!/bin/bash

# =============================================================================
# SCRIPT DE DÉPLOIEMENT EARTHIMAGERY
# =============================================================================
# Déploie l'application Next.js buildée sur le serveur de production
# Version: 3.0 - Avec authentification unique et option --clean
# 
# Usage:
#   ./deploy.sh           # Déploiement rapide (défaut)
#   ./deploy.sh --clean   # Déploiement avec nettoyage complet
# =============================================================================

set -euo pipefail

# Configuration du serveur
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
                show_deployment_help
                exit 0
                ;;
            *)
                echo "❌ Argument inconnu: $1"
                show_deployment_help
                exit 1
                ;;
        esac
    done
}

# Affichage de l'aide
show_deployment_help() {
    echo "🌍 EarthImagery - Script de Déploiement Principal"
    echo "================================================"
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

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Demande du mot de passe une seule fois
prompt_password() {
    echo "🔐 Authentification SSH"
    echo "======================="
    read -s -p "Mot de passe SSH pour $SERVER_USER@$SERVER_HOST: " SSH_PASSWORD
    echo ""
    export SSHPASS="$SSH_PASSWORD"
    log "INFO" "Mot de passe configuré pour la session"
}

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $timestamp - $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $timestamp - $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $timestamp - $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $timestamp - $message" ;;
    esac
}

# Vérifications préalables
check_prerequisites() {
    log "INFO" "🔍 Vérification des prérequis..."
    
    # Vérifier que le build existe
    if [ ! -d ".next" ]; then
        log "ERROR" "Le répertoire .next n'existe pas. Lancez 'npm run build' d'abord."
        exit 1
    fi
    
    # Vérifier que node_modules existe
    if [ ! -d "node_modules" ]; then
        log "ERROR" "Le répertoire node_modules n'existe pas. Lancez 'npm install' d'abord."
        exit 1
    fi
    
    # Vérifier SSH
    if ! command -v ssh &> /dev/null; then
        log "ERROR" "SSH n'est pas installé."
        exit 1
    fi
    
    # Test de connexion SSH
    log "INFO" "🔐 Test de connexion SSH..."
    if ! ssh -p $SERVER_PORT -o ConnectTimeout=10 -o BatchMode=yes $SERVER_USER@$SERVER_HOST "echo 'Connexion OK'" &>/dev/null; then
        log "WARN" "Impossible de se connecter automatiquement. Assurez-vous que:"
        log "WARN" "  - La clé SSH est configurée"
        log "WARN" "  - Le serveur est accessible"
        log "WARN" "La connexion sera tentée lors du déploiement..."
    else
        log "INFO" "✅ Connexion SSH OK"
    fi
    
    log "INFO" "✅ Prérequis vérifiés"
}

# Affichage des informations de déploiement
show_deployment_info() {
    log "INFO" "📊 Informations de déploiement:"
    echo ""
    echo "🎯 Serveur cible:"
    echo "   Host: $SERVER_HOST"
    echo "   Port: $SERVER_PORT"
    echo "   User: $SERVER_USER"
    echo "   Path: $SERVER_PATH"
    echo ""
    echo "📦 Fichiers à déployer:"
    echo "   📁 .next/ ($(du -sh .next | cut -f1))"
    echo "   📁 node_modules/ ($(du -sh node_modules | cut -f1))"
    echo "   📁 config/ ($(du -sh config | cut -f1))"
    echo "   📁 public/ ($(du -sh public | cut -f1))"
    echo "   📁 scripts/ ($(du -sh scripts | cut -f1))"
    echo "   📄 package.json"
    echo "   📄 next.config.ts"
    echo "   📄 package-lock.json"
    echo "   📄 .env.local"
    echo ""
}

# Création du répertoire sur le serveur
prepare_server() {
    log "INFO" "🏗️ Préparation du serveur..."
    
    sshpass -e ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST "
        mkdir -p $SERVER_PATH
        cd $SERVER_PATH
        echo 'Répertoire préparé sur le serveur'
    "
    
    log "INFO" "✅ Serveur préparé"
}

# Arrêt de l'application en cours
stop_running_app() {
    log "INFO" "🛑 Vérification et arrêt de l'application en cours..."
    
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
                echo '✅ Application arrêtée avec succès'
            else
                echo 'ℹ️  Aucune application EarthImagery en cours d'\''exécution'
            fi
        else
            echo 'ℹ️  PM2 non installé ou non accessible'
        fi
    "
    
    log "INFO" "✅ Vérification de l'application terminée"
}

# Déploiement des fichiers
deploy_files() {
    log "INFO" "🚀 Début du déploiement des fichiers..."
    
    # Fonction helper pour copier avec rsync
    copy_with_rsync() {
        local source="$1"
        local description="$2"
        local extra_options="$3"
        
        log "INFO" "📁 Copie de $description..."
        
        # Options rsync robustes
        local rsync_options="-avz --progress --partial --inplace $extra_options"
        
        if sshpass -e rsync $rsync_options -e "ssh -p $SERVER_PORT" "$source" $SERVER_USER@$SERVER_HOST:$SERVER_PATH/; then
            log "INFO" "✅ $description copié avec succès"
        else
            local exit_code=$?
            log "WARN" "⚠️ Erreur lors de la copie de $description (code: $exit_code)"
            if [ $exit_code -eq 23 ]; then
                log "WARN" "Code 23: Certains fichiers non transférés, mais copie partiellement réussie"
                log "INFO" "Tentative de continuation..."
            else
                log "ERROR" "Erreur critique lors de la copie de $description"
                return $exit_code
            fi
        fi
    }
    
    # Vérifier l'espace disque sur le serveur
    log "INFO" "💾 Vérification de l'espace disque sur le serveur..."
    ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST "
        echo '📊 Espace disque disponible:'
        df -h $SERVER_PATH || df -h .
        echo ''
        echo '📁 Permissions du répertoire:'
        ls -ld $SERVER_PATH 2>/dev/null || echo 'Répertoire à créer'
    "
    
    # Copie des répertoires principaux avec options adaptées
    # IMPORTANT: Tous sans slash final pour copier les répertoires eux-mêmes
    copy_with_rsync ".next" "Build Next.js (.next/)" "--delete --exclude='data/'"
    copy_with_rsync "node_modules" "Dépendances (node_modules/)" "--delete --exclude='*.log' --exclude='.cache' --exclude='data/'"
    copy_with_rsync "config" "Configuration de l'application (config/)" "--delete --exclude='data/'"
    copy_with_rsync "public" "Assets statiques (public/)" "--delete --exclude='data/'"
    copy_with_rsync "scripts" "Scripts de production (scripts/)" "--delete --exclude='data/'"
    
    # Copie des fichiers de configuration avec scp (plus fiable pour les petits fichiers)
    log "INFO" "📄 Copie des fichiers de configuration..."
    if sshpass -e scp -P $SERVER_PORT package.json package-lock.json next.config.ts pm2.config.json pm2-manager.sh .env.local $SERVER_USER@$SERVER_HOST:$SERVER_PATH/; then
        log "INFO" "✅ Fichiers de configuration copiés"
        
        # Rendre pm2-manager.sh exécutable
        log "INFO" "🔧 Configuration des permissions..."
        if sshpass -e ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST "chmod +x $SERVER_PATH/pm2-manager.sh"; then
            log "INFO" "✅ Permissions configurées"
        else
            log "WARN" "⚠️ Erreur lors de la configuration des permissions"
        fi
    else
        log "WARN" "⚠️ Erreur lors de la copie des fichiers de configuration"
    fi
    
    # Installation des dépendances sur le serveur distant
    if [ "$CLEAN_INSTALL" = true ]; then
        log "INFO" "🧹 Nettoyage et réinstallation complète des dépendances..."
        if sshpass -e ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST "
            # Chargement de nvm et activation de la version courante
            export NVM_DIR=\"\$HOME/.nvm\"
            [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
            [ -s \"\$NVM_DIR/bash_completion\" ] && . \"\$NVM_DIR/bash_completion\"
            
            # Nettoyage complet et réinstallation
            cd $SERVER_PATH && rm -rf node_modules package-lock.json && npm install --production
        "; then
            log "INFO" "✅ Dépendances réinstallées avec succès (mode propre)"
        else
            log "WARN" "⚠️ Erreur lors de l'installation propre des dépendances"
        fi
    else
        log "INFO" "📦 Installation des dépendances sur le serveur..."
        if sshpass -e ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST "
            # Chargement de nvm et activation de la version courante
            export NVM_DIR=\"\$HOME/.nvm\"
            [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
            [ -s \"\$NVM_DIR/bash_completion\" ] && . \"\$NVM_DIR/bash_completion\"
            
            # Aller dans le répertoire et installer les dépendances
            cd $SERVER_PATH && npm install --production
        "; then
            log "INFO" "✅ Dépendances installées avec succès"
        else
            log "WARN" "⚠️ Erreur lors de l'installation des dépendances"
        fi
    fi    log "INFO" "🎉 Déploiement des fichiers terminé"
}

# Vérification post-déploiement
verify_deployment() {
    log "INFO" "🔍 Vérification du déploiement..."
    
    sshpass -e ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST "
        cd $SERVER_PATH
        echo '📊 Contenu du répertoire de déploiement:'
        ls -la
        echo ''
        echo '📁 Vérification des répertoires critiques:'
        [ -d '.next' ] && echo '✅ .next/ présent' || echo '❌ .next/ manquant'
        [ -d 'node_modules' ] && echo '✅ node_modules/ présent' || echo '❌ node_modules/ manquant'
        [ -d 'config' ] && echo '✅ config/ présent' || echo '❌ config/ manquant'
        [ -d 'public' ] && echo '✅ public/ présent' || echo '❌ public/ manquant'
        [ -d 'scripts' ] && echo '✅ scripts/ présent' || echo '❌ scripts/ manquant'
        [ -f 'package.json' ] && echo '✅ package.json présent' || echo '❌ package.json manquant'
        [ -f 'next.config.ts' ] && echo '✅ next.config.ts présent' || echo '❌ next.config.ts manquant'
        [ -f '.env.local' ] && echo '✅ .env.local présent' || echo '❌ .env.local manquant'
        echo ''
        echo '🆔 Build ID:'
        cat .next/BUILD_ID 2>/dev/null || echo 'BUILD_ID non trouvé'
    "
    
    log "INFO" "✅ Vérification terminée"
}

# Instructions de démarrage
show_startup_instructions() {
    echo ""
    log "INFO" "🚀 Redémarrage automatique de l'application..."
    
    # Redémarrage automatique
    sshpass -e ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST "
        cd $SERVER_PATH
        
        # Chargement de nvm pour PM2
        export NVM_DIR=\"\$HOME/.nvm\"
        [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
        [ -s \"\$NVM_DIR/bash_completion\" ] && . \"\$NVM_DIR/bash_completion\"
        
        # Redémarrer l'application
        echo '🚀 Redémarrage de l'\''application...'
        ./pm2-manager.sh start
        sleep 3
        echo ''
        echo '� Statut final de l'\''application:'
        ./pm2-manager.sh status
    "
    
    echo ""
    log "INFO" "✅ Application redémarrée automatiquement !"
    echo ""
    echo "🌐 L'application est accessible sur:"
    echo "    http://$SERVER_HOST:11000"
    echo ""
    echo "📋 Commandes utiles pour la gestion:"
    echo "    ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST 'cd $SERVER_PATH && ./pm2-manager.sh logs'"
    echo "    ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST 'cd $SERVER_PATH && ./pm2-manager.sh restart'"
    echo "    ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST 'cd $SERVER_PATH && ./pm2-manager.sh stop'"
    echo ""
}

# Fonction principale
main() {
    echo ""
    echo "🌍 EarthImagery - Script de déploiement"
    echo "========================================"
    
    # Analyse des arguments
    parse_arguments "$@"
    
    if [ "$CLEAN_INSTALL" = true ]; then
        echo "🧹 Mode nettoyage complet activé"
    fi
    echo ""
    
    prompt_password
    check_prerequisites
    show_deployment_info
    
    # Confirmation avant déploiement
    read -p "Voulez-vous continuer le déploiement ? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Déploiement annulé."
        exit 0
    fi
    
    stop_running_app
    prepare_server
    deploy_files
    verify_deployment
    show_startup_instructions
    
    log "INFO" "🎉 Déploiement terminé avec succès !"
}

# Point d'entrée
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi