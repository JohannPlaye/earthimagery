'use client';

import React, { useState, useEffect, useRef } from 'react';
import { useAuth } from '@/contexts/AuthContext';

interface LogEntry {
  timestamp: string;
  level: string;
  message: string;
  raw: string;
}

interface LogFile {
  name: string;
  date: string;
  size: number;
}

export default function LogTerminal() {
  const { hasPermission } = useAuth();
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [availableLogFiles, setAvailableLogFiles] = useState<LogFile[]>([]);
  const [selectedLogFile, setSelectedLogFile] = useState<string>('');
  const [isRealTime, setIsRealTime] = useState(true);
  const [selectedDate, setSelectedDate] = useState<string>(''); // Pas de date par défaut pour charger tous les logs
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string>('');
  const terminalRef = useRef<HTMLDivElement>(null);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);

  // Fonction pour parser une ligne de log
  const parseLogLine = React.useCallback((line: string): LogEntry | null => {
    if (!line.trim()) return null;
    
    // Essayer de détecter différents formats de logs
    const timestampRegex = /(\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2})/;
    const levelRegex = /\[(DEBUG|INFO|WARN|ERROR|SUCCESS|FAIL)\]/i;
    
    const timestampMatch = line.match(timestampRegex);
    const levelMatch = line.match(levelRegex);
    
    return {
      timestamp: timestampMatch ? timestampMatch[1] : new Date().toISOString(),
      level: levelMatch ? levelMatch[1].toUpperCase() : 'INFO',
      message: line.replace(timestampRegex, '').replace(levelRegex, '').trim(),
      raw: line
    };
  }, []);

  // Fonction pour charger les fichiers de logs disponibles
  const loadAvailableLogFiles = React.useCallback(async (date?: string) => {
    try {
      const url = date ? `/api/logs/files?date=${date}` : '/api/logs/files';
      const response = await fetch(url);
      if (response.ok) {
        const files = await response.json();
        setAvailableLogFiles(files);
        
        // Sélectionner automatiquement le dernier fichier si en mode temps réel
        if (isRealTime && files.length > 0) {
          setSelectedLogFile(files[0].name);
        }
      }
    } catch (error) {
      console.error('Erreur lors du chargement des fichiers de logs:', error);
    }
  }, [isRealTime]);

  // Fonction pour charger le contenu d'un log
  const loadLogContent = React.useCallback(async (filename: string, isStreaming = false) => {
    try {
      setIsLoading(true);
      setError('');
      
      const response = await fetch(`/api/logs/content?file=${encodeURIComponent(filename)}&stream=${isStreaming}`);
      
      if (!response.ok) {
        throw new Error(`Erreur ${response.status}: ${response.statusText}`);
      }
      
      const content = await response.text();
      const lines = content.split('\n');
      const parsedLogs = lines
        .map(parseLogLine)
        .filter((log): log is LogEntry => log !== null);
      
      if (isStreaming) {
        // En mode streaming, ajouter seulement les nouvelles lignes
        setLogs(prev => {
          const newLogs = parsedLogs.filter(newLog => 
            !prev.some(existingLog => existingLog.raw === newLog.raw)
          );
          return [...prev, ...newLogs];
        });
      } else {
        // Remplacer tout le contenu
        setLogs(parsedLogs);
      }
      
    } catch (error) {
      console.error('Erreur lors du chargement du log:', error);
      setError(error instanceof Error ? error.message : 'Erreur de chargement');
    } finally {
      setIsLoading(false);
    }
  }, [parseLogLine]);

  // Auto-scroll vers le bas
  useEffect(() => {
    if (terminalRef.current) {
      terminalRef.current.scrollTop = terminalRef.current.scrollHeight;
    }
  }, [logs]);

  // Charger les fichiers disponibles quand la date change
  useEffect(() => {
    loadAvailableLogFiles(selectedDate || undefined);
  }, [selectedDate, loadAvailableLogFiles]);

  // Gestion du mode temps réel
  useEffect(() => {
    if (isRealTime && selectedLogFile) {
      // Charger le contenu initial
      loadLogContent(selectedLogFile, false);
      
      // Démarrer le polling en temps réel
      intervalRef.current = setInterval(() => {
        loadLogContent(selectedLogFile, true);
      }, 2000); // Rafraîchir toutes les 2 secondes
      
      return () => {
        if (intervalRef.current) {
          clearInterval(intervalRef.current);
        }
      };
    } else if (intervalRef.current) {
      clearInterval(intervalRef.current);
    }
  }, [isRealTime, selectedLogFile, loadLogContent]);

  // Charger le log sélectionné quand il change (mode manuel)
  useEffect(() => {
    if (!isRealTime && selectedLogFile) {
      loadLogContent(selectedLogFile, false);
    }
  }, [selectedLogFile, isRealTime, loadLogContent]);

  // Vérification des permissions
  if (!hasPermission('dataset_manage')) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="text-center">
          <div className="text-6xl mb-4">🔒</div>
          <h3 className="text-lg font-semibold text-purple-300 mb-2">
            Accès restreint
          </h3>
          <p className="text-gray-400">
            Seuls les administrateurs peuvent accéder aux logs.
          </p>
        </div>
      </div>
    );
  }

  // Fonction pour obtenir la couleur selon le niveau de log
  const getLogLevelColor = (level: string) => {
    switch (level) {
      case 'ERROR': case 'FAIL': return 'text-red-400';
      case 'WARN': return 'text-yellow-400';
      case 'SUCCESS': return 'text-green-400';
      case 'DEBUG': return 'text-gray-400';
      default: return 'text-white';
    }
  };

  return (
    <div className="h-full flex flex-col bg-[#101828] text-white">
      {/* Header avec contrôles */}
      <div className="p-4 border-b border-[#2d2d44] bg-[#232336]">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-purple-300 flex items-center gap-2">
            📟 Terminal de logs
            {isRealTime && (
              <span className="inline-block w-2 h-2 bg-green-400 rounded-full animate-pulse"></span>
            )}
          </h3>
          <div className="text-xs text-gray-400">
            {logs.length} entrées
          </div>
        </div>
        
        <div className="flex flex-wrap items-center gap-4">
          {/* Switch temps réel / manuel */}
          <div className="flex items-center gap-2">
            <label className="text-sm text-gray-300">Mode :</label>
            <button
              onClick={() => setIsRealTime(!isRealTime)}
              className={`px-3 py-1 rounded text-xs font-medium transition-colors ${
                isRealTime 
                  ? 'bg-green-600 text-white' 
                  : 'bg-gray-600 text-gray-300 hover:bg-gray-500'
              }`}
            >
              {isRealTime ? '🔴 Temps réel' : '📁 Manuel'}
            </button>
          </div>

          {/* Sélecteur de date */}
          {!isRealTime && (
            <div className="flex items-center gap-2">
              <label className="text-sm text-gray-300">Date :</label>
              <input
                type="date"
                value={selectedDate}
                onChange={(e) => setSelectedDate(e.target.value)}
                className="px-2 py-1 bg-[#232336] border border-[#2d2d44] rounded text-white text-xs"
              />
            </div>
          )}

          {/* Sélecteur de fichier */}
          {availableLogFiles.length > 0 && (
            <div className="flex items-center gap-2">
              <label className="text-sm text-gray-300">Fichier :</label>
              <select
                value={selectedLogFile}
                onChange={(e) => setSelectedLogFile(e.target.value)}
                className="px-2 py-1 bg-[#232336] border border-[#2d2d44] rounded text-white text-xs"
                disabled={isRealTime}
              >
                <option value="">Sélectionner un fichier</option>
                {availableLogFiles.map((file) => (
                  <option key={file.name} value={file.name}>
                    {file.name} ({(file.size / 1024).toFixed(1)}KB)
                  </option>
                ))}
              </select>
            </div>
          )}

          {/* Bouton clear */}
          <button
            onClick={() => setLogs([])}
            className="px-3 py-1 bg-gray-600 hover:bg-gray-500 rounded text-xs transition-colors"
          >
            🗑️ Effacer
          </button>
        </div>
      </div>

      {/* Zone de terminal */}
      <div
        ref={terminalRef}
        className="flex-1 p-4 overflow-y-auto font-mono text-sm bg-black"
        style={{ minHeight: '400px' }}
      >
        {error && (
          <div className="text-red-400 mb-4 p-2 bg-red-900/20 border border-red-700 rounded">
            ❌ {error}
          </div>
        )}
        
        {isLoading && logs.length === 0 && (
          <div className="text-gray-400 text-center py-8">
            📂 Chargement des logs...
          </div>
        )}
        
        {logs.length === 0 && !isLoading && !error && (
          <div className="text-gray-400 text-center py-8">
            📝 Aucun log disponible
            <br />
            <span className="text-xs">
              {isRealTime ? 'En attente de nouveaux logs...' : 'Sélectionnez un fichier de log'}
            </span>
          </div>
        )}
        
        {logs.map((log, index) => (
          <div key={index} className="mb-1 leading-tight">
            <span className="text-gray-500 text-xs">
              {log.timestamp.substring(11, 19)}
            </span>
            <span className={`ml-2 text-xs font-bold ${getLogLevelColor(log.level)}`}>
              [{log.level}]
            </span>
            <span className="ml-2 text-gray-100">
              {log.message}
            </span>
          </div>
        ))}
        
        {isRealTime && (
          <div className="text-green-400 text-xs mt-2 opacity-60">
            ⚡ Surveillance en temps réel active...
          </div>
        )}
      </div>
    </div>
  );
}
