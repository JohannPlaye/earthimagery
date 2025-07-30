import { NextRequest, NextResponse } from 'next/server';
import fs from 'fs/promises';
import path from 'path';

interface Dataset {
  key: string;
  satellite: string;
  sector: string;
  product: string;
  resolution: string;
  enabled: boolean;
  auto_download: boolean;
  last_download?: string;
  status: 'available' | 'downloaded' | 'processing' | 'error' | 'discovered';
  total_images?: number;
  description?: string;
  discovered_date?: string;
  disabled_reason?: string;
}

// Chemins vers les fichiers de configuration
const TRACKING_FILE = path.join(process.cwd(), 'config', 'download-tracking.json');
const CONFIG_FILE = path.join(process.cwd(), 'config', 'datasets-status.json');

// Obtenir le statut des datasets
export async function GET() {
  try {
    const datasets: Dataset[] = [];
    
    // Lire la configuration des datasets
    let configData: any = {};
    try {
      const configContent = await fs.readFile(CONFIG_FILE, 'utf-8');
      configData = JSON.parse(configContent);
    } catch (err) {
      console.warn('Fichier de configuration datasets non trouvé, utilisation du tracking uniquement');
    }
    
    // Lire le fichier de tracking pour les informations de téléchargement
    let trackingData: any = { tracking: {} };
    try {
      const trackingContent = await fs.readFile(TRACKING_FILE, 'utf-8');
      trackingData = JSON.parse(trackingContent);
    } catch (err) {
      console.warn('Fichier de tracking non trouvé');
    }
    
    // Traiter les datasets activés
    if (configData.enabled_datasets) {
      for (const [datasetKey, datasetConfig] of Object.entries(configData.enabled_datasets)) {
        const config = datasetConfig as any;
        const trackingInfo = trackingData.tracking?.[datasetKey] || {};
        
        const dataset: Dataset = {
          key: datasetKey,
          satellite: config.satellite || '',
          sector: config.sector || '',
          product: config.product || '',
          resolution: config.resolution || '',
          enabled: true,
          auto_download: config.auto_download || false,
          last_download: trackingInfo.last_download || config.re_enabled_date,
          status: trackingInfo.total_images_downloaded > 0 ? 'downloaded' : 'available',
          total_images: trackingInfo.total_images_downloaded || 0,
          description: config.description || `${config.satellite} ${config.sector} ${config.product} ${config.resolution}`
        };
        
        datasets.push(dataset);
      }
    }
    
    // Traiter les datasets désactivés
    if (configData.disabled_datasets) {
      for (const [datasetKey, datasetConfig] of Object.entries(configData.disabled_datasets)) {
        const config = datasetConfig as any;
        const trackingInfo = trackingData.tracking?.[datasetKey] || {};
        
        // Déterminer le status : 'error' seulement s'il y a une raison explicite de désactivation
        let status: Dataset['status'] = 'available';
        if (config.disabled_reason && config.disabled_reason.includes('inactive')) {
          status = 'error';
        } else if (trackingInfo.total_images_downloaded > 0) {
          status = 'downloaded';
        }
        
        const dataset: Dataset = {
          key: datasetKey,
          satellite: config.satellite || '',
          sector: config.sector || '',
          product: config.product || '',
          resolution: config.resolution || '',
          enabled: false,
          auto_download: config.auto_download || false,
          last_download: trackingInfo.last_download,
          status: status,
          total_images: trackingInfo.total_images_downloaded || 0,
          description: config.description || `${config.satellite} ${config.sector} ${config.product} ${config.resolution}`,
          disabled_reason: config.disabled_reason
        };
        
        datasets.push(dataset);
      }
    }
    
    // Traiter les datasets découverts mais non activés
    if (configData.discovered_datasets) {
      for (const [datasetKey, datasetConfig] of Object.entries(configData.discovered_datasets)) {
        const config = datasetConfig as any;
        
        const dataset: Dataset = {
          key: datasetKey,
          satellite: config.satellite || '',
          sector: config.sector || '',
          product: config.product || '',
          resolution: config.resolution || '',
          enabled: false,
          auto_download: config.auto_download || false,
          status: 'discovered',
          total_images: 0,
          description: config.description || `${config.satellite} ${config.sector} ${config.product} ${config.resolution}`,
          discovered_date: config.discovered_date
        };
        
        datasets.push(dataset);
      }
    }
    
    // Si aucune configuration n'est trouvée, utiliser les données du tracking
    if (datasets.length === 0 && trackingData.tracking) {
      for (const [datasetKey, datasetInfo] of Object.entries(trackingData.tracking)) {
        const info = datasetInfo as any;
        const datasetConfig = info.dataset_info || {};
        
        const dataset: Dataset = {
          key: datasetKey,
          satellite: datasetConfig.satellite || '',
          sector: datasetConfig.sector || '',
          product: datasetConfig.product || '',
          resolution: datasetConfig.resolution || '',
          enabled: datasetConfig.enabled || false,
          auto_download: datasetConfig.auto_download || false,
          last_download: info.last_download,
          status: info.total_images_downloaded > 0 ? 'downloaded' : 'available',
          total_images: info.total_images_downloaded || 0
        };
        
        datasets.push(dataset);
      }
    }
    
    return NextResponse.json({
      success: true,
      datasets,
      total_count: datasets.length,
      enabled_count: datasets.filter(d => d.enabled).length,
      discovered_count: datasets.filter(d => d.status === 'discovered').length,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('Erreur lors de la lecture du statut des datasets:', error);
    return NextResponse.json(
      { 
        success: false, 
        error: error instanceof Error ? error.message : 'Erreur lors de la lecture du statut',
        datasets: []
      },
      { status: 500 }
    );
  }
}
