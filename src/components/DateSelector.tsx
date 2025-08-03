'use client';

import React, { useState, useEffect } from 'react';
import { DateRange } from 'react-date-range';
import { Button, Alert, CircularProgress } from '@mui/material';
import { fr } from 'date-fns/locale';
import 'react-date-range/dist/styles.css';
import 'react-date-range/dist/theme/default.css';

interface DateSelectorProps {
  onDateRangeSelect: (from: string, to: string) => void;
  onPreviewInfo: (info: PlaylistInfo) => void;
  isLoading?: boolean;
  defaultDateRange?: [string, string];
}

interface PlaylistInfo {
  availableDays: number;
  totalSegments: number;
  estimatedDurationSeconds: number;
  estimatedDurationFormatted: string;
}

function validateDateRange(range: { startDate: Date; endDate: Date }) {
  if (!range.startDate || !range.endDate) return "Veuillez sélectionner une période.";
  const diff = (range.endDate.getTime() - range.startDate.getTime()) / (1000 * 3600 * 24);
  if (diff < 0) return "La date de fin doit être après la date de début.";
  if (diff > 365) return "La période ne peut pas dépasser 1 an.";
  return null;
}

function formatDateLocal(date: Date) {
  const yyyy = date.getFullYear();
  const mm = String(date.getMonth() + 1).padStart(2, '0');
  const dd = String(date.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

export default function DateSelector({
  onDateRangeSelect,
  onPreviewInfo,
  isLoading = false,
  defaultDateRange,
  children,
}: React.PropsWithChildren<DateSelectorProps>) {
  const [range, setRange] = useState({
    startDate: defaultDateRange?.[0] ? new Date(defaultDateRange[0]) : new Date(),
    endDate: defaultDateRange?.[1] ? new Date(defaultDateRange[1]) : new Date(),
    key: "selection",
  });
  const [error, setError] = useState<string | null>(null);
  const [isPreviewLoading, setIsPreviewLoading] = useState(false);
  const [previewInfo, setPreviewInfo] = useState<PlaylistInfo | null>(null);

  // Simule le chargement côté client
  const [mounted, setMounted] = useState(false);
  useEffect(() => {
    setMounted(true);
  }, []);

  const handleQuickSelect = (days: number) => {
    const today = new Date();
    const startDate = new Date(today.getTime() - days * 24 * 60 * 60 * 1000);
    setRange({ startDate, endDate: today, key: "selection" });
    setError(null);
    setPreviewInfo(null);
  };

  const handlePreview = async () => {
    setIsPreviewLoading(true);
    try {
      const validationError = validateDateRange(range);
      if (validationError) {
        setError(validationError);
        return;
      }
      setError(null);
      // Simule une requête d'aperçu
      const info: PlaylistInfo = {
        availableDays: Math.round((range.endDate.getTime() - range.startDate.getTime()) / (1000 * 3600 * 24)) + 1,
        totalSegments: Math.round((range.endDate.getTime() - range.startDate.getTime()) / (1000 * 3600 * 24)) * 24,
        estimatedDurationSeconds: Math.round((range.endDate.getTime() - range.startDate.getTime()) / (1000 * 3600 * 24)) * 24 * 10,
        estimatedDurationFormatted: `${Math.round((range.endDate.getTime() - range.startDate.getTime()) / (1000 * 3600 * 24)) * 4} min`,
      };
      setPreviewInfo(info);
      onPreviewInfo(info);
    } finally {
      setIsPreviewLoading(false);
    }
  };

  const handleGenerate = () => {
    const validationError = validateDateRange(range);
    if (validationError) {
      setError(validationError);
      return;
    }
    setError(null);
    const startDateCorrected = new Date(range.startDate);
    startDateCorrected.setDate(startDateCorrected.getDate() + 1);
    const endDateInclusive = new Date(range.endDate);
    endDateInclusive.setDate(endDateInclusive.getDate() + 1);
    onDateRangeSelect(
      formatDateLocal(startDateCorrected),
      formatDateLocal(endDateInclusive)
    );
  };

  return (
    <div className="w-full space-y-4">
      <h3 className="text-lg font-semibold text-purple-300">📅 Période d'observation</h3>
      {/* Sélecteurs rapides */}
      <div>
        <p className="text-sm font-medium text-gray-300 mb-2">Sélections rapides:</p>
        <div className="flex flex-wrap gap-2">
          {[
            { label: '7j', days: 7 },
            { label: '30j', days: 30 },
            { label: '90j', days: 90 },
            { label: '1an', days: 365 },
          ].map(({ label, days }) => (
            <Button
              key={days}
              variant="outlined"
              size="small"
              onClick={() => handleQuickSelect(days)}
              sx={{
                minWidth: '50px',
                fontSize: '12px',
                color: '#a78bfa',
                borderColor: '#a78bfa',
                '&:hover': {
                  borderColor: '#7c3aed',
                  backgroundColor: '#7c3aed20',
                },
              }}
            >
              {label}
            </Button>
          ))}
        </div>
      </div>
      {/* Sélecteur de plage de dates */}
      <div className="mb-4">
        <div className="w-full flex justify-center">
          <DateRange
            ranges={[range]}
            onChange={(item: any) => {
              setRange(item.selection);
              setError(null);
              setPreviewInfo(null);
            }}
            moveRangeOnFirstSelection={false}
            showMonthAndYearPickers={true}
            locale={fr}
            rangeColors={["#7c3aed"]}
            color="#7c3aed"
            direction="horizontal"
            months={1}
            minDate={new Date('2000-01-01')}
            maxDate={new Date()}
            className="rounded-lg shadow-lg bg-[#232336] text-white border border-[#2d2d44] max-w-[320px] w-full"
          />
        </div>
      </div>
      {/* Bloc Sélection du Dataset Satellitaire inséré ici */}
      {children}
      {/* Affichage des erreurs */}
      {error && (
        <Alert
          severity="error"
          sx={{
            backgroundColor: '#7f1d1d',
            color: '#fecaca',
            borderColor: '#dc2626',
            marginBottom: '16px',
          }}
        >
          {error}
        </Alert>
      )}
      {/* Boutons d'action */}
      <div className="flex flex-col gap-2">
        {/* Aperçu masqué */}
        {/*
        <Button
          variant="outlined"
          onClick={handlePreview}
          disabled={!range.startDate || !range.endDate || isPreviewLoading}
          startIcon={isPreviewLoading ? <CircularProgress size={16} /> : null}
          sx={{
            color: '#a78bfa',
            borderColor: '#a78bfa',
            fontSize: '14px',
            padding: '8px 16px',
            '&:hover': {
              borderColor: '#7c3aed',
              backgroundColor: '#7c3aed20',
            },
            '&:disabled': {
              color: '#6b7280',
              borderColor: '#4b5563',
            },
          }}
        >
          {isPreviewLoading ? 'Analyse...' : 'Aperçu'}
        </Button>
        */}
        <Button
          variant="contained"
          onClick={handleGenerate}
          disabled={!range.startDate || !range.endDate || isLoading}
          startIcon={isLoading ? <CircularProgress size={16} /> : null}
          sx={{
            backgroundColor: '#7c3aed',
            color: '#ffffff',
            fontSize: '14px',
            padding: '8px 16px',
            '&:hover': {
              backgroundColor: '#6d28d9',
            },
            '&:disabled': {
              backgroundColor: '#4b5563',
              color: '#9ca3af',
            },
          }}
        >
          {isLoading ? 'Génération...' : "Actualiser la période"}
        </Button>
      </div>
      {/* Informations de prévisualisation */}
      {previewInfo && (
        <div className="bg-[#232336] border border-[#2d2d44] rounded-lg p-4 mt-4">
          <h4 className="font-semibold text-purple-300 mb-3 text-sm">ℹ️ Informations sur la période</h4>
          <div className="grid grid-cols-2 gap-3 text-xs">
            <div className="text-center p-2 rounded bg-blue-900/30">
              <div className="font-bold text-blue-400">{previewInfo.availableDays}</div>
              <div className="text-blue-300">Jours</div>
            </div>
            <div className="text-center p-2 rounded bg-green-900/30">
              <div className="font-bold text-green-400">{previewInfo.totalSegments}</div>
              <div className="text-green-300">Segments</div>
            </div>
            <div className="text-center p-2 rounded bg-purple-900/30 col-span-2">
              <div className="font-bold text-purple-300">{previewInfo.estimatedDurationFormatted}</div>
              <div className="text-purple-200">Durée estimée</div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
