import { NextRequest, NextResponse } from 'next/server';
import { exec } from 'child_process';
import { promisify } from 'util';
import path from 'path';

const execAsync = promisify(exec);

// Chemin vers le script de découverte
const DISCOVERY_SCRIPT = path.join(process.cwd(), 'scripts', 'import-all-datasets.sh');

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { action = 'discover' } = body; // 'discover' ou 'recommended'

    console.log(`🔍 Découverte des datasets: ${action}`);
    
    const command = `bash "${DISCOVERY_SCRIPT}" "${action}"`;
    
    const { stdout, stderr } = await execAsync(command, {
      timeout: 120000, // 2 minutes timeout
      cwd: process.cwd()
    });

    if (stderr && !stderr.includes('Warning')) {
      console.error('Erreur de découverte:', stderr);
      throw new Error(`Erreur de découverte: ${stderr}`);
    }

    console.log('✅ Découverte terminée');
    
    return NextResponse.json({
      success: true,
      message: `Découverte des datasets ${action} terminée`,
      output: stdout,
      action
    });

  } catch (error) {
    console.error('Erreur lors de la découverte:', error);
    return NextResponse.json(
      { 
        success: false, 
        error: error instanceof Error ? error.message : 'Erreur lors de la découverte',
        action: 'discovery'
      },
      { status: 500 }
    );
  }
}
