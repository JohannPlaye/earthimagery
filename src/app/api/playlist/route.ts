import { NextRequest, NextResponse } from 'next/server';
import { promises as fs } from 'fs';
import path from 'path';

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const from = searchParams.get('from');
    const to = searchParams.get('to');
    const satellite = searchParams.get('satellite');
    const sector = searchParams.get('sector');
    const product = searchParams.get('product');
    const resolution = searchParams.get('resolution');

    // Validation des paramètres
    if (!from || !to || !satellite || !sector || !product || !resolution) {
      return NextResponse.json(
        { error: 'Paramètres "from", "to", "satellite", "sector", "product", "resolution" requis' },
        { status: 400 }
      );
    }

    // Validation du format de date
    const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
    if (!dateRegex.test(from) || !dateRegex.test(to)) {
      return NextResponse.json(
        { error: 'Format de date invalide. Utilisez YYYY-MM-DD' },
        { status: 400 }
      );
    }

    const fromDate = new Date(from);
    const toDate = new Date(to);

    // Validation de la plage de dates
    if (fromDate > toDate) {
      return NextResponse.json(
        { error: 'La date de début doit être antérieure à la date de fin' },
        { status: 400 }
      );
    }

    // Limitation de la plage (sécurité)
    const maxRangeDays = parseInt(process.env.MAX_DATE_RANGE_DAYS || '365');
    const diffTime = Math.abs(toDate.getTime() - fromDate.getTime());
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));

    if (diffDays > maxRangeDays) {
      return NextResponse.json(
        { error: `Plage de dates trop large. Maximum: ${maxRangeDays} jours` },
        { status: 400 }
      );
    }

    // Génération de la playlist
    const playlist = await generatePlaylist(fromDate, toDate, satellite, sector, product, resolution);

    // Vérifier si la playlist contient des segments
    if (!playlist.includes('#EXTINF')) {
      return NextResponse.json(
        { error: 'Aucune vidéo disponible pour cette période' },
        { status: 404 }
      );
    }

    return new NextResponse(playlist, {
      status: 200,
      headers: {
        'Content-Type': 'application/vnd.apple.mpegurl',
        'Cache-Control': 'public, max-age=300', // Cache 5 minutes
      },
    });

  } catch (error) {
    console.error('Erreur génération playlist:', error);
    return NextResponse.json(
      { error: 'Erreur interne du serveur' },
      { status: 500 }
    );
  }
}

async function generatePlaylist(fromDate: Date, toDate: Date, satellite: string, sector: string, product: string, resolution: string): Promise<string> {
  const dataRootPath = process.env.DATA_ROOT_PATH || '/home/johann/developpement/earthimagery/public/data';
  const hlsDir = process.env.HLS_DIR || 'hls';
  // Use new dot notation for datasetDir: {satellite}.{sector}.{product}.{resolution}
  const datasetDir = `${satellite}.${sector}.${product}.${resolution}`;

  const segments: string[] = [];
  let maxDuration = 0;

  // Parcourir chaque jour dans la plage
  const currentDate = new Date(fromDate);
  while (currentDate <= toDate) {
    const dateStr = currentDate.toISOString().split('T')[0];
    const dayHlsPath = path.join(dataRootPath, hlsDir, datasetDir, dateStr);
    const playlistPath = path.join(dayHlsPath, 'playlist.m3u8');

    try {
      // Vérifier si le fichier playlist existe
      await fs.access(playlistPath);
      
      // Lire la playlist du jour
      const dayPlaylistContent = await fs.readFile(playlistPath, 'utf-8');
      const lines = dayPlaylistContent.split('\n');

      for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        if (line.startsWith('#EXTINF:')) {
          // Extraire la durée du segment
          const duration = parseFloat(line.split(':')[1].split(',')[0]);
          maxDuration = Math.max(maxDuration, duration);
          
          // Ajouter l'info du segment
          segments.push(line);
          
          // Ajouter le nom du fichier segment (ligne suivante)
          if (i + 1 < lines.length) {
            const segmentFile = lines[i + 1].trim();
            if (segmentFile && !segmentFile.startsWith('#')) {
              // Construire l'URL vers la route API HLS (dot notation)
              const segmentUrl = `/api/hls/${datasetDir}/${dateStr}/${segmentFile}`;
              segments.push(segmentUrl);
            }
          }
        }
      }

    } catch {
      // Le fichier n'existe pas pour ce jour, continuer
      console.warn(`Aucune vidéo trouvée pour ${datasetDir}/${dateStr}`);
    }

    // Jour suivant
    currentDate.setDate(currentDate.getDate() + 1);
  }

  // Construire la playlist finale
  let playlistContent = '#EXTM3U\n';
  playlistContent += '#EXT-X-VERSION:3\n';
  playlistContent += '#EXT-X-PLAYLIST-TYPE:VOD\n';
  playlistContent += `#EXT-X-TARGETDURATION:${Math.ceil(maxDuration) || 12}\n`;
  playlistContent += `#EXT-X-MEDIA-SEQUENCE:0\n`;

  // Ajouter les segments
  segments.forEach(segment => {
    playlistContent += segment + '\n';
  });

  playlistContent += '#EXT-X-ENDLIST\n';

  return playlistContent;
}

// Endpoint pour obtenir des informations sur la période disponible
export async function POST(request: NextRequest) {
  try {
    const { from, to } = await request.json();

    if (!from || !to) {
      return NextResponse.json(
        { error: 'Paramètres "from" et "to" requis' },
        { status: 400 }
      );
    }

    const info = await getDateRangeInfo(from, to);
    return NextResponse.json(info);

  } catch (error) {
    console.error('Erreur info playlist:', error);
    return NextResponse.json(
      { error: 'Erreur interne du serveur' },
      { status: 500 }
    );
  }
}

async function getDateRangeInfo(from: string, to: string) {
  const dataRootPath = process.env.DATA_ROOT_PATH || '/home/johann/developpement/earthimagery/public/data';
  const hlsDir = process.env.HLS_DIR || 'hls';
  
  const fromDate = new Date(from);
  const toDate = new Date(to);
  
  let availableDays = 0;
  let totalSegments = 0;
  let estimatedDuration = 0;

  const currentDate = new Date(fromDate);
  while (currentDate <= toDate) {
    const dateStr = currentDate.toISOString().split('T')[0];
    const dayHlsPath = path.join(dataRootPath, hlsDir, dateStr);
    
    try {
      const files = await fs.readdir(dayHlsPath);
      const segmentFiles = files.filter(file => file.endsWith('.ts'));
      
      if (segmentFiles.length > 0) {
        availableDays++;
        totalSegments += segmentFiles.length;
        
        // Estimation de durée (segments de 10s par défaut)
        const segmentTime = parseInt(process.env.HLS_SEGMENT_TIME || '10');
        estimatedDuration += segmentFiles.length * segmentTime;
      }
    } catch {
      // Dossier n'existe pas pour ce jour
    }

    currentDate.setDate(currentDate.getDate() + 1);
  }

  return {
    availableDays,
    totalSegments,
    estimatedDurationSeconds: estimatedDuration,
    estimatedDurationFormatted: formatDuration(estimatedDuration)
  };
}

function formatDuration(seconds: number): string {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;

  if (hours > 0) {
    return `${hours}h ${minutes}m ${secs}s`;
  } else if (minutes > 0) {
    return `${minutes}m ${secs}s`;
  } else {
    return `${secs}s`;
  }
}
