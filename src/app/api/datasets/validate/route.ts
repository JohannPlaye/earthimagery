import { NextRequest, NextResponse } from 'next/server';
import { exec } from 'child_process';
import { promisify } from 'util';
import path from 'path';

interface Config {
  enabled_datasets?: Record<string, unknown>;
  disabled_datasets?: Record<string, unknown>;
}

interface TrackingDataset {
  availability?: {
    last_check?: string;
  };
}

interface TrackingData {
  tracking?: Record<string, TrackingDataset>;
}

const execAsync = promisify(exec);

// Chemin vers le script de validation
const VALIDATION_SCRIPT = path.join(process.cwd(), 'scripts', 'validate-datasets.sh');

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { action = 'validate' } = body; // 'validate' ou 'discover'

    console.log(`🔧 Validation des datasets: ${action}`);
    
    const command = `bash "${VALIDATION_SCRIPT}" "${action}"`;
    
    const { stdout, stderr } = await execAsync(command, {
      timeout: 60000, // 1 minute timeout
      cwd: process.cwd()
    });

    if (stderr && !stderr.includes('Warning')) {
      console.error('Erreur de validation:', stderr);
      throw new Error(`Erreur de validation: ${stderr}`);
    }

    console.log('✅ Validation terminée');
    
    return NextResponse.json({
      success: true,
      message: `Validation des datasets ${action} terminée`,
      output: stdout,
      action
    });

  } catch (error) {
    console.error('Erreur lors de la validation:', error);
    return NextResponse.json(
      { 
        success: false, 
        error: error instanceof Error ? error.message : 'Erreur lors de la validation',
        action: 'validation'
      },
      { status: 500 }
    );
  }
}

// Endpoint GET pour obtenir le statut de validation
export async function GET() {
  try {
    // Lire le fichier de configuration pour obtenir l'état actuel
    const fs = await import('fs/promises');
    const configPath = path.join(process.cwd(), 'config', 'datasets-status.json');
    const trackingPath = path.join(process.cwd(), 'config', 'download-tracking.json');
    
    let config: Config = {};
    let tracking: TrackingData = {};
    
    try {
      const configContent = await fs.readFile(configPath, 'utf-8');
      config = JSON.parse(configContent);
    } catch {
      console.warn('Fichier de configuration non trouvé');
    }
    
    try {
      const trackingContent = await fs.readFile(trackingPath, 'utf-8');
      tracking = JSON.parse(trackingContent);
    } catch {
      console.warn('Fichier de tracking non trouvé');
    }
    
    // Calculer les statistiques de disponibilité
    const stats = {
      enabled: Object.keys(config.enabled_datasets || {}).length,
      disabled: Object.keys(config.disabled_datasets || {}).length,
      total: Object.keys(config.enabled_datasets || {}).length + 
             Object.keys(config.disabled_datasets || {}).length,
      last_validation: null as string | null
    };
    
    // Chercher la dernière validation dans le tracking
    if (tracking.tracking) {
      const validationDates = Object.values(tracking.tracking)
        .map((dataset: TrackingDataset) => dataset.availability?.last_check)
        .filter((date): date is string => Boolean(date))
        .sort()
        .reverse();
      
      if (validationDates.length > 0) {
        stats.last_validation = validationDates[0];
      }
    }
    
    return NextResponse.json({
      success: true,
      stats,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('Erreur lors de la lecture du statut:', error);
    return NextResponse.json(
      { 
        success: false, 
        error: error instanceof Error ? error.message : 'Erreur lors de la lecture du statut'
      },
      { status: 500 }
    );
  }
}
