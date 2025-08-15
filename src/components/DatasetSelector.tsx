'use client';

import React, { useState, useEffect } from 'react';
import {
  Satellite as SatelliteIcon
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

interface PlaylistItem {
  satellite: string;
  sector: string;
  product: string;
  resolution: string;
  date: string;
  playlist_url: string;
  segments: number;
  duration: number;
  file_size: number;
}

interface DatasetSelectorProps {
  onDatasetSelect: (dataset: SatelliteDataset | null) => void;
  selectedDataset?: SatelliteDataset | null;
}

export default function DatasetSelector({ onDatasetSelect, selectedDataset }: DatasetSelectorProps) {
  // Accordéon : états ouverts pour satellites, secteurs, produits
  const [openSatellites, setOpenSatellites] = useState<{ [sat: string]: boolean }>({});
  const [openSectors, setOpenSectors] = useState<{ [sat: string]: { [sector: string]: boolean } }>({});
  const [openProducts, setOpenProducts] = useState<{ [sat: string]: { [sector: string]: { [product: string]: boolean } } }>({});

  // Initialiser l'accordéon pour afficher la branche du dataset actif
  useEffect(() => {
    if (!selectedDataset) return;
    setOpenSatellites((prev) => ({ ...prev, [selectedDataset.satellite]: true }));
    setOpenSectors((prev) => ({
      ...prev,
      [selectedDataset.satellite]: {
        ...(prev[selectedDataset.satellite] || {}),
        [selectedDataset.sector]: true,
      },
    }));
    setOpenProducts((prev) => ({
      ...prev,
      [selectedDataset.satellite]: {
        ...(prev[selectedDataset.satellite] || {}),
        [selectedDataset.sector]: {
          ...((prev[selectedDataset.satellite] || {})[selectedDataset.sector] || {}),
          [selectedDataset.product]: true,
        },
      },
    }));
  }, [selectedDataset]);
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
        const playlist = playlistData.playlists.find((p: PlaylistItem) => 
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

  if (loading) {
    return (
      <div className="rounded-xl p-4">
        <div className="text-sm text-gray-400">Chargement des datasets...</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-xl p-4">
        <div className="text-sm text-red-400">Erreur: {error}</div>
      </div>
    );
  }

  if (datasets.length === 0) {
    return (
      <div className="rounded-xl p-4">
        <div className="text-sm text-gray-400 text-center">
          Aucun dataset activé. Activez des datasets dans l&apos;onglet <span className="text-purple-400">🛰️ Datasets</span>.
        </div>
      </div>
    );
  }

  return (
    <>
      <div className="flex items-center gap-2 mb-4">
        <SatelliteIcon className="text-purple-400" fontSize="small" />
        <span className="text-lg font-semibold text-purple-300">Sélection du dataset</span>
      </div>
      <div className="overflow-x-auto w-full">
        <table className="w-full text-xs">
          <tbody>
            {Object.entries(organizedDatasets).map(([satellite, sectors]) => {
              const isSatelliteOpen = openSatellites[satellite];
              return (
                <React.Fragment key={satellite}>
                  {/* Satellite header accordéon */}
                  <tr className="bg-[#232336] cursor-pointer select-none" onClick={() => setOpenSatellites(prev => ({ ...prev, [satellite]: !isSatelliteOpen }))}>
                    <td colSpan={4} className="py-2 px-3 font-bold text-purple-200 border-b border-[#2d2d44]">
                      <div className="flex items-center gap-2">
                        <span>{isSatelliteOpen ? '▼' : '▶'}</span>
                        <SatelliteIcon className="text-purple-400" fontSize="small" />
                        {satellite}
                        <span className="ml-auto text-xs px-2 py-1 rounded bg-purple-900 text-purple-300">
                          {Object.values(sectors).flatMap(products => Object.values(products)).flat().length}
                        </span>
                      </div>
                    </td>
                  </tr>
                  {isSatelliteOpen && Object.entries(sectors).map(([sector, products]) => {
                    const isSectorOpen = openSectors[satellite]?.[sector];
                    return (
                      <React.Fragment key={sector}>
                        {/* Sector header accordéon */}
                        <tr className="bg-[#28283a] cursor-pointer select-none" onClick={() => setOpenSectors(prev => ({
                          ...prev,
                          [satellite]: {
                            ...(prev[satellite] || {}),
                            [sector]: !isSectorOpen,
                          },
                        }))}>
                          <td colSpan={4} className="py-1 px-4 font-semibold text-purple-400 border-b border-[#232336]">
                            <span>{isSectorOpen ? '▼' : '▶'}</span> 📍 {sector.toUpperCase()}
                          </td>
                        </tr>
                        {isSectorOpen && Object.entries(products).map(([product, datasetList]) => {
                          const isProductOpen = openProducts[satellite]?.[sector]?.[product];
                          // Vérifier si le dataset actif est dans cette liste
                          const hasActive = datasetList.some(d => selectedDataset?.key === d.key);
                          return (
                            <React.Fragment key={product}>
                              {/* Product header accordéon */}
                              <tr className="bg-[#232336] cursor-pointer select-none" onClick={() => setOpenProducts(prev => ({
                                ...prev,
                                [satellite]: {
                                  ...(prev[satellite] || {}),
                                  [sector]: {
                                    ...((prev[satellite] || {})[sector] || {}),
                                    [product]: !isProductOpen,
                                  },
                                },
                              }))}>
                                <td colSpan={4} className="py-1 px-6 font-medium text-gray-300 border-b border-[#232336]">
                                  <span>{isProductOpen ? '▼' : '▶'}</span> {product}
                                </td>
                              </tr>
                              {/* Résolutions visibles si accordéon ouvert ou dataset actif */}
                              {(isProductOpen || hasActive) && datasetList.map(dataset => (
                                <React.Fragment key={dataset.key}>
                                  <tr className={`transition ${selectedDataset?.key === dataset.key ? 'bg-[#2d2d4a]' : 'bg-transparent'} hover:bg-[#312e4f]`}>
                                    <td className="p-0 w-10 align-middle text-center" title="Sélectionner ce dataset">
                                      <input
                                        type="radio"
                                        name="dataset"
                                        value={dataset.key}
                                        checked={selectedDataset?.key === dataset.key}
                                        onChange={() => handleDatasetSelect(dataset)}
                                        className="accent-purple-500"
                                      />
                                    </td>
                                    <td className="p-0 w-10 align-middle text-center" title="Statut du dataset (vert: prêt, bleu: traitement, rouge: erreur, gris: disponible)">
                                      <span className={`w-2 h-2 rounded-full inline-block ${dataset.status === 'downloaded' ? 'bg-green-400' : dataset.status === 'processing' ? 'bg-blue-400' : dataset.status === 'error' ? 'bg-red-400' : 'bg-gray-500'}`}></span>
                                    </td>
                                    <td className="px-3 py-2 text-gray-200 align-middle text-center font-medium" title="Résolution spatiale du dataset (ex: 600, 1200, 1800)">{dataset.resolution}</td>
                                    <td className="p-0 w-8 align-middle text-center" title="Voir les images sources du dataset">
                                      <button
                                        type="button"
                                        className="inline-flex items-center justify-center w-6 h-6 rounded-full bg-[#312e4f] hover:bg-purple-700 text-purple-300"
                                        title="Voir les images sources du dataset"
                                        onClick={() => setPopupDataset(dataset)}
                                      >
                                        <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 10l7-7m0 0l7 7m-7-7v18" /></svg>
                                      </button>
                                    </td>
                                    {/* Indicateurs d'automatisation et disponibilité masqués */}
                                    {/* <td className="px-1 py-1 w-16 min-w-[40px] max-w-[80px] align-middle text-center" title="Indicateurs d'automatisation et disponibilité du dataset">
                                      {dataset.auto_download && (
                                        <span className="text-[10px] px-2 py-0.5 rounded bg-blue-900 text-blue-300 ml-1">Auto</span>
                                      )}
                                      {dataset.status === 'downloaded' && (
                                        <span className="text-[10px] px-2 py-0.5 rounded bg-green-700 text-green-200 ml-1">Prêt</span>
                                      )}
                                    </td> */}
                                  </tr>
                                </React.Fragment>
                              ))}
                            </React.Fragment>
                          );
                        })}
                      </React.Fragment>
                    );
                  })}
                </React.Fragment>
              );
            })}
          </tbody>
        </table>
      </div>
      {selectedDataset && (
        <div className="mt-4 p-3 rounded-lg bg-[#312e4f] border border-purple-700">
          <div className="text-xs font-bold text-purple-300 mb-1">Dataset sélectionné :</div>
          <div className="text-xs text-gray-200 mb-1">
            📡 {selectedDataset.satellite} • 📍 {selectedDataset.sector} • 🎨 {selectedDataset.product} • 📐 {selectedDataset.resolution}
          </div>
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
    </>
  );
}
