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
  status: 'available' | 'downloaded' | 'processing' | 'error';
  total_images?: number;
}

// Chemin vers le fichier de tracking unifié
const TRACKING_FILE = path.join(process.cwd(), 'config', 'download-tracking.json');

// Obtenir le statut des datasets
export async function GET() {
  try {
    // Lire le fichier de tracking unifié
    const trackingContent = await fs.readFile(TRACKING_FILE, 'utf-8');
    const trackingData = JSON.parse(trackingContent);
    
    const datasets: Dataset[] = [];
    
    // Parcourir tous les datasets dans le tracking
    for (const [datasetKey, datasetInfo] of Object.entries(trackingData.tracking || {})) {
      const info = datasetInfo as any;
      const datasetConfig = info.dataset_info || {};
      
      // Déterminer le statut basé sur les téléchargements récents
      let status: Dataset['status'] = 'available';
      const totalDownloaded = info.total_images_downloaded || 0;
      
      if (totalDownloaded > 0) {
        status = 'downloaded';
      }
      
      const dataset: Dataset = {
        key: datasetKey,
        satellite: datasetConfig.satellite || '',
        sector: datasetConfig.sector || '',
        product: datasetConfig.product || '',
        resolution: datasetConfig.resolution || '',
        enabled: datasetConfig.enabled || false,
        auto_download: datasetConfig.auto_download || false,
        last_download: info.last_download || undefined,
        status,
        total_images: totalDownloaded
      };
      
      datasets.push(dataset);
    }
    
    return NextResponse.json({
      success: true,
      datasets,
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
