'use client';

import { useEffect, useRef, useState, useMemo } from 'react';

// Types pour hls.js
interface HlsInstance {
  loadSource: (src: string) => void;
  attachMedia: (media: HTMLVideoElement) => void;
  destroy: () => void;
  startLoad: () => void;
  bufferController?: {
    flushBuffer: (start: number, end: number, type: string) => void;
  };
  on: (event: string, callback: (...args: unknown[]) => void) => void;
  off: (event: string, callback: (...args: unknown[]) => void) => void;
}

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
  const [segmentsLoaded, setSegmentsLoaded] = useState(0);
  const [segmentsTotal, setSegmentsTotal] = useState(0);

  const formattedFromDate = useMemo(() => fromDate.toISOString().split('T')[0], [fromDate]);
  const formattedToDate = useMemo(() => toDate.toISOString().split('T')[0], [toDate]);

  // Calculer la progression et autoriser la lecture à 2/3
  const targetSegments = Math.ceil(segmentsTotal * 2 / 3); // 2/3 des segments = 100%
  const progress = targetSegments > 0 ? Math.min(segmentsLoaded / targetSegments, 1) : 0;
  const canPlay = segmentsLoaded >= targetSegments;

  // Reset states when dates or dataset change
  useEffect(() => {
    setIsLoading(true);
    setError(null);
    setSegmentsLoaded(0);
    setSegmentsTotal(0);
  }, [formattedFromDate, formattedToDate, selectedDataset]);

  // Débloquer la lecture quand canPlay est vrai
  useEffect(() => {
    if (canPlay && isLoading && segmentsTotal > 0) {
      setIsLoading(false);
      setTimeout(() => {
        videoRef.current?.play();
      }, 500);
    }
  }, [canPlay, isLoading, segmentsTotal]);

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
      
      // Add error handlers for native HLS
      const handleNativeError = (e: Event) => {
        console.error('❌ Native HLS error:', e);
        setError(`Aucune vidéo disponible pour la période du ${fromDate.toLocaleDateString('fr-FR')} au ${toDate.toLocaleDateString('fr-FR')}`);
        setIsLoading(false);
      };
      
      const handleNativeLoad = () => {
        console.log('✅ Native HLS loaded');
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
          
          // Cleanup previous instance
          if (hlsRef.current) {
            (hlsRef.current as { destroy: () => void }).destroy();
          }

          const hls = new Hls({
            debug: false,
            enableWorker: true,
            lowLatencyMode: false,
            // Configuration buffer plus conservative pour éviter saturation
            maxBufferLength: 30, // Réduit pour éviter buffer full
            maxMaxBufferLength: 60, // Réduit également
            maxBufferSize: 100 * 1000 * 1000, // 100MB max (réduit de 200MB)
            maxBufferHole: 0.5, 
            // Configuration pour éviter les buffer full errors
            backBufferLength: 10, // Garder seulement 10s derrière
            // ADAPTATION DYNAMIQUE selon le nombre total de segments (sera ajusté après parsing)
            liveSyncDurationCount: 8, // Valeur par défaut, sera ajustée
            liveMaxLatencyDurationCount: 10, // Sera ajusté après parsing du manifest
            // Paramètres agressifs pour le préchargement
            startLevel: 0,
            capLevelToPlayerSize: false,
            maxLoadingDelay: 4,
            maxFragLookUpTolerance: 0.25,
            // Timeouts adaptés
            manifestLoadingTimeOut: 60000,
            manifestLoadingMaxRetry: 3,
            levelLoadingTimeOut: 60000,
            fragLoadingTimeOut: 300000,
            fragLoadingMaxRetry: 3,
            fragLoadingMaxRetryTimeout: 30000,
            // Paramètres ABR désactivés pour forcer le chargement
            abrEwmaFastLive: 3.0,
            abrEwmaSlowLive: 9.0,
            abrMaxWithRealBitrate: false,
            // Forcer le préchargement dès le début
            startFragPrefetch: true,
          });

          hlsRef.current = hls;

          // Fonction de purge agressive du cache
          const purgeOldSegments = () => {
            if (!video || !video.buffered || video.buffered.length === 0) return;
            
            const currentTime = video.currentTime;
            const purgeThreshold = 5; // Garder seulement 5 secondes derrière la position actuelle
            
            try {
              for (let i = 0; i < video.buffered.length; i++) {
                const start = video.buffered.start(i);
                const end = video.buffered.end(i);
                
                // Purger tout ce qui est plus de 5 secondes derrière
                if (end < currentTime - purgeThreshold) {
                  console.log('🧹 Purge segment ancien:', {
                    range: `${start.toFixed(1)}s - ${end.toFixed(1)}s`,
                    currentTime: currentTime.toFixed(1)
                  });
                  
                  const hlsInstance = hlsRef.current as HlsInstance;
                  if (hlsInstance.bufferController && hlsInstance.bufferController.flushBuffer) {
                    hlsInstance.bufferController.flushBuffer(start, end, 'video');
                  }
                }
                // Purger partiellement les segments qui commencent trop tôt
                else if (start < currentTime - purgeThreshold && end > currentTime - purgeThreshold) {
                  const purgeEnd = currentTime - purgeThreshold;
                  if (purgeEnd > start) {
                    console.log('🧹 Purge segment partiel:', {
                      range: `${start.toFixed(1)}s - ${purgeEnd.toFixed(1)}s`,
                      currentTime: currentTime.toFixed(1)
                    });
                    
                    const hlsInstance = hlsRef.current as HlsInstance;
                    if (hlsInstance.bufferController && hlsInstance.bufferController.flushBuffer) {
                      hlsInstance.bufferController.flushBuffer(start, purgeEnd, 'video');
                    }
                  }
                }
              }
            } catch (err) {
              console.warn('Erreur lors de la purge:', err);
            }
          };

          // Essential event listeners
          hls.on(Hls.Events.MANIFEST_PARSED, (event: string, data: unknown) => {
            const eventData = data as { levels?: { details?: { fragments?: unknown[] } }[]; totalduration?: number };
            const total = eventData.levels?.[0]?.details?.fragments?.length || 0;
            
            // Configuration adaptative selon le nombre de segments
            const targetSegments = Math.ceil(total * 2 / 3);
            const optimalSyncCount = Math.min(total, Math.max(targetSegments + 1, 3));
            
            console.log('✅ Manifest parsed successfully:', {
              levels: eventData.levels?.length || 0,
              duration: eventData.totalduration,
              totalSegments: total,
              targetSegments: targetSegments,
              optimalSyncCount: optimalSyncCount
            });
            
            // Adapter la configuration HLS selon le nombre de segments
            if (hls.config) {
              hls.config.liveSyncDurationCount = optimalSyncCount;
              hls.config.liveMaxLatencyDurationCount = Math.min(optimalSyncCount + 2, total);
              console.log('🔧 Configuration HLS adaptée:', {
                liveSyncDurationCount: hls.config.liveSyncDurationCount,
                liveMaxLatencyDurationCount: hls.config.liveMaxLatencyDurationCount
              });
            }
            
            setSegmentsTotal(total);
            setSegmentsLoaded(0);
            
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
          });

          hls.on(Hls.Events.FRAG_LOADED, (event: string, data: unknown) => {
            const eventData = data as { frag?: { url?: string; duration?: number; sn?: number } };
            console.log('✅ Fragment loaded:', {
              url: eventData.frag?.url,
              duration: eventData.frag?.duration,
              segmentNumber: eventData.frag?.sn,
              progress: `${segmentsLoaded + 1}/${segmentsTotal} (${Math.round(((segmentsLoaded + 1) / targetSegments) * 100)}%)`
            });
            
            // Incrémenter le compteur de segments chargés
            setSegmentsLoaded(prev => prev + 1);
            
            // Purger seulement si la vidéo est en cours de lecture (pas pendant le préchargement)
            if (video.currentTime > 0 && !video.paused) {
              setTimeout(() => {
                purgeOldSegments();
              }, 1000);
            }
          });

          // Logs détaillés pour traquer les échecs de chargement
          hls.on(Hls.Events.FRAG_LOADING, (event: string, data: unknown) => {
            const eventData = data as { frag?: { url?: string; sn?: number } };
            console.log('🔄 Fragment loading:', {
              url: eventData.frag?.url,
              segmentNumber: eventData.frag?.sn,
              currentProgress: `${segmentsLoaded}/${segmentsTotal}`
            });
          });

          hls.on(Hls.Events.FRAG_LOAD_EMERGENCY_ABORTED, (event: string, data: unknown) => {
            const eventData = data as { frag?: { url?: string; sn?: number } };
            console.warn('⚠️ Fragment load emergency aborted:', {
              url: eventData.frag?.url,
              segmentNumber: eventData.frag?.sn
            });
          });

          // Surveillance du blocage silencieux
          let lastFragmentTime = Date.now();
          hls.on(Hls.Events.FRAG_LOADING, () => {
            lastFragmentTime = Date.now();
          });

          // Détection de blocage après 30 secondes sans nouveau fragment
          const checkStalling = setInterval(() => {
            if (Date.now() - lastFragmentTime > 30000 && segmentsLoaded < targetSegments) {
              console.warn('🚨 BLOCAGE DÉTECTÉ:', {
                segmentsLoaded,
                targetSegments,
                timeSinceLastFragment: `${(Date.now() - lastFragmentTime) / 1000}s`,
                action: 'Tentative de relance'
              });
              
              // Forcer une relance
              try {
                if (hlsRef.current) {
                  (hlsRef.current as HlsInstance).startLoad();
                }
              } catch (err) {
                console.warn('Erreur lors de la relance:', err);
              }
            }
            
            // NOUVEAU : Forcer le chargement si on a pas assez de segments après 10 secondes
            if (Date.now() - lastFragmentTime > 10000 && segmentsLoaded < targetSegments && segmentsLoaded > 0) {
              console.warn('🔧 Timeout atteint:', {
                segmentsLoaded,
                targetSegments,
                action: 'Lancement avec segments disponibles'
              });
              
              // Au lieu de forcer en boucle, accepter ce qu'on a et lancer
              console.log('🎯 Lancement anticipé avec', segmentsLoaded, 'segments sur', targetSegments, 'requis');
              
              // Marquer comme prêt
              setIsLoading(false);
              
              // Lancer la vidéo
              if (videoRef.current) {
                videoRef.current.play().catch(err => {
                  console.warn('Erreur lecture auto:', err);
                });
              }
              
              lastFragmentTime = Date.now(); // Reset pour éviter répétition
            }
          }, 5000);

          hls.on(Hls.Events.ERROR, (event: string, data: unknown) => {
            const eventData = data as { type?: string; details?: string; fatal?: boolean; url?: string };
            console.error('❌ HLS Error:', {
              type: eventData.type,
              details: eventData.details,
              fatal: eventData.fatal,
              url: eventData.url
            });
            
            // Gestion intelligente des erreurs de buffer plein
            if (eventData.details === 'bufferFullError') {
              console.log('🧹 Buffer plein détecté - stratégie conservation');
              
              // Ne pas purger si on a déjà atteint l'objectif
              if (segmentsLoaded >= targetSegments) {
                console.log('🎯 Objectif atteint, on ignore les nouveaux chargements');
                return; // Ignorer les erreurs si on a assez de segments
              }
              
              // Purge plus agressive uniquement si nécessaire
              purgeOldSegments();
              
              // Petite pause avant relance pour éviter boucle infinie
              setTimeout(() => {
                if (hlsRef.current && segmentsLoaded < targetSegments) {
                  console.log('🔄 Relance chargement après purge');
                  (hlsRef.current as HlsInstance).startLoad();
                }
              }, 1000); // 1 seconde de pause
              
              return; // Ne pas traiter comme erreur fatale
            }
            
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

          // Purge périodique pendant la lecture pour maintenir un cache léger
          video.addEventListener('timeupdate', () => {
            if (video.currentTime > 0) {
              const now = Date.now();
              const videoWithCache = video as HTMLVideoElement & { lastPurgeTime?: number };
              const lastPurge = videoWithCache.lastPurgeTime || 0;
              
              // Purger toutes les 10 secondes pendant la lecture
              if (now - lastPurge > 10000) {
                purgeOldSegments();
                videoWithCache.lastPurgeTime = now;
              }
            }
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
                  strokeDashoffset={226.19 - (226.19 * progress)}
                  className="transition-all duration-500 ease-out"
                />
              </svg>
              {/* Pourcentage au centre */}
              <div className="absolute inset-0 flex items-center justify-center">
                <span className="text-purple-300 font-semibold text-lg">
                  {Math.round(progress * 100)}%
                </span>
              </div>
            </div>
            
            {/* Étape de chargement */}
            <div className="text-center">
              <div className="text-purple-300 font-medium mb-1">🛰️ Préchargement vidéo</div>
              <div className="text-gray-400 text-sm">
                {segmentsLoaded}/{targetSegments} segments requis chargés
              </div>
              {canPlay && segmentsTotal > 0 && (
                <div className="text-green-400 mt-2">✅ Lecture possible !</div>
              )}
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
