import { NextRequest, NextResponse } from 'next/server';

interface SourceParams {
  satellite: string;
  sector: string;
  product: string;
  resolution: string;
}

interface ImageResult {
  name: string;
  url: string;
  date?: string;
}

// Map des sources connues (à étendre facilement)
const SOURCES: Record<string, (params: SourceParams) => { url: string; parser: (html: string) => Array<ImageResult> }> = {
  'NOAA': ({ satellite, sector, product, resolution }) => {
    // Mutualisation de la logique Bash :
    // Si secteur CONUS, FD ou MESO* => .../ABI/$SECTOR_UPPER/$product/
    // Sinon => .../ABI/SECTOR/$sector/$product/
    const sector_upper = sector.toUpperCase();
    let url = '';
    if (sector_upper === 'CONUS' || sector_upper === 'FD' || sector_upper.startsWith('MESO')) {
      url = `https://cdn.star.nesdis.noaa.gov/${satellite}/ABI/${sector_upper}/${product}/`;
    } else {
      url = `https://cdn.star.nesdis.noaa.gov/${satellite}/ABI/SECTOR/${sector}/${product}/`;
    }
    return {
      url,
      parser: (html: string) => {
        // Filtrage strict : 11 chiffres + _ + ... -${resolution}.(jpg|png), insensible à la casse sur l’extension
        const pattern = new RegExp(`href="([0-9]{11}_[^"]*-(${resolution})\\.(jpg|png))"`, 'gi');
        const matches = Array.from(html.matchAll(pattern));
        // DEBUG: log le nombre d'images trouvées
        console.log(`[API/images] Résolution demandée: ${resolution}, images trouvées: ${matches.length}`);
        return matches.map(m => ({
          name: m[1],
          url: url + m[1],
        }));
      }
    };
  },
  // Ajouter d'autres sources ici
};

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const satellite = searchParams.get('satellite');
  const sector = searchParams.get('sector');
  const product = searchParams.get('product');
  const resolution = searchParams.get('resolution');
  const source = searchParams.get('source') || 'NOAA';

  if (!satellite || !sector || !product || !resolution) {
    return NextResponse.json({ success: false, error: 'Paramètres manquants' }, { status: 400 });
  }

  const sourceDef = SOURCES[source];
  if (!sourceDef) {
    return NextResponse.json({ success: false, error: `Source inconnue: ${source}` }, { status: 400 });
  }

  const { url, parser } = sourceDef({ satellite, sector, product, resolution });

  try {
    const resp = await fetch(url);
    if (!resp.ok) {
      return NextResponse.json({ success: false, error: `Erreur HTTP: ${resp.status}` }, { status: 502 });
    }
    const html = await resp.text();
    const images = parser(html);
    // LOG DEBUG
    console.log('[API/images] URL:', url);
    console.log('[API/images] Résolution:', resolution);
    console.log('[API/images] Images trouvées:', images.length);
    if (images.length > 0) {
      console.log('[API/images] Extrait:', images.slice(0, 5).map(i => i.name));
    } else {
      console.log('[API/images] Aucun nom d\'image extrait.');
    }
    return NextResponse.json({ success: true, source_url: url, images });
  } catch (err) {
    return NextResponse.json({ success: false, error: (err as Error).message }, { status: 500 });
  }
}
