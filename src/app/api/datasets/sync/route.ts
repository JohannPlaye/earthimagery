import { NextRequest, NextResponse } from 'next/server';
import { exec } from 'child_process';
import { promisify } from 'util';
import path from 'path';

const execAsync = promisify(exec);

// Chemin vers le script de gestion des datasets
const REAL_DATA_SCRIPT = path.join(process.cwd(), 'scripts', 'real-data-helpers.sh');

export async function POST() {
  try {
    console.log('🔄 Lancement de la synchronisation...');
    
    // Exécuter le script de synchronisation
    const { stdout, stderr } = await execAsync(`bash "${REAL_DATA_SCRIPT}" sync`, {
      timeout: 60000, // 1 minute
      cwd: process.cwd()
    });

    if (stderr && !stderr.includes('Warning')) {
      console.error('Erreur de synchronisation:', stderr);
      throw new Error(`Erreur de synchronisation: ${stderr}`);
    }

    console.log('✅ Synchronisation terminée');
    return NextResponse.json({
      success: true,
      message: 'Synchronisation des datasets terminée',
      output: stdout
    });

  } catch (error) {
    console.error('Erreur lors de la synchronisation:', error);
    return NextResponse.json(
      { 
        success: false, 
        error: error instanceof Error ? error.message : 'Erreur lors de la synchronisation'
      },
      { status: 500 }
    );
  }
}
