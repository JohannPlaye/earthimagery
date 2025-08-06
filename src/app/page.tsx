'use client';

import { useState, useEffect } from 'react';
import DateSelector from '@/components/DateSelector';
import VideoPlayer from '@/components/VideoPlayer';
import DatasetManager from '@/components/DatasetManager';
import DatasetSelector from '@/components/DatasetSelector';
import NoSSR from '@/components/NoSSR';

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

  // Gestion des changements de dates
  function handleDateRangeSelect(range: { startDate: Date; endDate: Date }) {
    setSelectedDateRange([toDateOnly(range.startDate), toDateOnly(range.endDate)]);
  }
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  function handlePreviewInfo(_: PreviewInfo | null) {
    // Cette fonction peut être retirée si elle n'est plus nécessaire
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
          <div className="mb-4">
            <h1 className="text-3xl font-bold text-purple-400 tracking-wide mb-2">EarthImagery</h1>
            <span className="text-base text-purple-300">Earth on your screen</span>
          </div>
          {/* Tabs horizontaux personnalisés */}
          <div className="flex flex-row gap-2 mb-0">
            <button
              className={`flex-1 py-2 px-4 font-semibold rounded-t-lg focus:outline-none transition-colors duration-150 ${activeTab === 0 ? 'text-sm border-b-4 border-purple-400 text-purple-200 bg-[#232336]' : 'text-sm text-purple-400 bg-transparent'}`}
              onClick={() => setActiveTab(0)}
              type="button"
            >
              ⚙️ Paramètres
            </button>
            <button
              className={`flex-1 py-2 px-4 font-semibold rounded-t-lg focus:outline-none transition-colors duration-150 ${activeTab === 1 ? 'text-sm border-b-4 border-purple-400 text-purple-200 bg-[#232336]' : 'text-sm text-purple-400 bg-transparent'}`}
              onClick={() => setActiveTab(1)}
              type="button"
            >
              🛰️ Datasets
            </button>
          </div>
          <div className="mt-6 flex-1 overflow-y-auto">
            {activeTab === 0 && (
              <div className="space-y-6">
                <div className="bg-[#101828] rounded-xl p-4">
                  <NoSSR fallback={<div>Chargement des dates...</div>}>
                    <DateSelector
                      onDateRangeSelect={handleDateRangeSelect}
                      onPreviewInfo={handlePreviewInfo}
                    />
                  </NoSSR>
                </div>
                <div className="bg-[#101828] rounded-xl p-4">
                  <NoSSR fallback={<div>Chargement du sélecteur...</div>}>
                    <DatasetSelector
                      onDatasetSelect={setSelectedDataset}
                      selectedDataset={selectedDataset}
                    />
                  </NoSSR>
                </div>
              </div>
            )}
            {activeTab === 1 && (
              <div className="mt-2">
                <div className="bg-[#101828] rounded-xl p-4">
                  <DatasetManager />
                </div>
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
