'use client';

import { useState, useEffect, useMemo } from 'react';
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
  const today = toDateOnly(new Date());
  const yesterday = toDateOnly(new Date(Date.now() - 24 * 60 * 60 * 1000));

  // Hooks d'état pour la navigation et les sélections
  const [activeTab, setActiveTab] = useState(0);
  const [selectedDataset, setSelectedDataset] = useState<SatelliteDataset | null>(null);
  const [selectedDateRange, setSelectedDateRange] = useState<[Date, Date]>([yesterday, today]);
  const [isLoading, setIsLoading] = useState(false);
  const [previewInfo, setPreviewInfo] = useState<PreviewInfo | null>(null);

  // Gestion des changements de dates
  function handleDateRangeSelect(from: string, to: string) {
    setSelectedDateRange([toDateOnly(new Date(from)), toDateOnly(new Date(to))]);
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

  // Mémorisation des props pour éviter les re-rendus
  const defaultDateRange = useMemo(() => [
    selectedDateRange[0].toISOString().slice(0, 10),
    selectedDateRange[1].toISOString().slice(0, 10)
  ] as [string, string], [selectedDateRange]);

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
              <div className="bg-[#181825] rounded-xl p-4 space-y-6">
                {/* Sélecteur de période en haut */}
                <NoSSR fallback={<div>Chargement des dates...</div>}>
                  <DateSelector
                    onDateRangeSelect={handleDateRangeSelect}
                    onPreviewInfo={handlePreviewInfo}
                    isLoading={isLoading}
                    defaultDateRange={defaultDateRange}
                  />
                </NoSSR>
                {/* Sélecteur de dataset en dessous */}
                <NoSSR fallback={<div>Chargement du sélecteur...</div>}>
                  <DatasetSelector
                    onDatasetSelect={setSelectedDataset}
                    selectedDataset={selectedDataset}
                  />
                </NoSSR>
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
                fromDate={selectedDateRange[0]}
                toDate={selectedDateRange[1]}
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
