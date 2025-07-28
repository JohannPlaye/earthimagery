# Copilot Instructions pour EarthImagery

<!-- Use this file to provide workspace-specific custom instructions to Copilot. For more details, visit https://code.visualstudio.com/docs/copilot/copilot-customization#_use-a-githubcopilotinstructionsmd-file -->

## Context du projet

Cette application Next.js est conçue pour l'observation de phénomènes météorologiques via des images satellitaires :

- **Frontend** : Next.js avec TypeScript, Tailwind CSS, MUI pour les composants UI
- **Backend** : API Routes Next.js pour génération de playlists HLS
- **Traitement vidéo** : Scripts bash avec ffmpeg pour création de fragments HLS 
- **Streaming** : HLS (HTTP Live Streaming) avec hls.js pour lecture fluide
- **Stockage** : Variables d'environnement pour chemins dev/prod

## Architecture

- `/src/app` : Pages et API routes Next.js
- `/scripts` : Scripts bash pour récupération d'images et génération vidéo
- `/public/data` : Stockage des données en développement
- Variables d'environnement pour configuration dev/prod

## Conventions de code

- Utiliser TypeScript strictement typé
- Composants React fonctionnels avec hooks
- Tailwind CSS pour le styling
- MUI pour les composants complexes (DateRangePicker)
- Gestion d'erreurs robuste pour l'API
- Validation des plages de dates (max 1 an)

## Spécificités techniques

- Format HLS (.m3u8) pour streaming vidéo
- Génération dynamique de playlists sans re-encoding
- Support responsive pour mobile
- Optimisation des performances de chargement
