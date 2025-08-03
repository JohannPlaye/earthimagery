'use client';

import React, { useState, useEffect } from 'react';
import { 
  Card, 
  CardContent, 
  Typography, 
  Switch, 
  FormControlLabel,
  Chip,
  Box,
  Button,
  LinearProgress,
  Alert,
  Accordion,
  AccordionSummary,
  AccordionDetails,
  Grid
} from '@mui/material';
import { 
  ExpandMore as ExpandMoreIcon,
  Satellite as SatelliteIcon,
  Download as DownloadIcon,
  CheckCircle as CheckCircleIcon,
  Cancel as CancelIcon,
  Refresh as RefreshIcon
} from '@mui/icons-material';

interface Dataset {
  key: string;
  satellite: string;
  sector: string;
  product: string;
  resolution: string;
  enabled: boolean;
  auto_download: boolean;
  enabled_date?: string;
  last_download?: string;
  status: 'available' | 'downloaded' | 'processing' | 'error';
  file_size?: number;
  default_display?: boolean;
}

interface DatasetsByCategory {
  [satellite: string]: {
    [sector: string]: {
      [product: string]: Dataset[];
    };
  };
}

export default function DatasetManager() {
  const [datasets, setDatasets] = useState<Dataset[]>([]);
  const [defaultDisplayKey, setDefaultDisplayKey] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [syncing, setSyncing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [expandedSatellites, setExpandedSatellites] = useState<Set<string>>(new Set(['GOES18']));

  // Charger les datasets disponibles
  const loadDatasets = async () => {
    try {
      setLoading(true);
      const response = await fetch('/api/datasets/status');
      if (!response.ok) throw new Error('Erreur lors du chargement');
      
      const data = await response.json();
      setDatasets(data.datasets || []);
      // Trouver le dataset par défaut
      const defaultDs = (data.datasets || []).find((ds: Dataset) => ds.default_display);
      setDefaultDisplayKey(defaultDs ? defaultDs.key : null);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erreur inconnue');
    } finally {
      setLoading(false);
    }
  };

  // Activer/désactiver un dataset
  const toggleDataset = async (datasetKey: string, enabled: boolean, autoDownload = false) => {
    try {
      // Empêcher de désactiver un dataset qui est par défaut
      if (!enabled) {
        const currentDataset = datasets.find(d => d.key === datasetKey);
        if (currentDataset?.default_display) {
          setError('Impossible de désactiver l\'affichage d\'un dataset défini par défaut. Sélectionnez d\'abord un autre dataset comme défaut.');
          return;
        }
      }
      
      const [satellite, sector, product, resolution] = datasetKey.split('.');
      const response = await fetch('/api/datasets/toggle', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          satellite,
          sector,
          product,
          resolution,
          enabled,
          auto_download: autoDownload
        })
      });
      if (!response.ok) throw new Error('Erreur lors de la mise à jour');
      await loadDatasets();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erreur de mise à jour');
    }
  };

  // Sélectionner le dataset par défaut
  const setDefaultDataset = async (datasetKey: string) => {
    try {
      const [satellite, sector, product, resolution] = datasetKey.split('.');
      // Appel API pour activer ET définir le dataset par défaut
      const response = await fetch('/api/datasets/toggle', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ satellite, sector, product, resolution, enabled: true, setDefault: true })
      });
      if (!response.ok) throw new Error('Erreur lors de la mise à jour du dataset par défaut');
      // On attend la réponse et recharge l'état à partir du backend
      await loadDatasets();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erreur inconnue');
    }
  };

  // Activer/désactiver uniquement le téléchargement automatique
  const toggleAutoDownload = async (datasetKey: string, autoDownload: boolean) => {
    try {
      const [satellite, sector, product, resolution] = datasetKey.split('.');
      
      const response = await fetch('/api/datasets/toggle', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          satellite,
          sector,
          product,
          resolution,
          enabled: false, // On ne change pas le statut d'affichage
          auto_download: autoDownload,
          download_only: true // Flag pour indiquer qu'on veut juste changer le téléchargement
        })
      });

      if (!response.ok) throw new Error('Erreur lors de la mise à jour');
      
      await loadDatasets();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erreur de mise à jour');
    }
  };

  // Synchroniser les datasets
  const syncDatasets = async () => {
    try {
      setSyncing(true);
      const response = await fetch('/api/datasets/sync', { method: 'POST' });
      if (!response.ok) throw new Error('Erreur lors de la synchronisation');
      
      await loadDatasets();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erreur de synchronisation');
    } finally {
      setSyncing(false);
    }
  };

  // Scanner les nouveaux datasets
  const scanDatasets = async () => {
    try {
      setLoading(true);
      const response = await fetch('/api/datasets/scan', { method: 'POST' });
      if (!response.ok) throw new Error('Erreur lors du scan');
      
      await loadDatasets();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erreur de scan');
    }
  };

  useEffect(() => {
    loadDatasets();
  }, []);

  // Organiser les datasets par catégories
  const organizeDatasets = (datasets: Dataset[]): DatasetsByCategory => {
    // Sort datasets by name and resolution before organizing
    // On trie par 'product' (nom du produit), puis par résolution (convertie en nombre si possible)
    const parseResolution = (res: string | undefined): number => {
      if (!res) return 0;
      // Exemples : "1km", "500m", "0.25deg"
      const match = res.match(/([\d\.]+)/);
      return match ? parseFloat(match[1]) : 0;
    };
    const sorted = [...datasets].sort((a, b) => {
      // Tri principal par clé unique (key)
      if (a.key < b.key) return -1;
      if (a.key > b.key) return 1;
      // Si la clé est identique, on trie par produit
      if (a.product < b.product) return -1;
      if (a.product > b.product) return 1;
      // Si le produit est identique, on trie par résolution croissante
      return parseResolution(a.resolution) - parseResolution(b.resolution);
    });
    const organized: DatasetsByCategory = {};
    sorted.forEach(dataset => {
      if (!organized[dataset.satellite]) {
        organized[dataset.satellite] = {};
      }
      if (!organized[dataset.satellite][dataset.sector]) {
        organized[dataset.satellite][dataset.sector] = {};
      }
      if (!organized[dataset.satellite][dataset.sector][dataset.product]) {
        organized[dataset.satellite][dataset.sector][dataset.product] = [];
      }
      organized[dataset.satellite][dataset.sector][dataset.product].push(dataset);
    });
    return organized;
  };

  const organizedDatasets = organizeDatasets(datasets);

  // Statistiques
  const stats = {
    total: datasets.length,
    enabled: datasets.filter(d => d.enabled).length,
    downloaded: datasets.filter(d => d.status === 'downloaded').length,
    autoSync: datasets.filter(d => d.auto_download).length
  };

  const getStatusIcon = (status: Dataset['status']) => {
    switch (status) {
      case 'downloaded': return <CheckCircleIcon color="success" />;
      case 'processing': return <DownloadIcon color="info" />;
      case 'error': return <CancelIcon color="error" />;
      default: return <SatelliteIcon color="disabled" />;
    }
  };

  const getStatusColor = (status: Dataset['status']) => {
    switch (status) {
      case 'downloaded': return 'success';
      case 'processing': return 'info';
      case 'error': return 'error';
      default: return 'default';
    }
  };

  const formatFileSize = (bytes: number | undefined) => {
    if (!bytes) return '';
    const mb = bytes / (1024 * 1024);
    return mb > 1 ? `${mb.toFixed(1)} MB` : `${Math.round(bytes / 1024)} KB`;
  };

  if (loading && datasets.length === 0) {
    return (
      <Card>
        <CardContent>
          <LinearProgress />
          <Typography variant="body2" sx={{ mt: 2 }}>
            Chargement des datasets...
          </Typography>
        </CardContent>
      </Card>
    );
  }

  return (
    <Box className="rounded-xl">
      <h3 className="text-lg font-semibold text-purple-300">🛰️ Sélection du Dataset</h3>
      {/* En-tête minimaliste avec statistiques */}
      <div className="flex justify-between items-center mb-2">
        <div className="flex gap-2">
          <Button
            variant="outlined"
            size="small"
            onClick={scanDatasets}
            disabled={loading}
            sx={{ color: '#a78bfa', borderColor: '#a78bfa', minWidth: 0, padding: '6px' }}
          >
            <RefreshIcon />
          </Button>
          <Button
            variant="contained"
            size="small"
            onClick={syncDatasets}
            disabled={syncing}
            sx={{ background: '#a78bfa', color: '#181825', minWidth: 0, padding: '6px' }}
          >
            <DownloadIcon />
          </Button>
        </div>
      </div>
      <div className="flex gap-4 mb-2 text-xs">
        <div className="flex flex-col items-center"><span className="text-gray-400">Total</span><span>{stats.total}</span></div>
        <div className="flex flex-col items-center"><span className="text-purple-400">Activés</span><span>{stats.enabled}</span></div>
        <div className="flex flex-col items-center"><span className="text-green-400">Téléchargés</span><span>{stats.downloaded}</span></div>
        <div className="flex flex-col items-center"><span className="text-blue-400">Auto-sync</span><span>{stats.autoSync}</span></div>
      </div>
      {syncing && <LinearProgress sx={{ mt: 1, background: '#312244' }} />}

      {/* Messages d'erreur */}
      {error && (
        <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError(null)}>
          {error}
        </Alert>
      )}

      {/* Liste des datasets organisée */}
      <div className="space-y-2">
        {Object.entries(organizedDatasets).map(([satellite, sectors]) => (
          <div key={satellite} className="bg-[#232347] rounded-lg">
            <button
              className="w-full flex items-center justify-between px-3 py-2 text-left focus:outline-none"
              onClick={() => {
                const newExpanded = new Set(expandedSatellites);
                if (!expandedSatellites.has(satellite)) {
                  newExpanded.add(satellite);
                } else {
                  newExpanded.delete(satellite);
                }
                setExpandedSatellites(newExpanded);
              }}
            >
              <span className="font-semibold text-purple-300">{satellite}</span>
              <span className="bg-purple-900 text-purple-200 rounded-full px-2 py-0.5 text-xs">{Object.values(sectors).flat().flat().length}</span>
            </button>
            {expandedSatellites.has(satellite) && (
              <div className="px-3 pb-2">
                {Object.entries(sectors).map(([sector, products]) => (
                  <div key={sector} className="mb-1">
                    <div className="text-xs text-blue-300 font-medium mb-1">📍 {sector.toUpperCase()}</div>
                    {Object.entries(products).map(([product, datasetList]) => (
                      <div key={product} className="bg-[#181825] rounded-md mb-1 p-2">
                        <div className="text-xs text-purple-200 font-semibold mb-1">{product}</div>
                        <div className="flex flex-wrap gap-1">
                          {datasetList.map(dataset => (
                            <div
                              key={dataset.key}
                              className="flex items-center justify-between bg-[#232347] rounded px-2 py-1 min-w-[180px] text-xs"
                            >
                              <div className="flex items-center gap-1">
                                {getStatusIcon(dataset.status)}
                                <span className="text-gray-200">{dataset.resolution}</span>
                                {dataset.file_size && (
                                  <span className="text-gray-400">({formatFileSize(dataset.file_size)})</span>
                                )}
                              </div>
                              <div className="flex items-center gap-2">
                                <Switch
                                  checked={dataset.enabled}
                                  onChange={(e) => toggleDataset(dataset.key, e.target.checked, dataset.auto_download)}
                                  size="small"
                                  disabled={!!dataset.default_display}
                                  color="secondary"
                                />
                                {dataset.enabled && (
                                  <input
                                    type="radio"
                                    name="defaultDisplay"
                                    checked={!!dataset.default_display}
                                    onChange={() => setDefaultDataset(dataset.key)}
                                    className="accent-purple-400"
                                  />
                                )}
                                <Switch
                                  checked={dataset.auto_download}
                                  onChange={(e) => toggleAutoDownload(dataset.key, e.target.checked)}
                                  size="small"
                                  color="secondary"
                                />
                              </div>
                            </div>
                          ))}
                        </div>
                      </div>
                    ))}
                  </div>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>

      {datasets.length === 0 && !loading && (
        <div className="bg-[#232347] rounded-lg p-4 text-center text-gray-400">
          Aucun dataset disponible. Cliquez sur "Scanner" pour découvrir les datasets.
        </div>
      )}
    

      {/* */}
    </Box>
  );
}
