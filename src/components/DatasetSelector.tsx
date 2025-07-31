'use client';

import React, { useState, useEffect } from 'react';
import {
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  Box,
  Typography,
  Chip,
  Paper,
  Accordion,
  AccordionSummary,
  AccordionDetails,
  FormControlLabel,
  Radio,
  RadioGroup
} from '@mui/material';
import {
  ExpandMore as ExpandMoreIcon,
  Satellite as SatelliteIcon,
  Public as PublicIcon,
  Visibility as VisibilityIcon,
  HighQuality as QualityIcon
} from '@mui/icons-material';
import PublishedImagesPanel from './PublishedImagesPanel';

interface SatelliteDataset {
  key: string;
  satellite: string;
  sector: string;
  product: string;
  resolution: string;
  enabled: boolean;
  auto_download: boolean;
  status: 'available' | 'downloaded' | 'processing' | 'error';
  playlist_url?: string;
  file_size?: number;
}

interface DatasetSelectorProps {
  onDatasetSelect: (dataset: SatelliteDataset | null) => void;
  selectedDataset?: SatelliteDataset | null;
}

export default function DatasetSelector({ onDatasetSelect, selectedDataset }: DatasetSelectorProps) {
  const [datasets, setDatasets] = useState<SatelliteDataset[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Charger les datasets activés avec leurs playlists
  const loadActiveDatasets = async () => {
    try {
      setLoading(true);
      
      // Charger le statut des datasets
      const statusResponse = await fetch('/api/datasets/status');
      if (!statusResponse.ok) throw new Error('Erreur lors du chargement des datasets');
      
      const statusData = await statusResponse.json();
      const activeDatasets = statusData.datasets.filter((d: SatelliteDataset) => d.enabled);
      
      // Charger les playlists disponibles
      const playlistResponse = await fetch('/api/datasets/playlists');
      if (!playlistResponse.ok) throw new Error('Erreur lors du chargement des playlists');
      
      const playlistData = await playlistResponse.json();
      
      // Associer les playlists aux datasets
      const datasetsWithPlaylists = activeDatasets.map((dataset: SatelliteDataset) => {
        const playlist = playlistData.playlists.find((p: any) => 
          p.satellite === dataset.satellite &&
          p.sector === dataset.sector &&
          p.product === dataset.product &&
          p.resolution === dataset.resolution
        );
        
        return {
          ...dataset,
          playlist_url: playlist?.playlist_url,
          status: playlist ? 'downloaded' : 'available'
        };
      });
      
      setDatasets(datasetsWithPlaylists);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erreur inconnue');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadActiveDatasets();
  }, []);

  // Organiser les datasets par hiérarchie
  const organizeDatasets = (datasets: SatelliteDataset[]) => {
    const organized: { [satellite: string]: { [sector: string]: { [product: string]: SatelliteDataset[] } } } = {};
    
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

  const handleDatasetSelect = (dataset: SatelliteDataset) => {
    onDatasetSelect(dataset);
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'downloaded': return <VisibilityIcon color="success" fontSize="small" />;
      case 'processing': return <QualityIcon color="info" fontSize="small" />;
      case 'error': return <VisibilityIcon color="error" fontSize="small" />;
      default: return <VisibilityIcon color="disabled" fontSize="small" />;
    }
  };

  const getResolutionColor = (resolution: string) => {
    if (resolution.includes('600')) return 'success';
    if (resolution.includes('1200')) return 'warning';
    if (resolution.includes('1800')) return 'error';
    return 'default';
  };

  if (loading) {
    return (
      <Paper sx={{ p: 2 }}>
        <Typography variant="body2">Chargement des datasets...</Typography>
      </Paper>
    );
  }

  if (error) {
    return (
      <Paper sx={{ p: 2, bgcolor: 'error.light' }}>
        <Typography variant="body2" color="error">
          Erreur: {error}
        </Typography>
      </Paper>
    );
  }

  if (datasets.length === 0) {
    return (
      <Paper sx={{ p: 2 }}>
        <Typography variant="body2" color="textSecondary" textAlign="center">
          Aucun dataset activé. Activez des datasets dans l'onglet "🛰️ Datasets".
        </Typography>
      </Paper>
    );
  }

  return (
    <Paper sx={{ p: 2 }}>
      <Box display="flex" alignItems="center" gap={1} mb={2}>
        <SatelliteIcon color="primary" />
        <Typography variant="h6">
          Sélection du Dataset Satellitaire
        </Typography>
        <Chip size="small" label={`${datasets.length} activés`} color="primary" />
      </Box>

      <RadioGroup
        value={selectedDataset?.key || ''}
        onChange={(e) => {
          const dataset = datasets.find(d => d.key === e.target.value);
          handleDatasetSelect(dataset!);
        }}
      >
        {Object.entries(organizedDatasets).map(([satellite, sectors]) => (
          <Accordion key={satellite} defaultExpanded={Object.keys(organizedDatasets).length <= 2}>
            <AccordionSummary expandIcon={<ExpandMoreIcon />}>
              <Box display="flex" alignItems="center" gap={1}>
                <SatelliteIcon fontSize="small" />
                <Typography variant="subtitle1" fontWeight="bold">
                  {satellite}
                </Typography>
                <Chip 
                  size="small" 
                  label={Object.values(sectors).flatMap(products => Object.values(products)).flat().length}
                  variant="outlined"
                />
              </Box>
            </AccordionSummary>
            
            <AccordionDetails>
              {Object.entries(sectors).map(([sector, products]) => (
                <Box key={sector} sx={{ mb: 2 }}>
                  <Box display="flex" alignItems="center" gap={1} mb={1}>
                    <PublicIcon fontSize="small" color="primary" />
                    <Typography variant="subtitle2" color="primary">
                      📍 {sector.toUpperCase()}
                    </Typography>
                  </Box>
                  
                  {Object.entries(products).map(([product, datasetList]) => (
                    <Box key={product} sx={{ ml: 3, mb: 1 }}>
                      <Typography variant="body2" fontWeight="medium" gutterBottom>
                        {product}
                      </Typography>
                      
                      {datasetList.map(dataset => (
                        <Box
                          key={dataset.key}
                          sx={{ 
                            ml: 2, 
                            p: 1, 
                            border: selectedDataset?.key === dataset.key ? '2px solid' : '1px solid',
                            borderColor: selectedDataset?.key === dataset.key ? 'primary.main' : 'grey.300',
                            borderRadius: 1,
                            mb: 1,
                            bgcolor: selectedDataset?.key === dataset.key ? 'primary.50' : 'transparent'
                          }}
                        >
                          <FormControlLabel
                            value={dataset.key}
                            control={<Radio size="small" />}
                            sx={{ width: '100%', m: 0 }}
                            label={
                              <Box display="flex" alignItems="center" justifyContent="space-between" width="100%">
                                <Box display="flex" alignItems="center" gap={1}>
                                  {getStatusIcon(dataset.status)}
                                  <Typography variant="body2">
                                    {dataset.resolution}
                                  </Typography>
                                  <Chip 
                                    size="small" 
                                    label={dataset.resolution.includes('600') ? 'Low-Res' : 'High-Res'}
                                    color={getResolutionColor(dataset.resolution)}
                                    variant="outlined"
                                  />
                                </Box>
                                <Box display="flex" alignItems="center" gap={1}>
                                  {dataset.auto_download && (
                                    <Chip size="small" label="Auto" color="secondary" variant="outlined" />
                                  )}
                                  {dataset.status === 'downloaded' && (
                                    <Chip size="small" label="Prêt" color="success" variant="filled" />
                                  )}
                                </Box>
                              </Box>
                            }
                          />
                          {/* Panneau images publiées */}
                          <PublishedImagesPanel dataset={{
                            satellite: dataset.satellite,
                            sector: dataset.sector,
                            product: dataset.product,
                            resolution: dataset.resolution,
                            source: 'NOAA',
                            label: `${dataset.satellite} / ${dataset.sector} / ${dataset.product} / ${dataset.resolution}`
                          }} />
                        </Box>
                      ))}
                    </Box>
                  ))}
                </Box>
              ))}
            </AccordionDetails>
          </Accordion>
        ))}
      </RadioGroup>

      {selectedDataset && (
        <Box sx={{ mt: 2, p: 2, bgcolor: 'info.light', borderRadius: 1 }}>
          <Typography variant="body2" fontWeight="bold" gutterBottom>
            Dataset sélectionné:
          </Typography>
          <Typography variant="body2">
            📡 {selectedDataset.satellite} • 📍 {selectedDataset.sector} • 🎨 {selectedDataset.product} • 📐 {selectedDataset.resolution}
          </Typography>
          {selectedDataset.playlist_url && (
            <Typography variant="caption" color="textSecondary">
              Playlist: {selectedDataset.playlist_url}
            </Typography>
          )}
        </Box>
      )}
    </Paper>
  );
}
