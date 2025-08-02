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
  const [popupDataset, setPopupDataset] = useState<SatelliteDataset | null>(null);
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
      <div className="bg-[#232336] border border-[#7c3aed] rounded-xl p-4">
        <div className="text-sm text-gray-400">Chargement des datasets...</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-[#232336] border border-red-700 rounded-xl p-4">
        <div className="text-sm text-red-400">Erreur: {error}</div>
      </div>
    );
  }

  if (datasets.length === 0) {
    return (
      <div className="bg-[#232336] border border-[#7c3aed] rounded-xl p-4">
        <div className="text-sm text-gray-400 text-center">
          Aucun dataset activé. Activez des datasets dans l'onglet <span className="text-purple-400">🛰️ Datasets</span>.
        </div>
      </div>
    );
  }

  return (
    <div className="bg-[#232336] border border-[#7c3aed] rounded-xl p-4 w-full max-w-[420px]">
      <div className="flex items-center gap-2 mb-3">
        <SatelliteIcon className="text-purple-400" fontSize="small" />
        <span className="text-base font-bold text-purple-300 tracking-wide">Sélection du Dataset Satellitaire</span>
        <span className="ml-auto text-xs px-2 py-1 rounded bg-purple-900 text-purple-300">{datasets.length} activés</span>
      </div>
      <div className="overflow-x-auto">
        <table className="min-w-full text-xs">
          <tbody>
            {Object.entries(organizedDatasets).map(([satellite, sectors]) => (
              <React.Fragment key={satellite}>
                {/* Dataset header */}
                <tr className="bg-[#232336]">
                  <td colSpan={6} className="py-2 px-3 font-bold text-purple-200 border-b border-[#2d2d44]">
                    <div className="flex items-center gap-2">
                      <SatelliteIcon className="text-purple-400" fontSize="small" />
                      {satellite}
                      <span className="ml-auto text-xs px-2 py-1 rounded bg-purple-900 text-purple-300">
                        {Object.values(sectors).flatMap(products => Object.values(products)).flat().length}
                      </span>
                    </div>
                  </td>
                </tr>
                {Object.entries(sectors).map(([sector, products]) => (
                  <React.Fragment key={sector}>
                    {/* Sector subheader */}
                    <tr className="bg-[#28283a]">
                      <td colSpan={6} className="py-1 px-4 font-semibold text-purple-400 border-b border-[#232336]">
                        📍 {sector.toUpperCase()}
                      </td>
                    </tr>
                    {Object.entries(products).map(([product, datasetList]) => (
                      <React.Fragment key={product}>
                        {/* Product subheader */}
                        <tr className="bg-[#232336]">
                          <td colSpan={6} className="py-1 px-6 font-medium text-gray-300 border-b border-[#232336]">
                            {product}
                          </td>
                        </tr>
                        {datasetList.map(dataset => (
                          <React.Fragment key={dataset.key}>
                            <tr className={`transition ${selectedDataset?.key === dataset.key ? 'bg-[#2d2d4a]' : 'bg-transparent'} hover:bg-[#312e4f]`}>
                              <td className="px-8 py-1">
                                <input
                                  type="radio"
                                  name="dataset"
                                  value={dataset.key}
                                  checked={selectedDataset?.key === dataset.key}
                                  onChange={() => handleDatasetSelect(dataset)}
                                  className="accent-purple-500"
                                />
                              </td>
                              <td className="px-2 py-1">
                                <span className={`w-2 h-2 rounded-full inline-block mr-1 ${dataset.status === 'downloaded' ? 'bg-green-400' : dataset.status === 'processing' ? 'bg-blue-400' : dataset.status === 'error' ? 'bg-red-400' : 'bg-gray-500'}`}></span>
                              </td>
                              <td className="px-2 py-1 text-gray-200">{dataset.resolution}</td>
                              {/* Bouton popup images */}
                              <td className="px-2 py-1">
                                <button
                                  type="button"
                                  className="inline-flex items-center justify-center w-6 h-6 rounded-full bg-[#312e4f] hover:bg-purple-700 text-purple-300"
                                  title="Voir les images sources"
                                  onClick={() => setPopupDataset(dataset)}
                                >
                                  <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 10l7-7m0 0l7 7m-7-7v18" /></svg>
                                </button>
                              </td>
                              <td className="px-2 py-1">
                                <span className={`text-[10px] px-2 py-0.5 rounded ${dataset.resolution.includes('600') ? 'bg-green-900 text-green-300' : 'bg-purple-900 text-purple-300'}`}>{dataset.resolution.includes('600') ? 'Low-Res' : 'High-Res'}</span>
                              </td>
                              <td className="px-2 py-1">
                                {dataset.auto_download && (
                                  <span className="text-[10px] px-2 py-0.5 rounded bg-blue-900 text-blue-300 ml-1">Auto</span>
                                )}
                                {dataset.status === 'downloaded' && (
                                  <span className="text-[10px] px-2 py-0.5 rounded bg-green-700 text-green-200 ml-1">Prêt</span>
                                )}
                              </td>
                            </tr>

                          </React.Fragment>
                        ))}
                      </React.Fragment>
                    ))}
                  </React.Fragment>
                ))}
              </React.Fragment>
            ))}
          </tbody>
        </table>
      </div>
      {selectedDataset && (
        <div className="mt-4 p-3 rounded-lg bg-[#312e4f] border border-purple-700">
          <div className="text-xs font-bold text-purple-300 mb-1">Dataset sélectionné :</div>
          <div className="text-xs text-gray-200 mb-1">
            📡 {selectedDataset.satellite} • 📍 {selectedDataset.sector} • 🎨 {selectedDataset.product} • 📐 {selectedDataset.resolution}
          </div>
          {selectedDataset.playlist_url && (
            <div className="text-[10px] text-gray-400">Playlist: {selectedDataset.playlist_url}</div>
          )}
        </div>
      )}
      
      {/* Popup images sources - affichée en dehors du tableau pour éviter les problèmes d'affichage */}
      {popupDataset && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-12">
          {/* Background semi-transparent avec blur fort */}
          <div 
            className="absolute inset-0 backdrop-blur-md" 
            style={{ backgroundColor: 'rgba(0, 0, 0, 0.5)' }}
            onClick={() => setPopupDataset(null)} 
          />
          {/* Popup avec transparence interne */}
          <div className="relative rounded-xl border border-purple-700 shadow-2xl w-full h-full overflow-y-auto" style={{ background: 'rgba(35, 35, 54, 0.7)' }}>
            <button
              className="absolute top-4 right-4 text-gray-400 hover:text-purple-400 text-xl z-10"
              onClick={() => setPopupDataset(null)}
              title="Fermer"
            >
              &times;
            </button>
            <div className="w-full p-8">
              <PublishedImagesPanel
                dataset={{
                  satellite: popupDataset.satellite,
                  sector: popupDataset.sector,
                  product: popupDataset.product,
                  resolution: popupDataset.resolution,
                  source: 'NOAA',
                  label: `${popupDataset.satellite} / ${popupDataset.sector} / ${popupDataset.product} / ${popupDataset.resolution}`
                }}
                alwaysOpen={true}
              />
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
