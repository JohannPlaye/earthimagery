'use client';

import React, { useState } from 'react';
import { DatePicker } from '@mui/x-date-pickers/DatePicker';
import { LocalizationProvider } from '@mui/x-date-pickers/LocalizationProvider';
import { AdapterDayjs } from '@mui/x-date-pickers/AdapterDayjs';
import { Button, Alert, CircularProgress } from '@mui/material';
import dayjs, { Dayjs } from 'dayjs';
import 'dayjs/locale/fr';

dayjs.locale('fr');

interface DateSelectorProps {
  onDateRangeSelect: (from: string, to: string) => void;
  onPreviewInfo: (info: PlaylistInfo) => void;
  isLoading?: boolean;
  defaultFromDate?: string;
  defaultToDate?: string;
}

interface PlaylistInfo {
  availableDays: number;
  totalSegments: number;
  estimatedDurationSeconds: number;
  estimatedDurationFormatted: string;
}

export default function DateSelector({ 
  onDateRangeSelect, 
  onPreviewInfo, 
  isLoading = false,
  defaultFromDate,
  defaultToDate
}: DateSelectorProps) {
  const [fromDate, setFromDate] = useState<Dayjs | null>(defaultFromDate ? dayjs(defaultFromDate) : null);
  const [toDate, setToDate] = useState<Dayjs | null>(defaultToDate ? dayjs(defaultToDate) : null);
  const [error, setError] = useState<string | null>(null);
  const [previewInfo, setPreviewInfo] = useState<PlaylistInfo | null>(null);
  const [isPreviewLoading, setIsPreviewLoading] = useState(false);
  const [mounted, setMounted] = useState(false);

  React.useEffect(() => {
    setMounted(true);
  }, []);

  const validateDateRange = (from: Dayjs | null, to: Dayjs | null): string | null => {
    if (!from || !to) {
      return 'Veuillez sélectionner les deux dates';
    }

    if (from.isAfter(to)) {
      return 'La date de début doit être antérieure à la date de fin';
    }

    const maxDays = 365; // Depuis les variables d'environnement
    const diffDays = to.diff(from, 'day');
    
    if (diffDays > maxDays) {
      return `La période ne peut pas dépasser ${maxDays} jours`;
    }

    if (from.isAfter(dayjs())) {
      return 'La date de début ne peut pas être dans le futur';
    }

    return null;
  };

  const handlePreview = async () => {
    const validationError = validateDateRange(fromDate, toDate);
    if (validationError) {
      setError(validationError);
      return;
    }

    setError(null);
    setIsPreviewLoading(true);

    try {
      const response = await fetch('/api/playlist', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: fromDate!.format('YYYY-MM-DD'),
          to: toDate!.format('YYYY-MM-DD'),
        }),
      });

      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error || 'Erreur lors de la récupération des informations');
      }

      const info = await response.json();
      setPreviewInfo(info);
      onPreviewInfo(info);

    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erreur inconnue');
      setPreviewInfo(null);
    } finally {
      setIsPreviewLoading(false);
    }
  };

  const handleGenerate = () => {
    console.log('🔍 DateSelector Debug Info:');
    console.log('  - fromDate:', fromDate?.format('YYYY-MM-DD'));
    console.log('  - toDate:', toDate?.format('YYYY-MM-DD'));
    
    const validationError = validateDateRange(fromDate, toDate);
    if (validationError) {
      setError(validationError);
      return;
    }

    setError(null);
    console.log('🚀 Calling onDateRangeSelect with:', fromDate!.format('YYYY-MM-DD'), toDate!.format('YYYY-MM-DD'));
    onDateRangeSelect(
      fromDate!.format('YYYY-MM-DD'),
      toDate!.format('YYYY-MM-DD')
    );
  };

  const handleQuickSelect = (days: number) => {
    const today = dayjs();
    const startDate = today.subtract(days, 'day');
    setFromDate(startDate);
    setToDate(today);
    setError(null);
    setPreviewInfo(null);
  };

  if (!mounted) {
    return (
      <div className="w-full max-w-4xl mx-auto p-6 bg-white rounded-lg shadow-lg">
        <h2 className="text-2xl font-bold text-gray-800 mb-6 text-center">
          Sélection de la période d&apos;observation
        </h2>
        <div className="flex items-center justify-center py-8">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
          <span className="ml-2">Chargement...</span>
        </div>
      </div>
    );
  }

  return (
    <LocalizationProvider dateAdapter={AdapterDayjs} adapterLocale="fr">
      <div className="w-full max-w-4xl mx-auto p-6 bg-white rounded-lg shadow-lg">
        <h2 className="text-2xl font-bold text-gray-800 mb-6 text-center">
          Sélection de la période d&apos;observation
        </h2>

        {/* Sélecteurs rapides */}
        <div className="mb-6">
          <p className="text-sm font-medium text-gray-700 mb-3">Sélections rapides:</p>
          <div className="flex flex-wrap gap-2">
            {[
              { label: 'Dernière semaine', days: 7 },
              { label: 'Dernier mois', days: 30 },
              { label: 'Derniers 3 mois', days: 90 },
              { label: 'Dernière année', days: 365 },
            ].map(({ label, days }) => (
              <Button
                key={days}
                variant="outlined"
                size="small"
                onClick={() => handleQuickSelect(days)}
                className="text-xs"
              >
                {label}
              </Button>
            ))}
          </div>
        </div>

        {/* Sélecteurs de dates */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
          <DatePicker
            label="Date de début"
            value={fromDate}
            onChange={(newValue) => {
              setFromDate(newValue);
              setError(null);
              setPreviewInfo(null);
            }}
            maxDate={dayjs()}
            slotProps={{
              textField: {
                fullWidth: true,
                variant: 'outlined',
              },
            }}
          />
          
          <DatePicker
            label="Date de fin"
            value={toDate}
            onChange={(newValue) => {
              setToDate(newValue);
              setError(null);
              setPreviewInfo(null);
            }}
            minDate={fromDate || undefined}
            maxDate={dayjs()}
            slotProps={{
              textField: {
                fullWidth: true,
                variant: 'outlined',
              },
            }}
          />
        </div>

        {/* Affichage des erreurs */}
        {error && (
          <Alert severity="error" className="mb-4">
            {error}
          </Alert>
        )}

        {/* Boutons d'action */}
        <div className="flex flex-col sm:flex-row gap-3 mb-6">
          <Button
            variant="outlined"
            onClick={handlePreview}
            disabled={!fromDate || !toDate || isPreviewLoading}
            startIcon={isPreviewLoading ? <CircularProgress size={20} /> : null}
            className="flex-1"
          >
            {isPreviewLoading ? 'Analyse...' : 'Aperçu des données'}
          </Button>
          
          <Button
            variant="contained"
            onClick={handleGenerate}
            disabled={!fromDate || !toDate || isLoading}
            startIcon={isLoading ? <CircularProgress size={20} /> : null}
            className="flex-1 bg-blue-600 hover:bg-blue-700"
          >
            {isLoading ? 'Génération...' : 'Générer l\'animation'}
          </Button>
        </div>

        {/* Informations de prévisualisation */}
        {previewInfo && (
          <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
            <h3 className="font-semibold text-blue-800 mb-2">
              Informations sur la période sélectionnée
            </h3>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
              <div>
                <span className="font-medium text-blue-700">Jours disponibles:</span>
                <p className="text-blue-600">{previewInfo.availableDays}</p>
              </div>
              <div>
                <span className="font-medium text-blue-700">Segments vidéo:</span>
                <p className="text-blue-600">{previewInfo.totalSegments}</p>
              </div>
              <div>
                <span className="font-medium text-blue-700">Durée estimée:</span>
                <p className="text-blue-600">{previewInfo.estimatedDurationFormatted}</p>
              </div>
              <div>
                <span className="font-medium text-blue-700">Qualité:</span>
                <p className="text-blue-600">25 FPS</p>
              </div>
            </div>
          </div>
        )}

        {/* Aide */}
        <div className="mt-6 text-xs text-gray-500 text-center">
          💡 Sélectionnez une période pour générer une animation des images satellitaires.
          <br />
          La durée maximale est limitée à 1 an pour des raisons de performance.
        </div>
      </div>
    </LocalizationProvider>
  );
}
