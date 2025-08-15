'use client';

import { useEffect, useRef, useState, useMemo } from 'react';

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

interface VideoPlayerProps {
  fromDate: Date;
  toDate: Date;
  selectedDataset?: SatelliteDataset | null;
  className?: string;
}


export default function VideoPlayer({ fromDate, toDate, selectedDataset, className }: VideoPlayerProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const hlsRef = useRef<unknown>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [mounted, setMounted] = useState(false);
  const [playbackRate, setPlaybackRate] = useState(1);
  const [loadingProgress, setLoadingProgress] = useState(0);
  const [loadingStage, setLoadingStage] = useState('Initialisation...');

  const formattedFromDate = useMemo(() => fromDate.toISOString().split('T')[0], [fromDate]);
  const formattedToDate = useMemo(() => toDate.toISOString().split('T')[0], [toDate]);

  // Reset states when dates or dataset change
  useEffect(() => {
    setIsLoading(true);
    setError(null);
  }, [formattedFromDate, formattedToDate, selectedDataset]);

  useEffect(() => {
    setMounted(true);
    return () => setMounted(false);
  }, []);

  // Appliquer la vitesse de lecture à chaque changement
  useEffect(() => {
    if (videoRef.current) {
      videoRef.current.playbackRate = playbackRate;
    }
  }, [playbackRate]);

  useEffect(() => {
    if (!mounted || !videoRef.current) return;

    // Ne rien faire si les paramètres essentiels ne sont pas définis
    if (!selectedDataset || !selectedDataset.satellite || !selectedDataset.sector || !selectedDataset.product || !selectedDataset.resolution || !fromDate || !toDate) {
      console.log('⏸️ Paramètres incomplets, player non initialisé');
      return;
    }

    const video = videoRef.current;

    // Construire l'URL de la playlist HLS
    const playlistUrl = `/api/playlist?satellite=${encodeURIComponent(selectedDataset.satellite)}&sector=${encodeURIComponent(selectedDataset.sector)}&product=${encodeURIComponent(selectedDataset.product)}&resolution=${encodeURIComponent(selectedDataset.resolution)}&from=${formattedFromDate}&to=${formattedToDate}`;
    console.log('🛰️ Using dataset API playlist:', playlistUrl);

    // Try native HLS first (Safari, iOS)
    if (video.canPlayType('application/vnd.apple.mpegurl')) {
      console.log('🍎 Using native HLS support');
      setLoadingStage('Connexion au serveur...');
      setLoadingProgress(25);
      
      // Add error handlers for native HLS
      const handleNativeError = (e: Event) => {
        console.error('❌ Native HLS error:', e);
        setError(`Aucune vidéo disponible pour la période du ${fromDate.toLocaleDateString('fr-FR')} au ${toDate.toLocaleDateString('fr-FR')}`);
        setIsLoading(false);
      };
      
      const handleNativeLoad = () => {
        console.log('✅ Native HLS loaded');
        setLoadingStage('Chargement terminé');
        setLoadingProgress(100);
        setIsLoading(false);
      };
      
      video.addEventListener('error', handleNativeError);
      video.addEventListener('loadeddata', handleNativeLoad);
      
      video.src = playlistUrl;
      
      // Appliquer la vitesse de lecture après chargement
      video.playbackRate = playbackRate;

      // Return cleanup function for native HLS
      return () => {
        console.log('🧹 Cleaning up Native HLS');
        video.removeEventListener('error', handleNativeError);
        video.removeEventListener('loadeddata', handleNativeLoad);
      };
    } else {
      // Use HLS.js for other browsers with dynamic import
      import('hls.js').then((hlsModule) => {
        const Hls = hlsModule.default;
        
        if (Hls.isSupported()) {
          console.log('📱 Using HLS.js for:', playlistUrl);
          setLoadingStage('Chargement du lecteur...');
          setLoadingProgress(10);
          
          // Cleanup previous instance
          if (hlsRef.current) {
            (hlsRef.current as { destroy: () => void }).destroy();
          }

          const hls = new Hls({
            debug: false,
            enableWorker: false,
            lowLatencyMode: false,
            maxBufferLength: 30,
            maxMaxBufferLength: 60,
            maxBufferSize: 30 * 1000 * 1000,
            maxBufferHole: 0.1,
          });

          hlsRef.current = hls;

          // Essential event listeners
          hls.on(Hls.Events.MANIFEST_PARSED, (event: string, data: unknown) => {
            const eventData = data as { levels?: unknown[]; totalduration?: number };
            console.log('✅ Manifest parsed successfully:', {
              levels: eventData.levels?.length || 0,
              duration: eventData.totalduration
            });
            setLoadingStage('Préparation de la vidéo...');
            setLoadingProgress(70);
            setIsLoading(false);
            // Appliquer la vitesse de lecture après parsing
            if (video) video.playbackRate = playbackRate;
          });

          hls.on(Hls.Events.LEVEL_LOADED, (event: string, data: unknown) => {
            const eventData = data as { level?: number; details?: { fragments?: unknown[]; totalduration?: number } };
            console.log('✅ Level loaded:', {
              level: eventData.level,
              fragments: eventData.details?.fragments?.length || 0,
              duration: eventData.details?.totalduration || 0
            });
            setLoadingStage('Chargement des segments...');
            setLoadingProgress(85);
          });

          hls.on(Hls.Events.FRAG_LOADED, (event: string, data: unknown) => {
            const eventData = data as { frag?: { url?: string; duration?: number } };
            console.log('✅ Fragment loaded:', {
              url: eventData.frag?.url,
              duration: eventData.frag?.duration
            });
          });

          hls.on(Hls.Events.ERROR, (event: string, data: unknown) => {
            const eventData = data as { type?: string; details?: string; fatal?: boolean; url?: string };
            console.error('❌ HLS Error:', {
              type: eventData.type,
              details: eventData.details,
              fatal: eventData.fatal,
              url: eventData.url
            });
            
            if (eventData.fatal) {
              switch (eventData.type) {
                case Hls.ErrorTypes.NETWORK_ERROR:
                  console.log('🔄 Fatal network error, trying to recover...');
                  // Check if it's a 404 or empty playlist
                  if (eventData.details === Hls.ErrorDetails.MANIFEST_LOAD_ERROR) {
                    setError(`Aucune vidéo disponible pour la période du ${fromDate.toLocaleDateString('fr-FR')} au ${toDate.toLocaleDateString('fr-FR')}`);
                    setIsLoading(false);
                    return;
                  }
                  setTimeout(() => {
                    if (hlsRef.current) {
                      (hlsRef.current as { startLoad: () => void }).startLoad();
                    }
                  }, 2000);
                  break;
                case Hls.ErrorTypes.MEDIA_ERROR:
                  console.log('🔄 Fatal media error, trying to recover...');
                  setTimeout(() => {
                    if (hlsRef.current) {
                      (hlsRef.current as { recoverMediaError: () => void }).recoverMediaError();
                    }
                  }, 2000);
                  break;
                default:
                  setError(`Erreur de lecture: ${eventData.details}`);
                  setIsLoading(false);
                  break;
              }
            }
          });

          // Load source with validation and attach media
          const loadPlaylist = async () => {
            console.log('🔄 Loading playlist:', playlistUrl);
            
            try {
              const response = await fetch(playlistUrl);
              if (!response.ok) {
                if (response.status === 404) {
                  setError(`Aucune vidéo disponible pour la période du ${fromDate.toLocaleDateString('fr-FR')} au ${toDate.toLocaleDateString('fr-FR')}`);
                } else {
                  setError(`Erreur ${response.status}: ${response.statusText}`);
                }
                setIsLoading(false);
                return;
              }
              
              const playlistContent = await response.text();
              console.log('📋 Playlist content preview:', playlistContent.substring(0, 200));
              
              // Check if playlist has actual segments
              if (!playlistContent.includes('#EXTINF') || !playlistContent.includes('.ts')) {
                setError(`Aucune vidéo disponible pour la période du ${fromDate.toLocaleDateString('fr-FR')} au ${toDate.toLocaleDateString('fr-FR')}`);
                setIsLoading(false);
                return;
              }
              
              // If playlist looks valid, load it with HLS.js
              hls.loadSource(playlistUrl);
              hls.attachMedia(video);
              // Appliquer la vitesse de lecture après attachement
              if (video) video.playbackRate = playbackRate;
            } catch (err) {
              console.error('❌ Error checking playlist:', err);
              setError('Erreur lors de la vérification de la vidéo');
              setIsLoading(false);
            }
          };
          
          loadPlaylist();

          // Video event listeners for debugging
          video.addEventListener('loadedmetadata', () => {
            console.log('📺 Video metadata loaded:', {
              duration: video.duration,
              dimensions: `${video.videoWidth}x${video.videoHeight}`
            });
            // Appliquer la vitesse de lecture après chargement des métadonnées
            video.playbackRate = playbackRate;
          });

          video.addEventListener('canplay', () => {
            console.log('📺 Video ready to play');
          });

        } else {
          setError('HLS not supported in this browser');
        }
      }).catch((err) => {
        console.error('Failed to load HLS.js:', err);
        setError('Impossible de charger le lecteur vidéo');
      });
    }

    return () => {
      console.log('🧹 Cleaning up VideoPlayer');
      if (hlsRef.current) {
        (hlsRef.current as { destroy: () => void }).destroy();
        hlsRef.current = null;
      }
    };
  }, [formattedFromDate, formattedToDate, mounted, fromDate, toDate, selectedDataset, playbackRate]);

  if (!mounted) {
    return (
      <div className="w-full h-96 bg-gray-100 rounded-lg flex items-center justify-center">
        <div className="text-gray-500">Initialisation du lecteur...</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="w-full h-96 bg-red-50 rounded-lg flex items-center justify-center">
        <div className="text-red-600">{error}</div>
      </div>
    );
  }

  return (
    <div className={`w-full h-full relative rounded-2xl ${className ?? ''}`}>
      <div className="relative w-full h-full">
        <video
          ref={videoRef}
          controls
          className="w-full h-full bg-black rounded-lg"
          poster="/placeholder-satellite.jpg"
          muted
          playsInline
        >
          Votre navigateur ne supporte pas la lecture vidéo.
        </video>
        {/* Bouton jauge minimaliste en haut à droite */}
        <div className="absolute top-4 right-4 z-20">
          <SpeedPopover playbackRate={playbackRate} setPlaybackRate={setPlaybackRate} />
        </div>
      </div>
      {isLoading && (
        <div className="absolute inset-0 flex items-center justify-center bg-[#181820] bg-opacity-90 rounded-lg backdrop-blur-sm">
          <div className="flex flex-col items-center gap-6">
            {/* Indicateur circulaire */}
            <div className="relative w-20 h-20">
              {/* Cercle de fond */}
              <svg className="w-20 h-20 transform -rotate-90" viewBox="0 0 80 80">
                <circle
                  cx="40"
                  cy="40"
                  r="36"
                  stroke="#2d2d44"
                  strokeWidth="8"
                  fill="none"
                />
                {/* Cercle de progression */}
                <circle
                  cx="40"
                  cy="40"
                  r="36"
                  stroke="#a78bfa"
                  strokeWidth="8"
                  fill="none"
                  strokeLinecap="round"
                  strokeDasharray={226.19}
                  strokeDashoffset={226.19 - (226.19 * loadingProgress) / 100}
                  className="transition-all duration-500 ease-out"
                />
              </svg>
              {/* Pourcentage au centre */}
              <div className="absolute inset-0 flex items-center justify-center">
                <span className="text-purple-300 font-semibold text-lg">
                  {Math.round(loadingProgress)}%
                </span>
              </div>
            </div>
            
            {/* Étape de chargement */}
            <div className="text-center">
              <div className="text-purple-300 font-medium mb-1">🛰️ Chargement de la vidéo</div>
              <div className="text-gray-400 text-sm">{loadingStage}</div>
            </div>
            
            {/* Animation de points */}
            <div className="flex gap-1">
              <div className="w-2 h-2 bg-purple-400 rounded-full animate-pulse"></div>
              <div className="w-2 h-2 bg-purple-400 rounded-full animate-pulse" style={{ animationDelay: '0.2s' }}></div>
              <div className="w-2 h-2 bg-purple-400 rounded-full animate-pulse" style={{ animationDelay: '0.4s' }}></div>
            </div>
          </div>
        </div>
      )}
      <div className="absolute top-4 left-4 bg-black bg-opacity-50 text-white p-2 rounded">
        📅 {formattedFromDate === formattedToDate 
          ? fromDate.toLocaleDateString('fr-FR')
          : `${fromDate.toLocaleDateString('fr-FR')} - ${toDate.toLocaleDateString('fr-FR')}`
        }
      </div>
    </div>
  );

}

