import { NextRequest, NextResponse } from 'next/server';
import { exec } from 'child_process';
import { promisify } from 'util';
import path from 'path';

const execAsync = promisify(exec);

// Chemins vers les scripts de découverte
const DISCOVERY_SCRIPT = path.join(process.cwd(), 'scripts', 'import-all-datasets.sh');
const SATELLITE_DISCOVERY_SCRIPT = path.join(process.cwd(), 'scripts', 'satellite-discovery.sh');

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { action = 'discover', mode = 'standard' } = body; // action: 'discover'|'recommended', mode: 'standard'|'comprehensive'

    console.log(`🔍 Découverte des datasets: ${action} (mode: ${mode})`);
    
    // Choisir le script selon le mode
    const scriptPath = mode === 'comprehensive' ? SATELLITE_DISCOVERY_SCRIPT : DISCOVERY_SCRIPT;
    const command = mode === 'comprehensive' ? `bash "${scriptPath}"` : `bash "${scriptPath}" "${action}"`;
    
    const { stdout, stderr } = await execAsync(command, {
      timeout: mode === 'comprehensive' ? 300000 : 120000, // 5 minutes pour comprehensive, 2 minutes pour standard
      cwd: process.cwd()
    });

    if (stderr && !stderr.includes('Warning')) {
      console.error('Erreur de découverte:', stderr);
      throw new Error(`Erreur de découverte: ${stderr}`);
    }

    console.log('✅ Découverte terminée');
    
    return NextResponse.json({
      success: true,
      message: `Découverte ${mode} des datasets ${action} terminée`,
      output: stdout,
      action,
      mode
    });

  } catch (error) {
    const body = await request.json().catch(() => ({}));
    const mode = body.mode || 'standard';
    
    console.error('Erreur lors de la découverte:', error);
    return NextResponse.json(
      { 
        success: false, 
        error: error instanceof Error ? error.message : 'Erreur lors de la découverte',
        action: 'discovery',
        mode: mode
      },
      { status: 500 }
    );
  }
}
