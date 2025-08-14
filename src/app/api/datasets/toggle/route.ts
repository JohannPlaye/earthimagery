import { NextRequest, NextResponse } from 'next/server';
import { exec } from 'child_process';
import { promisify } from 'util';
import path from 'path';
import fs from 'fs';
import { getAuthenticatedUser, hasPermission } from '@/lib/auth-middleware';

interface DatasetConfig {
  satellite: string;
  sector: string;
  product: string;
  resolution: string;
  enabled: boolean;
  auto_download: boolean;
  default_display: boolean;
}

interface Config {
  enabled_datasets: Record<string, DatasetConfig>;
  disabled_datasets?: Record<string, DatasetConfig>;
}

const execAsync = promisify(exec);

// Chemin vers le script de gestion des datasets
const DATASET_TOGGLE_SCRIPT = path.join(process.cwd(), 'scripts', 'dataset-toggle.sh');

export async function POST(request: NextRequest) {
  try {
    // Vérification de l'authentification
    const user = await getAuthenticatedUser(request);
    if (!user || !hasPermission(user, 'dataset_manage')) {
      return NextResponse.json(
        { success: false, error: 'Accès non autorisé' },
        { status: 403 }
      );
    }

    const body = await request.json();
    const { satellite, sector, product, resolution, enabled, auto_download, download_only, setDefault } = body;

    // Validation des paramètres
    if (!satellite || !sector || !product || !resolution) {
      return NextResponse.json(
        { success: false, error: 'Paramètres manquants' },
        { status: 400 }
      );
    }

    if (setDefault) {
      // Exclusivité : retire le flag default_display de tous les autres datasets
      const configPath = path.join(process.cwd(), 'config', 'datasets-status.json');
      const datasetKey = `${satellite}.${sector}.${product}.${resolution}`;
      const config: Config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
      
      // S'assurer que le dataset est bien dans enabled_datasets
      if (!config.enabled_datasets[datasetKey]) {
        // Si absent, l'activer avec les paramètres par défaut
        config.enabled_datasets[datasetKey] = {
          satellite, sector, product, resolution, enabled: true, auto_download: auto_download || false, default_display: true
        };
      } else {
        // Si déjà présent, mettre à jour ses paramètres
        config.enabled_datasets[datasetKey].enabled = true;
        config.enabled_datasets[datasetKey].default_display = true;
        if (auto_download !== undefined) {
          config.enabled_datasets[datasetKey].auto_download = auto_download;
        }
      }
      
      // Mettre default_display à false pour tous les autres datasets (enabled ET disabled)
      for (const key of Object.keys(config.enabled_datasets)) {
        if (key !== datasetKey) {
          config.enabled_datasets[key].default_display = false;
        }
      }
      // Nettoyer aussi les datasets désactivés
      if (config.disabled_datasets) {
        for (const key of Object.keys(config.disabled_datasets)) {
          config.disabled_datasets[key].default_display = false;
        }
      }
      
      fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
      
      console.log(`✅ Dataset ${datasetKey} défini comme affiché par défaut`);
      return NextResponse.json({ 
        success: true, 
        message: `Dataset ${datasetKey} défini comme affiché par défaut.`,
        default_display: true
      });
    }

    if (download_only) {
      // Modifier uniquement le statut de téléchargement automatique
      const command = `bash "${DATASET_TOGGLE_SCRIPT}" toggle-download "${satellite}" "${sector}" "${product}" "${resolution}" "${auto_download ? 'true' : 'false'}"`;
      
      console.log(`🔧 Modification téléchargement: ${satellite}.${sector}.${product}.${resolution} (auto: ${auto_download})`);
      
      const { stderr } = await execAsync(command, {
        timeout: 30000,
        cwd: process.cwd()
      });

      if (stderr && !stderr.includes('Warning')) {
        console.error('Erreur de modification téléchargement:', stderr);
        throw new Error(`Erreur de modification: ${stderr}`);
      }

      console.log('✅ Téléchargement modifié');
      return NextResponse.json({
        success: true,
        message: `Téléchargement ${satellite}.${sector}.${product}.${resolution} ${auto_download ? 'activé' : 'désactivé'}`,
        auto_download
      });

    } else if (enabled) {
      // Activer le dataset
      const autoFlag = auto_download ? 'true' : 'false';
      const command = `bash "${DATASET_TOGGLE_SCRIPT}" enable "${satellite}" "${sector}" "${product}" "${resolution}" "${autoFlag}"`;
      
      console.log(`🔧 Activation dataset: ${satellite}.${sector}.${product}.${resolution} (auto: ${autoFlag})`);
      
      const { stderr } = await execAsync(command, {
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
      
      const { stderr } = await execAsync(command, {
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
    console.error('Erreur dans le traitement de la requête:', error);
    return NextResponse.json(
      { success: false, error: 'Erreur interne du serveur' },
      { status: 500 }
    );
  }
}
