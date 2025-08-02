'use client';

import { useState, useEffect } from 'react';
import DateSelector from '@/components/DateSelector';
import VideoPlayer from '@/components/VideoPlayer';
import DatasetManager from '@/components/DatasetManager';
import DatasetSelector from '@/components/DatasetSelector';
import NoSSR from '@/components/NoSSR';
import { Tabs, Tab, Box } from '@mui/material';

interface PreviewInfo {
  availableDays: number;
  totalSegments: number;
  estimatedDurationSeconds: number;
  estimatedDurationFormatted: string;
}

interface SatelliteDataset {
  key: string;
  satellite: string;
  sector: string;
  product: string;
  resolution: string;
  enabled: boolean;
  auto_download: boolean;
  default_display?: boolean;
  status: 'available' | 'downloaded' | 'processing' | 'error';
  playlist_url?: string;
  file_size?: number;
}

export default function Home() {
  // Utilitaires pour la date
  function toDateOnly(d: Date) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate());
  }
  const today = new Date();
  const yesterday = new Date();
  yesterday.setDate(today.getDate() - 1);

  // Hooks d'état pour la navigation et les sélections
  const [activeTab, setActiveTab] = useState(0);
  const [selectedDataset, setSelectedDataset] = useState<SatelliteDataset | null>(null);
  const [selectedFromDate, setSelectedFromDate] = useState(toDateOnly(yesterday));
  const [selectedToDate, setSelectedToDate] = useState(toDateOnly(today));
  const [isLoading, setIsLoading] = useState(false);
  const [previewInfo, setPreviewInfo] = useState<PreviewInfo | null>(null);

  // Gestion des changements de dates
  function handleDateRangeSelect(from: string, to: string) {
    setSelectedFromDate(toDateOnly(new Date(from)));
    setSelectedToDate(toDateOnly(new Date(to)));
  }
  function handlePreviewInfo(info: PreviewInfo) {
    setPreviewInfo(info);
  }

  // Charger le dataset par défaut au montage
  useEffect(() => {
    const loadDefaultDataset = async () => {
      const response = await fetch('/api/datasets/status');
      if (!response.ok) return;
      const data = await response.json();
      const defaultDataset = data.datasets?.find((dataset: SatelliteDataset) => dataset.default_display && dataset.enabled);
      if (defaultDataset) setSelectedDataset(defaultDataset);
    };
    loadDefaultDataset();
  }, []);

  return (
    <div className="flex flex-col h-screen bg-[#181820] text-white">
      <main className="flex">
        {/* Sidebar latéral */}
        <aside className="w-1/6 min-w-[220px] max-w-[320px] h-screen bg-[#232336] border-r border-[#2d2d44] flex flex-col py-6 px-3">
          <div className="mb-8">
            <h1 className="text-2xl font-bold text-purple-400 tracking-wide mb-2">EarthImagery</h1>
            <span className="text-xs text-gray-400">Observation satellite</span>
          </div>
          <Tabs
            orientation="vertical"
            value={activeTab}
            onChange={(_, newValue) => setActiveTab(newValue)}
            sx={{
              '.MuiTabs-indicator': { backgroundColor: '#a78bfa' },
              '.MuiTab-root': {
                color: '#a78bfa',
                fontWeight: 600,
                borderRadius: '8px',
                marginBottom: '8px',
                background: '#232336',
                '&.Mui-selected': {
                  background: 'linear-gradient(90deg, #7c3aed 60%, #232336 100%)',
                  color: '#fff',
                },
              },
            }}
          >
            <Tab label="⚙️ Paramètres" />
            <Tab label="🛰️ Datasets" />
          </Tabs>
          <div className="mt-6 flex-1 overflow-y-auto">
            {activeTab === 0 && (
              <div className="space-y-6">
                <NoSSR fallback={<div>Chargement du sélecteur...</div>}>
                  <DatasetSelector
                    onDatasetSelect={setSelectedDataset}
                    selectedDataset={selectedDataset}
                  />
                </NoSSR>
                <NoSSR fallback={<div>Chargement des dates...</div>}>
                  <DateSelector
                    onDateRangeSelect={handleDateRangeSelect}
                    onPreviewInfo={handlePreviewInfo}
                    isLoading={isLoading}
                    defaultFromDate={selectedFromDate.toISOString().slice(0, 10)}
                    defaultToDate={selectedToDate.toISOString().slice(0, 10)}
                  />
                </NoSSR>
                {previewInfo && (
                  <div className="bg-[#232336] rounded-lg p-4 mt-4">
                    <h3 className="text-lg font-semibold text-purple-300 mb-2">📊 Statistiques</h3>
                    <div className="grid grid-cols-2 gap-4">
                      <div className="text-center p-2 rounded-lg bg-blue-900/40">
                        <div className="text-xl font-bold text-blue-400">{previewInfo.availableDays}</div>
                        <div className="text-xs text-blue-300">Jours disponibles</div>
                      </div>
                      <div className="text-center p-2 rounded-lg bg-green-900/40">
                        <div className="text-xl font-bold text-green-400">{previewInfo.totalSegments}</div>
                        <div className="text-xs text-green-300">Segments vidéo</div>
                      </div>
                      <div className="text-center p-2 rounded-lg bg-purple-900/40">
                        <div className="text-xl font-bold text-purple-300">{previewInfo.estimatedDurationFormatted}</div>
                        <div className="text-xs text-purple-200">Durée estimée</div>
                      </div>
                      <div className="text-center p-2 rounded-lg bg-orange-900/40">
                        <div className="text-xl font-bold text-orange-300">25</div>
                        <div className="text-xs text-orange-200">FPS</div>
                      </div>
                    </div>
                  </div>
                )}
              </div>
            )}
            {activeTab === 1 && (
              <div className="mt-2">
                <DatasetManager />
              </div>
            )}
          </div>
        </aside>
        {/* Player central */}
        <section className="w-5/6 flex items-center justify-center bg-[#181820] h-screen">
          <div className="h-full w-full flex items-center justify-center p-[25px]">
            <NoSSR fallback={<div>Chargement du player...</div>}>
              <VideoPlayer
                fromDate={selectedFromDate}
                toDate={selectedToDate}
                selectedDataset={selectedDataset}
                className="h-full w-full"
              />
            </NoSSR>
          </div>
        </section>
      </main>
      {/* Footer modernisé */}
      <footer className="bg-[#232336] border-t border-[#2d2d44]">
        <div className="max-w-6xl mx-auto px-4 py-6">
          <div className="text-center text-gray-400">
            <p className="mb-2">
              🛰️ Données satellitaires traitées avec <span className="font-semibold text-purple-300">FFmpeg</span> et diffusées via <span className="font-semibold text-purple-300">HLS</span>
            </p>
            <p className="text-xs">
              Développé avec Next.js • TypeScript • Tailwind CSS • MUI
            </p>
          </div>
        </div>
      </footer>
    </div>
  );
}
