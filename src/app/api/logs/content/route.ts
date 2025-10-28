import { NextResponse } from 'next/server';
import { promises as fs } from 'fs';
import path from 'path';

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const filename = searchParams.get('file');
    const isStreaming = searchParams.get('stream') === 'true';
    
    if (!filename) {
      return NextResponse.json(
        { error: 'Nom de fichier requis' },
        { status: 400 }
      );
    }
    
    // Validation du nom de fichier pour éviter les path traversal
    if (filename.includes('..') || filename.includes('/') || filename.includes('\\')) {
      return NextResponse.json(
        { error: 'Nom de fichier invalide' },
        { status: 400 }
      );
    }
    
    // Chemin vers le dossier de logs (même logique que les scripts)
    const logsPath = path.join(process.cwd(), 'public', 'data');
    
    const filePath = path.join(logsPath, 'logs', filename);
    
    try {
      // Vérifier si le fichier existe
      await fs.access(filePath);
    } catch {
      return NextResponse.json(
        { error: 'Fichier de log non trouvé' },
        { status: 404 }
      );
    }
    
    // Lire le contenu du fichier
    const content = await fs.readFile(filePath, 'utf-8');
    
    if (isStreaming) {
      // En mode streaming, on pourrait implémenter une logique pour ne retourner
      // que les nouvelles lignes depuis la dernière lecture, mais pour simplifier
      // on retourne tout le contenu et le client se charge de filtrer
      
      // Retourner seulement les dernières lignes (par exemple les 100 dernières)
      const lines = content.split('\n');
      const lastLines = lines.slice(-100).join('\n');
      
      return new NextResponse(lastLines, {
        headers: {
          'Content-Type': 'text/plain; charset=utf-8',
          'Cache-Control': 'no-cache, no-store, must-revalidate',
        },
      });
    }
    
    return new NextResponse(content, {
      headers: {
        'Content-Type': 'text/plain; charset=utf-8',
      },
    });
    
  } catch (error) {
    console.error('Erreur lors de la lecture du fichier de log:', error);
    return NextResponse.json(
      { error: 'Erreur lors de la lecture du fichier de log' },
      { status: 500 }
    );
  }
}
