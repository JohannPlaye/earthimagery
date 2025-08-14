#!/bin/bash

# Script pour simuler l'ajout de logs en temps réel
LOG_FILE="/home/johann/developpement/earthimagery/public/data/logs/testcomplet_$(date +%Y-%m-%d).log"

echo "$(date '+%Y-%m-%dT%H:%M:%S') [INFO] Simulation de logs en temps réel démarrée" >> "$LOG_FILE"

# Boucle pour ajouter des logs périodiquement
for i in {1..20}; do
    sleep 5
    
    case $((i % 4)) in
        0)
            echo "$(date '+%Y-%m-%dT%H:%M:%S') [SUCCESS] ✓ Téléchargement image_$i.jpg réussi ($(($RANDOM % 3 + 1)).$(($RANDOM % 9))MB)" >> "$LOG_FILE"
            ;;
        1)
            echo "$(date '+%Y-%m-%dT%H:%M:%S') [INFO] Traitement du segment $i/20..." >> "$LOG_FILE"
            ;;
        2)
            echo "$(date '+%Y-%m-%dT%H:%M:%S') [DEBUG] Vérification de l'espace disque: $(($RANDOM % 100 + 50))GB libres" >> "$LOG_FILE"
            ;;
        3)
            if [ $((RANDOM % 10)) -eq 0 ]; then
                echo "$(date '+%Y-%m-%dT%H:%M:%S') [WARN] Connexion lente détectée, réduction de la vitesse" >> "$LOG_FILE"
            else
                echo "$(date '+%Y-%m-%dT%H:%M:%S') [INFO] Génération playlist HLS segment_$i.m3u8" >> "$LOG_FILE"
            fi
            ;;
    esac
done

echo "$(date '+%Y-%m-%dT%H:%M:%S') [SUCCESS] ✓ Script de simulation terminé" >> "$LOG_FILE"
