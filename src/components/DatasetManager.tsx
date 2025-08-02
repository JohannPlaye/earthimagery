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
    const organized: DatasetsByCategory = {};
    
    datasets.forEach(dataset => {
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
    <Box>
      {/* En-tête avec statistiques */}
      <Card sx={{ mb: 3 }}>
        <CardContent>
          <Box display="flex" justifyContent="space-between" alignItems="center" mb={2}>
            <Typography variant="h6" component="h2">
              <SatelliteIcon sx={{ mr: 1, verticalAlign: 'middle' }} />
              Gestion des Datasets Satellitaires
            </Typography>
            
            <Box display="flex" gap={1}>
              <Button
                variant="outlined"
                size="small"
                onClick={scanDatasets}
                disabled={loading}
                startIcon={<RefreshIcon />}
              >
                Scanner
              </Button>
              <Button
                variant="contained"
                size="small"
                onClick={syncDatasets}
                disabled={syncing}
                startIcon={<DownloadIcon />}
              >
                {syncing ? 'Sync...' : 'Synchroniser'}
              </Button>
            </Box>
          </Box>

          {/* Statistiques */}
          <Box display="flex" gap={3}>
            <Box>
              <Typography variant="body2" color="textSecondary">Total</Typography>
              <Typography variant="h6">{stats.total}</Typography>
            </Box>
            <Box>
              <Typography variant="body2" color="textSecondary">Activés</Typography>
              <Typography variant="h6" color="primary">{stats.enabled}</Typography>
            </Box>
            <Box>
              <Typography variant="body2" color="textSecondary">Téléchargés</Typography>
              <Typography variant="h6" color="success.main">{stats.downloaded}</Typography>
            </Box>
            <Box>
              <Typography variant="body2" color="textSecondary">Auto-sync</Typography>
              <Typography variant="h6" color="info.main">{stats.autoSync}</Typography>
            </Box>
          </Box>

          {syncing && <LinearProgress sx={{ mt: 2 }} />}
        </CardContent>
      </Card>

      {/* Messages d'erreur */}
      {error && (
        <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError(null)}>
          {error}
        </Alert>
      )}

      {/* Liste des datasets organisée */}
      {Object.entries(organizedDatasets).map(([satellite, sectors]) => (
        <Accordion
          key={satellite}
          expanded={expandedSatellites.has(satellite)}
          onChange={(_, expanded) => {
            const newExpanded = new Set(expandedSatellites);
            if (expanded) {
              newExpanded.add(satellite);
            } else {
              newExpanded.delete(satellite);
            }
            setExpandedSatellites(newExpanded);
          }}
        >
          <AccordionSummary expandIcon={<ExpandMoreIcon />}>
            <Typography variant="h6">
              {satellite}
              <Chip 
                size="small" 
                label={Object.values(sectors).flat().flat().length}
                sx={{ ml: 2 }}
              />
            </Typography>
          </AccordionSummary>
          
          <AccordionDetails>
            {Object.entries(sectors).map(([sector, products]) => (
              <Box key={sector} sx={{ mb: 2 }}>
                <Typography variant="subtitle1" color="primary" gutterBottom>
                  📍 {sector.toUpperCase()}
                </Typography>
                
                {Object.entries(products).map(([product, datasetList]) => (
                  <Card key={product} variant="outlined" sx={{ mb: 1 }}>
                    <CardContent sx={{ py: 1 }}>
                      <Typography variant="subtitle2" gutterBottom>
                        {product}
                      </Typography>
                      
                      <Box display="flex" flexWrap="wrap" gap={1}>
                        {datasetList.map(dataset => (
                          <Box 
                            key={dataset.key}
                            display="flex" 
                            alignItems="center" 
                            justifyContent="space-between"
                            p={1}
                            border={1}
                            borderColor="grey.300"
                            borderRadius={1}
                            minWidth="250px"
                            flex="1 1 auto"
                          >
                            <Box display="flex" alignItems="center" gap={1}>
                              {getStatusIcon(dataset.status)}
                              <Typography variant="body2">
                                {dataset.resolution}
                              </Typography>
                              {dataset.file_size && (
                                <Typography variant="caption" color="textSecondary">
                                  ({formatFileSize(dataset.file_size)})
                                </Typography>
                              )}
                            </Box>
                            
                            <Box display="flex" flexDirection="column" alignItems="end">
                              <FormControlLabel
                                control={
                                  <Switch
                                    checked={dataset.enabled}
                                    onChange={(e) => toggleDataset(dataset.key, e.target.checked, dataset.auto_download)}
                                    size="small"
                                    disabled={!!dataset.default_display} // Empêcher de désactiver si par défaut
                                  />
                                }
                                label={<Typography variant="caption">Afficher</Typography>}
                                sx={{ m: 0 }}
                              />
                              {/* Bouton Par défaut visible seulement si le dataset est affiché */}
                              {dataset.enabled && (
                                <FormControlLabel
                                  control={
                                    <input
                                      type="radio"
                                      name="defaultDisplay"
                                      checked={!!dataset.default_display}
                                      onChange={() => setDefaultDataset(dataset.key)}
                                      style={{ marginRight: 4 }}
                                    />
                                  }
                                  label={<Typography variant="caption">Par défaut</Typography>}
                                  sx={{ m: 0 }}
                                />
                              )}
                              <FormControlLabel
                                control={
                                  <Switch
                                    checked={dataset.auto_download}
                                    onChange={(e) => toggleAutoDownload(dataset.key, e.target.checked)}
                                    size="small"
                                    color="secondary"
                                  />
                                }
                                label={<Typography variant="caption">Télécharger</Typography>}
                                sx={{ m: 0 }}
                              />
                            </Box>
                          </Box>
                        ))}
                      </Box>
                    </CardContent>
                  </Card>
                ))}
              </Box>
            ))}
          </AccordionDetails>
        </Accordion>
      ))}

      {datasets.length === 0 && !loading && (
        <Card>
          <CardContent>
            <Typography variant="body1" textAlign="center" color="textSecondary">
              Aucun dataset disponible. Cliquez sur "Scanner" pour découvrir les datasets.
            </Typography>
          </CardContent>
        </Card>
      )}
    </Box>
  );
}
