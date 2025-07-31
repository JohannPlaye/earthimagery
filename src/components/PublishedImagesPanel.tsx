"use client";
import React, { useState } from 'react';
import { Accordion, AccordionSummary, AccordionDetails, Button, Typography, Link, List, ListItem, ListItemText, CircularProgress, Alert, Pagination, Box, Table, TableBody, TableCell, TableContainer, TableHead, TableRow, Paper } from '@mui/material';
// Essaie de décoder la date/heure à partir du nom de fichier (formats courants)
function parseImageDate(name: string): { date: Date|null, label: string } {
  // Format 1: YYYY-MM-DD[_T]HHMM (ex: 2024-07-31T1200 ou 2024-07-31_1200)
  const iso = name.match(/(20\d{2}-\d{2}-\d{2})[T_]?(\d{4})?/);
  if (iso) {
    const dateStr = iso[1];
    const timeStr = iso[2] || '0000';
    const year = parseInt(dateStr.slice(0,4));
    const month = parseInt(dateStr.slice(5,7))-1;
    const day = parseInt(dateStr.slice(8,10));
    const hour = parseInt(timeStr.slice(0,2));
    const min = parseInt(timeStr.slice(2,4));
    const date = new Date(Date.UTC(year, month, day, hour, min));
    return { date, label: `${year}-${(month+1).toString().padStart(2,'0')}-${day.toString().padStart(2,'0')} ${hour.toString().padStart(2,'0')}:${min.toString().padStart(2,'0')}` };
  }
  // Format 2: YYYYJJJHHMM (année, jour julien, heure, minute)
  const julian = name.match(/(20\d{2})(\d{3})(\d{2})(\d{2})/);
  if (julian) {
    const year = parseInt(julian[1]);
    const dayOfYear = parseInt(julian[2]);
    const hour = parseInt(julian[3]);
    const min = parseInt(julian[4]);
    // Convertir jour julien en mois/jour
    const date = new Date(Date.UTC(year, 0, dayOfYear, hour, min));
    const label = `${year}-${(date.getUTCMonth()+1).toString().padStart(2,'0')}-${date.getUTCDate().toString().padStart(2,'0')} ${hour.toString().padStart(2,'0')}:${min.toString().padStart(2,'0')}`;
    return { date, label };
  }
  // Format 3: YYYYMMDDHHMM (ex: 202407311200)
  const ymdhm = name.match(/(20\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/);
  if (ymdhm) {
    const year = parseInt(ymdhm[1]);
    const month = parseInt(ymdhm[2])-1;
    const day = parseInt(ymdhm[3]);
    const hour = parseInt(ymdhm[4]);
    const min = parseInt(ymdhm[5]);
    const date = new Date(Date.UTC(year, month, day, hour, min));
    const label = `${year}-${(month+1).toString().padStart(2,'0')}-${day.toString().padStart(2,'0')} ${hour.toString().padStart(2,'0')}:${min.toString().padStart(2,'0')}`;
    return { date, label };
  }
  // Format inconnu
  return { date: null, label: '-' };
}
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';

const IMAGES_PER_PAGE = 25;

interface PublishedImagesPanelProps {
  dataset: {
    satellite: string;
    sector: string;
    product: string;
    resolution: string;
    source?: string;
    label?: string;
  };
}


export default function PublishedImagesPanel({ dataset }: PublishedImagesPanelProps) {
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [images, setImages] = useState<Array<{ name: string; url: string }>>([]);
  const [sourceUrl, setSourceUrl] = useState<string | null>(null);
  const [page, setPage] = useState(1);

  const fetchImages = async () => {
    setLoading(true);
    setError(null);
    try {
      const params = new URLSearchParams({
        satellite: dataset.satellite,
        sector: dataset.sector,
        product: dataset.product,
        resolution: dataset.resolution,
        source: dataset.source || 'NOAA',
      });
      const resp = await fetch(`/api/datasets/images?${params.toString()}`);
      const data = await resp.json();
      if (!data.success) throw new Error(data.error || 'Erreur inconnue');
      setImages(data.images || []);
      setSourceUrl(data.source_url);
    } catch (err: any) {
      setError(err.message || 'Erreur lors du chargement');
    } finally {
      setLoading(false);
    }
  };

  const handleToggle = (_: any, expanded: boolean) => {
    setOpen(expanded);
    if (expanded && images.length === 0 && !loading) {
      fetchImages();
    }
  };


  // Décodage date/heure et tri du plus récent au plus ancien directement sur la liste reçue
  const imagesWithDate = images.map(img => {
    const { date, label } = parseImageDate(img.name);
    return { ...img, date, dateLabel: label };
  });
  imagesWithDate.sort((a, b) => {
    if (a.date && b.date) return b.date.getTime() - a.date.getTime();
    if (a.date) return -1;
    if (b.date) return 1;
    return 0;
  });
  const pageCount = Math.ceil(imagesWithDate.length / IMAGES_PER_PAGE);
  const pagedImages = imagesWithDate.slice((page - 1) * IMAGES_PER_PAGE, page * IMAGES_PER_PAGE);

  const handlePageChange = (_event: React.ChangeEvent<unknown>, value: number) => {
    setPage(value);
  };

  // Reset page to 1 when images change
  React.useEffect(() => {
    setPage(1);
  }, [images]);

  return (
    <Accordion expanded={open} onChange={handleToggle} sx={{ mb: 2 }}>
      <AccordionSummary expandIcon={<ExpandMoreIcon />}>
        <Typography fontWeight="bold">Images publiées {dataset.label ? `- ${dataset.label}` : ''}</Typography>
      </AccordionSummary>
      <AccordionDetails>
        {loading && <CircularProgress size={24} />}
        {error && <Alert severity="error">{error}</Alert>}
        {sourceUrl && (
          <Typography variant="body2" sx={{ mb: 1 }}>
            Source : <Link href={sourceUrl} target="_blank" rel="noopener">{sourceUrl}</Link>
          </Typography>
        )}
        {imagesWithDate.length > 0 && (
          <>
            <TableContainer component={Paper} sx={{ mb: 2 }}>
              <Table size="small">
                <TableHead>
                  <TableRow>
                    <TableCell>Nom</TableCell>
                    <TableCell>Date/Heure</TableCell>
                    <TableCell align="right">Téléchargement</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {pagedImages.map(img => (
                    <TableRow key={img.url}>
                      <TableCell>{img.name}</TableCell>
                      <TableCell>{img.dateLabel}</TableCell>
                      <TableCell align="right">
                        <Button href={img.url} target="_blank" rel="noopener" size="small" variant="outlined" download>
                          Télécharger
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
            {pageCount > 1 && (
              <Box display="flex" justifyContent="center" mt={2}>
                <Pagination
                  count={pageCount}
                  page={page}
                  onChange={handlePageChange}
                  size="small"
                  color="primary"
                  showFirstButton
                  showLastButton
                />
              </Box>
            )}
          </>
        )}
        {!loading && !error && images.length === 0 && (
          <Typography variant="body2" color="textSecondary">Aucune image trouvée.</Typography>
        )}
      </AccordionDetails>
    </Accordion>
  );
}