// Composant popover pour la sélection de vitesse
function SpeedPopover({ playbackRate, setPlaybackRate }: { playbackRate: number, setPlaybackRate: (v: number) => void, minimal?: boolean }) {
  const [open, setOpen] = useState(false);
  const rates = [0.1, 0.25, 0.5, 1, 1.5, 2, 5, 10];
  // Pour fermer le menu si clic ailleurs
  useEffect(() => {
    if (!open) return;
    const close = () => {
      setOpen(false);
    };
    window.addEventListener('click', close);
    return () => window.removeEventListener('click', close);
  }, [open]);
  return (
    <div className="relative pointer-events-auto">
      <button
        type="button"
        aria-label="Vitesse de lecture"
        className={`flex items-center justify-center w-8 h-8 rounded-full bg-gray-800 hover:bg-gray-700 border border-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-colors ${open ? 'ring-2 ring-blue-400' : ''}`}
        onClick={e => { e.stopPropagation(); setOpen(o => !o); }}
      >
        {/* Icône jauge/tachymètre SVG minimaliste */}
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-white">
          <path d="M12 21a9 9 0 1 0-9-9" />
          <path d="M12 3v4" />
          <path d="M12 12l3-3" />
          <circle cx="12" cy="12" r="1.5" fill="currentColor" />
        </svg>
      </button>
      {open && (
        <div className="absolute top-10 right-0 bg-gray-900 border border-gray-700 rounded shadow-lg z-50 min-w-[90px]">
          {rates.map(rate => (
            <button
              key={rate}
              className={`w-full text-left px-4 py-2 text-sm text-white hover:bg-blue-600 ${playbackRate === rate ? 'bg-blue-700 font-bold' : ''}`}
              onClick={e => { e.stopPropagation(); setPlaybackRate(rate); setOpen(false); }}
            >
              {rate}x
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
