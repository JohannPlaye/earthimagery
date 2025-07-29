import { NextRequest, NextResponse } from 'next/server';
import fs from 'fs/promises';
import path from 'path';

interface SatellitePlaylist {
  satellite: string;
  sector: string;
  product: string;
  resolution: string;
  date: string;
  playlist_url: string;
  segments: number;
  duration: number;
  file_size: number;
}

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const satellite = searchParams.get('satellite');
    const sector = searchParams.get('sector');
    const product = searchParams.get('product');
    const resolution = searchParams.get('resolution');

    const hlsDir = path.join(process.cwd(), 'public', 'data', 'hls');
    
    // Si des paramètres spécifiques sont fournis, chercher cette combinaison
    if (satellite && sector && product && resolution) {
      const specificDir = path.join(hlsDir, `${satellite}.${sector}.${product}.${resolution}`);
      
      try {
        const dates = await fs.readdir(specificDir);
        const playlists: SatellitePlaylist[] = [];

        for (const date of dates) {
          const datePath = path.join(specificDir, date);
          const playlistPath = path.join(datePath, 'playlist.m3u8');
          
          try {
            const stats = await fs.stat(playlistPath);
            const playlistContent = await fs.readFile(playlistPath, 'utf-8');
            
            // Compter les segments
            const segments = (playlistContent.match(/#EXTINF:/g) || []).length;
            
            // Calculer la durée totale
            const durations = playlistContent.match(/#EXTINF:([\d.]+),/g) || [];
            const totalDuration = durations.reduce((sum, line) => {
              const match = line.match(/#EXTINF:([\d.]+),/);
              return sum + (match ? parseFloat(match[1]) : 0);
            }, 0);

            playlists.push({
              satellite,
              sector,
              product,
              resolution,
              date,
              playlist_url: `/data/hls/${satellite}.${sector}.${product}.${resolution}/${date}/playlist.m3u8`,
              segments,
              duration: Math.round(totalDuration),
              file_size: stats.size
            });
          } catch (error) {
            // Ignorer les erreurs pour les dossiers/fichiers non valides
          }
        }

        // Trier par date décroissante
        playlists.sort((a, b) => b.date.localeCompare(a.date));

        return NextResponse.json({
          success: true,
          playlists,
          total: playlists.length
        });

      } catch (error) {
        return NextResponse.json({
          success: true,
          playlists: [],
          total: 0,
          message: 'Aucune vidéo trouvée pour cette combinaison'
        });
      }
    }

    // Sinon, scanner tous les dossiers satellitaires
    try {
      const entries = await fs.readdir(hlsDir);
      // Chercher les dossiers au format SATELLITE.SECTOR.PRODUCT.RESOLUTION
      const satelliteDirs = entries.filter(name => name.includes('.') && name.split('.').length === 4);
      
      const allPlaylists: SatellitePlaylist[] = [];

      for (const satDir of satelliteDirs) {
        // Parser le nom du dossier: GOES18.hi.GEOCOLOR.600x600
        const parts = satDir.split('.');
        if (parts.length === 4) {
          const [sat, sect, prod, res] = parts;

          const satPath = path.join(hlsDir, satDir);
          try {
            const dates = await fs.readdir(satPath);
            
            for (const date of dates) {
              const datePath = path.join(satPath, date);
              const playlistPath = path.join(datePath, 'playlist.m3u8');
              
              try {
                const stats = await fs.stat(playlistPath);
                const playlistContent = await fs.readFile(playlistPath, 'utf-8');
                
                const segments = (playlistContent.match(/#EXTINF:/g) || []).length;
                const durations = playlistContent.match(/#EXTINF:([\d.]+),/g) || [];
                const totalDuration = durations.reduce((sum, line) => {
                  const match = line.match(/#EXTINF:([\d.]+),/);
                  return sum + (match ? parseFloat(match[1]) : 0);
                }, 0);

                allPlaylists.push({
                  satellite: sat,
                  sector: sect,
                  product: prod,
                  resolution: res,
                  date,
                  playlist_url: `/data/hls/${satDir}/${date}/playlist.m3u8`,
                  segments,
                  duration: Math.round(totalDuration),
                  file_size: stats.size
                });
              } catch (error) {
                // Ignorer les erreurs de fichiers individuels
              }
            }
          } catch (error) {
            // Ignorer les erreurs de dossiers individuels
          }
        }
      }

      // Trier par date décroissante
      allPlaylists.sort((a, b) => b.date.localeCompare(a.date));

      return NextResponse.json({
        success: true,
        playlists: allPlaylists,
        total: allPlaylists.length
      });

    } catch (error) {
      return NextResponse.json({
        success: true,
        playlists: [],
        total: 0,
        message: 'Répertoire HLS non trouvé'
      });
    }

  } catch (error) {
    console.error('Erreur lors de la récupération des playlists satellitaires:', error);
    return NextResponse.json(
      { 
        success: false, 
        error: error instanceof Error ? error.message : 'Erreur serveur'
      },
      { status: 500 }
    );
  }
}
