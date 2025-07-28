import { NextRequest, NextResponse } from 'next/server';
import { promises as fs } from 'fs';
import path from 'path';

export async function GET(
  request: NextRequest,
  { params }: { params: { path: string[] } }
) {
  try {
    const { path: pathSegments } = await params;
    
    if (!pathSegments || pathSegments.length === 0) {
      return new NextResponse('Path required', { status: 400 });
    }

    // Reconstruction du chemin
    const relativePath = pathSegments.join('/');
    const dataRootPath = process.env.DATA_ROOT_PATH || '/home/johann/developpement/earthimagery/public/data';
    const hlsDir = process.env.HLS_DIR || 'hls';
    const filePath = path.join(dataRootPath, hlsDir, relativePath);

    // Vérification de sécurité pour éviter le directory traversal
    const normalizedPath = path.normalize(filePath);
    const basePath = path.normalize(path.join(dataRootPath, hlsDir));
    
    if (!normalizedPath.startsWith(basePath)) {
      return new NextResponse('Access denied', { status: 403 });
    }

    try {
      const fileBuffer = await fs.readFile(filePath);
      
      // Déterminer le Content-Type basé sur l'extension
      let contentType = 'application/octet-stream';
      if (filePath.endsWith('.m3u8')) {
        contentType = 'application/vnd.apple.mpegurl';
      } else if (filePath.endsWith('.ts')) {
        contentType = 'video/mp2t';
      }

      return new NextResponse(fileBuffer, {
        status: 200,
        headers: {
          'Content-Type': contentType,
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
          'Access-Control-Allow-Headers': 'Range, Content-Range',
          'Cache-Control': 'public, max-age=300',
          'Accept-Ranges': 'bytes',
        },
      });

    } catch (fileError) {
      console.error('Erreur lecture fichier HLS:', fileError);
      return new NextResponse('File not found', { status: 404 });
    }

  } catch (error) {
    console.error('Erreur API HLS:', error);
    return new NextResponse('Internal server error', { status: 500 });
  }
}

export async function HEAD(
  request: NextRequest,
  { params }: { params: { path: string[] } }
) {
  const response = await GET(request, { params });
  return new NextResponse(null, {
    status: response.status,
    headers: response.headers,
  });
}

export async function OPTIONS() {
  return new NextResponse(null, {
    status: 200,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
      'Access-Control-Allow-Headers': 'Range, Content-Range',
    },
  });
}
