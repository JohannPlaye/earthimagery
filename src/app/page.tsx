'use client';

import { useState } from 'react';
import DateSelector from '@/components/DateSelector';
import VideoPlayer from '@/components/VideoPlayer';
import NoSSR from '@/components/NoSSR';

interface PreviewInfo {
  availableDays: number;
  totalSegments: number;
  estimatedDurationSeconds: number;
  estimatedDurationFormatted: string;
}

export default function Home() {
  const [selectedFromDate, setSelectedFromDate] = useState<Date>(new Date('2025-07-22'));
  const [selectedToDate, setSelectedToDate] = useState<Date>(new Date('2025-07-22'));
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [previewInfo, setPreviewInfo] = useState<PreviewInfo | null>(null);

  const handleDateRangeSelect = async (from: string, to: string) => {
    setIsLoading(true);
    setError(null);

    try {
      setSelectedFromDate(new Date(from));
      setSelectedToDate(new Date(to));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erreur inconnue');
    } finally {
      setIsLoading(false);
    }
  };

  const handlePreviewInfo = (info: PreviewInfo) => {
    setPreviewInfo(info);
  };

  const handleVideoError = (errorMessage: string) => {
    setError(errorMessage);
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100">
      {/* Header */}
      <header className="bg-white shadow-sm border-b">
        <div className="max-w-6xl mx-auto px-4 py-6">
          <div className="text-center">
            <h1 className="text-4xl font-bold text-gray-800 mb-2">
              🌍 EarthImagery
            </h1>
            <p className="text-lg text-gray-600">
              Observation de phénomènes météorologiques via imagerie satellitaire
            </p>
          </div>
        </div>
      </header>

      <main className="max-w-6xl mx-auto px-4 py-8 space-y-8">
        {/* Sélecteur de dates */}
        <NoSSR fallback={
          <div className="w-full max-w-4xl mx-auto p-6 bg-white rounded-lg shadow-lg">
            <h2 className="text-2xl font-bold text-gray-800 mb-6 text-center">
              Sélection de la période d&apos;observation
            </h2>
            <div className="flex items-center justify-center py-8">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
              <span className="ml-2">Chargement...</span>
            </div>
          </div>
        }>
          <DateSelector
            onDateRangeSelect={handleDateRangeSelect}
            onPreviewInfo={handlePreviewInfo}
            isLoading={isLoading}
          />
        </NoSSR>

        {/* Affichage des erreurs globales */}
        {error && (
          <div className="max-w-4xl mx-auto">
            <div className="bg-red-50 border border-red-200 rounded-lg p-4">
              <div className="flex">
                <div className="flex-shrink-0">
                  <svg className="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clipRule="evenodd" />
                  </svg>
                </div>
                <div className="ml-3">
                  <h3 className="text-sm font-medium text-red-800">Erreur</h3>
                  <div className="mt-2 text-sm text-red-700">{error}</div>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Lecteur vidéo */}
        <NoSSR fallback={
          <div className="w-full max-w-4xl mx-auto">
            <div className="relative bg-black rounded-lg overflow-hidden shadow-lg">
              <video
                className="w-full h-auto"
                controls
                preload="metadata"
                style={{ minHeight: '300px' }}
              >
                Votre navigateur ne supporte pas la lecture vidéo.
              </video>
              <div className="absolute inset-0 bg-gray-900 flex items-center justify-center">
                <div className="text-center text-gray-300">
                  <svg className="h-16 w-16 mx-auto mb-4 opacity-50" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M14.828 14.828a4 4 0 01-5.656 0M9 10h1m4 0h1m-6 4h8m2-5V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-2m-1 4H10" />
                  </svg>
                  <p className="text-lg">Chargement...</p>
                </div>
              </div>
            </div>
          </div>
        }>
          <VideoPlayer
            fromDate={selectedFromDate}
            toDate={selectedToDate}
          />
        </NoSSR>

        {/* Informations sur les données */}
        {previewInfo && (
          <div className="max-w-4xl mx-auto">
            <div className="bg-white rounded-lg shadow-sm border p-6">
              <h3 className="text-lg font-semibold text-gray-800 mb-4">
                📊 Statistiques des données
              </h3>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                <div className="text-center p-3 bg-blue-50 rounded-lg">
                  <div className="text-2xl font-bold text-blue-600">
                    {previewInfo.availableDays}
                  </div>
                  <div className="text-sm text-blue-700">Jours disponibles</div>
                </div>
                <div className="text-center p-3 bg-green-50 rounded-lg">
                  <div className="text-2xl font-bold text-green-600">
                    {previewInfo.totalSegments}
                  </div>
                  <div className="text-sm text-green-700">Segments vidéo</div>
                </div>
                <div className="text-center p-3 bg-purple-50 rounded-lg">
                  <div className="text-2xl font-bold text-purple-600">
                    {previewInfo.estimatedDurationFormatted}
                  </div>
                  <div className="text-sm text-purple-700">Durée estimée</div>
                </div>
                <div className="text-center p-3 bg-orange-50 rounded-lg">
                  <div className="text-2xl font-bold text-orange-600">25</div>
                  <div className="text-sm text-orange-700">FPS</div>
                </div>
              </div>
            </div>
          </div>
        )}
      </main>

      {/* Footer */}
      <footer className="bg-white border-t mt-16">
        <div className="max-w-6xl mx-auto px-4 py-8">
          <div className="text-center text-gray-600">
            <p className="mb-2">
              🛰️ Données satellitaires traitées avec{' '}
              <span className="font-semibold">FFmpeg</span> et diffusées via{' '}
              <span className="font-semibold">HLS</span>
            </p>
            <p className="text-sm">
              Développé avec Next.js • TypeScript • Tailwind CSS • MUI
            </p>
          </div>
        </div>
      </footer>
    </div>
  );
}
