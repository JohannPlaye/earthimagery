'use client';

import { useEffect, useRef, useState, useMemo } from 'react';

interface VideoPlayerProps {
  fromDate: Date;
  toDate: Date;
}

export default function VideoPlayer({ fromDate, toDate }: VideoPlayerProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const hlsRef = useRef<any>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [mounted, setMounted] = useState(false);

  const formattedFromDate = useMemo(() => fromDate.toISOString().split('T')[0], [fromDate]);
  const formattedToDate = useMemo(() => toDate.toISOString().split('T')[0], [toDate]);

  // Reset states when dates change
  useEffect(() => {
    setIsLoading(true);
    setError(null);
  }, [formattedFromDate, formattedToDate]);

  useEffect(() => {
    setMounted(true);
    return () => setMounted(false);
  }, []);

  useEffect(() => {
    if (!mounted || !videoRef.current) return;

    const video = videoRef.current;
    const playlistUrl = `/api/playlist?from=${formattedFromDate}&to=${formattedToDate}`;

    console.log('🎯 Initializing HLS with:', playlistUrl);

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
            hlsRef.current.destroy();
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
          hls.on(Hls.Events.MANIFEST_PARSED, (event: any, data: any) => {
            console.log('✅ Manifest parsed successfully:', {
              levels: data.levels?.length || 0,
              duration: data.totalduration
            });
            setIsLoading(false);
          });

          hls.on(Hls.Events.LEVEL_LOADED, (event: any, data: any) => {
            console.log('✅ Level loaded:', {
              level: data.level,
              fragments: data.details?.fragments?.length || 0,
              duration: data.details?.totalduration || 0
            });
          });

          hls.on(Hls.Events.FRAG_LOADED, (event: any, data: any) => {
            console.log('✅ Fragment loaded:', {
              url: data.frag?.url,
              duration: data.frag?.duration
            });
          });

          hls.on(Hls.Events.ERROR, (event: any, data: any) => {
            console.error('❌ HLS Error:', {
              type: data.type,
              details: data.details,
              fatal: data.fatal,
              url: data.url
            });
            
            if (data.fatal) {
              switch (data.type) {
                case Hls.ErrorTypes.NETWORK_ERROR:
                  console.log('🔄 Fatal network error, trying to recover...');
                  // Check if it's a 404 or empty playlist
                  if (data.details === Hls.ErrorDetails.MANIFEST_LOAD_ERROR) {
                    setError(`Aucune vidéo disponible pour la période du ${fromDate.toLocaleDateString('fr-FR')} au ${toDate.toLocaleDateString('fr-FR')}`);
                    setIsLoading(false);
                    return;
                  }
                  setTimeout(() => {
                    if (hlsRef.current) {
                      hlsRef.current.startLoad();
                    }
                  }, 2000);
                  break;
                case Hls.ErrorTypes.MEDIA_ERROR:
                  console.log('🔄 Fatal media error, trying to recover...');
                  setTimeout(() => {
                    if (hlsRef.current) {
                      hlsRef.current.recoverMediaError();
                    }
                  }, 2000);
                  break;
                default:
                  setError(`Erreur de lecture: ${data.details}`);
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
        hlsRef.current.destroy();
        hlsRef.current = null;
      }
    };
  }, [formattedFromDate, formattedToDate, mounted, fromDate, toDate]);

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
    <div className="w-full relative">
      <video
        ref={videoRef}
        controls
        className="w-full h-96 bg-black rounded-lg"
        poster="/placeholder-satellite.jpg"
        muted
        playsInline
      >
        Votre navigateur ne supporte pas la lecture vidéo.
      </video>
      {isLoading && (
        <div className="absolute inset-0 flex items-center justify-center bg-black bg-opacity-50 rounded-lg">
          <div className="text-white">Chargement de la vidéo...</div>
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
