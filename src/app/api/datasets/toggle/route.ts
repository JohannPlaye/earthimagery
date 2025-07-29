import { NextRequest, NextResponse } from 'next/server';
import { exec } from 'child_process';
import { promisify } from 'util';
import path from 'path';

const execAsync = promisify(exec);

// Chemin vers le script de gestion des datasets
const DATASET_TOGGLE_SCRIPT = path.join(process.cwd(), 'scripts', 'dataset-toggle.sh');

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { satellite, sector, product, resolution, enabled, auto_download } = body;

    // Validation des paramètres
    if (!satellite || !sector || !product || !resolution) {
      return NextResponse.json(
        { success: false, error: 'Paramètres manquants' },
        { status: 400 }
      );
    }

    if (enabled) {
      // Activer le dataset
      const autoFlag = auto_download ? 'true' : 'false';
      const command = `bash "${DATASET_TOGGLE_SCRIPT}" enable "${satellite}" "${sector}" "${product}" "${resolution}" "${autoFlag}"`;
      
      console.log(`🔧 Activation dataset: ${satellite}.${sector}.${product}.${resolution} (auto: ${autoFlag})`);
      
      const { stdout, stderr } = await execAsync(command, {
        timeout: 30000,
        cwd: process.cwd()
      });

      if (stderr && !stderr.includes('Warning')) {
        console.error('Erreur d\'activation:', stderr);
        throw new Error(`Erreur d'activation: ${stderr}`);
      }

      console.log('✅ Dataset activé');
      return NextResponse.json({
        success: true,
        message: `Dataset ${satellite}.${sector}.${product}.${resolution} activé`,
        auto_download
      });

    } else {
      // Désactiver le dataset
      const command = `bash "${DATASET_TOGGLE_SCRIPT}" disable "${satellite}" "${sector}" "${product}" "${resolution}"`;
      
      console.log(`🔧 Désactivation dataset: ${satellite}.${sector}.${product}.${resolution}`);
      
      const { stdout, stderr } = await execAsync(command, {
        timeout: 30000,
        cwd: process.cwd()
      });

      if (stderr && !stderr.includes('Warning')) {
        console.error('Erreur de désactivation:', stderr);
        throw new Error(`Erreur de désactivation: ${stderr}`);
      }

      console.log('✅ Dataset désactivé');
      return NextResponse.json({
        success: true,
        message: `Dataset ${satellite}.${sector}.${product}.${resolution} désactivé`
      });
    }

  } catch (error) {
    console.error('Erreur lors de la modification du dataset:', error);
    return NextResponse.json(
      { 
        success: false, 
        error: error instanceof Error ? error.message : 'Erreur lors de la modification'
      },
      { status: 500 }
    );
  }
}
