import { NextResponse } from 'next/server';
import { promises as fs } from 'fs';
import path from 'path';

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const date = searchParams.get('date') || new Date().toISOString().split('T')[0];
    
    // Chemin vers le dossier de logs
    const logsPath = process.env.NODE_ENV === 'production' 
      ? (process.env.DATA_PATH_PROD || '/data')
      : path.join(process.cwd(), 'public', 'data');
    
    const logsDir = path.join(logsPath, 'logs');
    
    try {
      // Vérifier si le dossier de logs existe
      await fs.access(logsDir);
    } catch {
      // Créer le dossier s'il n'existe pas
      await fs.mkdir(logsDir, { recursive: true });
      return NextResponse.json([]);
    }
    
    // Lire tous les fichiers du dossier
    const files = await fs.readdir(logsDir);
    
    // Filtrer et formater les fichiers de logs
    const logFiles = [];
    
    for (const file of files) {
      if (file.endsWith('.log') || file.endsWith('.txt')) {
        const filePath = path.join(logsDir, file);
        const stats = await fs.stat(filePath);
        
        // Extraire la date du nom de fichier ou utiliser la date de modification
        let fileDate = '';
        const dateMatch = file.match(/(\d{4}-\d{2}-\d{2})/);
        if (dateMatch) {
          fileDate = dateMatch[1];
        } else {
          fileDate = stats.mtime.toISOString().split('T')[0];
        }
        
        // Filtrer par date si spécifiée
        if (date && fileDate !== date) {
          continue;
        }
        
        logFiles.push({
          name: file,
          date: fileDate,
          size: stats.size,
          modified: stats.mtime.toISOString()
        });
      }
    }
    
    // Trier par date de modification (plus récent en premier)
    logFiles.sort((a, b) => new Date(b.modified).getTime() - new Date(a.modified).getTime());
    
    return NextResponse.json(logFiles);
    
  } catch (error) {
    console.error('Erreur lors de la récupération des fichiers de logs:', error);
    return NextResponse.json(
      { error: 'Erreur lors de la récupération des fichiers de logs' },
      { status: 500 }
    );
  }
}
