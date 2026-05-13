import { useEffect, useRef, useState } from 'react';
import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  Chip,
  CircularProgress,
  Divider,
  Grid,
  Stack,
  TextField,
  Typography,
} from '@mui/material';

import { api, ensureFreshAccessToken } from '@/api/axios.js';

const StatCard = ({ label, value, note }) => (
  <Card sx={{ height: '100%' }}>
    <CardContent sx={{ p: 2.25 }}>
      <Box sx={{ mb: 1.25 }}>
        <Typography variant="body2" color="text.secondary">{label}</Typography>
      </Box>
      <Typography variant="h5" fontWeight={700}>{value}</Typography>
      <Typography variant="caption" color="text.secondary">{note}</Typography>
    </CardContent>
  </Card>
);

export default function DashboardPage() {
  const videoRef = useRef(null);
  const imageRef = useRef(null);
  const [cameraActive, setCameraActive] = useState(false);
  const [previewUrl, setPreviewUrl] = useState('');
  const [imageFile, setImageFile] = useState(null);
  const [fileName, setFileName] = useState('');
  const [cameraError, setCameraError] = useState('');
  const [processing, setProcessing] = useState(false);
  const [processError, setProcessError] = useState('');
  const [result, setResult] = useState(null);
  const [previewMode, setPreviewMode] = useState('overlay');
  const [calibration, setCalibration] = useState({ start: null, end: null, referenceMm: '' });
  const [drawingCalibration, setDrawingCalibration] = useState(false);

  useEffect(() => () => {
    if (videoRef.current?.srcObject) {
      videoRef.current.srcObject.getTracks().forEach((track) => track.stop());
    }
    if (previewUrl) URL.revokeObjectURL(previewUrl);
  }, [previewUrl]);

  const handleCamera = async () => {
    setCameraError('');
    setProcessError('');
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: true });
      if (videoRef.current) videoRef.current.srcObject = stream;
      if (previewUrl) URL.revokeObjectURL(previewUrl);
      setPreviewUrl('');
      setImageFile(null);
      setFileName('camera-frame.png');
      setResult(null);
      setCalibration({ start: null, end: null, referenceMm: '' });
      setCameraActive(true);
    } catch {
      setCameraError('Không thể kết nối camera. Kiểm tra quyền truy cập hoặc thiết bị.');
    }
  };

  const handleFile = (event) => {
    const file = event.target.files?.[0];
    if (!file) return;
    if (previewUrl) URL.revokeObjectURL(previewUrl);
    setPreviewUrl(URL.createObjectURL(file));
    setImageFile(file);
    setFileName(file.name);
    setCameraActive(false);
    setProcessError('');
    setResult(null);
    setPreviewMode('overlay');
    setCalibration({ start: null, end: null, referenceMm: '' });
  };

  const getCalibrationPoint = (event) => {
    const image = imageRef.current;
    if (!image?.naturalWidth || !image?.naturalHeight) return null;
    const rect = image.getBoundingClientRect();
    const x = Math.max(0, Math.min(rect.width, event.clientX - rect.left));
    const y = Math.max(0, Math.min(rect.height, event.clientY - rect.top));
    return {
      x: (x / Math.max(1, rect.width)) * image.naturalWidth,
      y: (y / Math.max(1, rect.height)) * image.naturalHeight,
    };
  };

  const calibrationPixels = calibration.start && calibration.end
    ? Math.hypot(calibration.end.x - calibration.start.x, calibration.end.y - calibration.start.y)
    : 0;
  const calibrationMm = Number(calibration.referenceMm);
  const calibrationReady = calibrationPixels > 1 && Number.isFinite(calibrationMm) && calibrationMm > 0;

  const renderCalibrationOverlay = () => {
    const image = imageRef.current;
    if (!image?.naturalWidth || !image?.naturalHeight || !calibration.start || !calibration.end) return null;
    const start = {
      x: (calibration.start.x / image.naturalWidth) * 100,
      y: (calibration.start.y / image.naturalHeight) * 100,
    };
    const end = {
      x: (calibration.end.x / image.naturalWidth) * 100,
      y: (calibration.end.y / image.naturalHeight) * 100,
    };
    return (
      <Box sx={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
        <svg width="100%" height="100%" viewBox="0 0 100 100" preserveAspectRatio="none">
          <line x1={start.x} y1={start.y} x2={end.x} y2={end.y} stroke="#1d4ed8" strokeWidth="0.8" vectorEffect="non-scaling-stroke" />
          <circle cx={start.x} cy={start.y} r="1.1" fill="#1d4ed8" />
          <circle cx={end.x} cy={end.y} r="1.1" fill="#1d4ed8" />
        </svg>
      </Box>
    );
  };

  const getImageForProcessing = async () => {
    if (imageFile) return imageFile;
    if (!cameraActive || !videoRef.current?.videoWidth) return null;

    const video = videoRef.current;
    const canvas = document.createElement('canvas');
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const context = canvas.getContext('2d');
    context.drawImage(video, 0, 0, canvas.width, canvas.height);

    return new Promise((resolve) => {
      canvas.toBlob((blob) => {
        if (!blob) resolve(null);
        resolve(new File([blob], 'camera-frame.png', { type: 'image/png' }));
      }, 'image/png');
    });
  };

  const handleProcess = async () => {
    setProcessing(true);
    setProcessError('');

    try {
      const file = await getImageForProcessing();
      if (!file) {
        setProcessError('Vui lòng import ảnh hoặc bật camera trước khi xử lý.');
        return;
      }

      await ensureFreshAccessToken(true);

      const formData = new FormData();
      formData.append('image', file);
      if (calibrationReady) {
        formData.append('referencePixels', String(calibrationPixels));
        formData.append('referenceMm', String(calibrationMm));
        formData.append('referencePixelSpace', 'original');
        formData.append('referenceX1', String(calibration.start.x));
        formData.append('referenceY1', String(calibration.start.y));
        formData.append('referenceX2', String(calibration.end.x));
        formData.append('referenceY2', String(calibration.end.y));
      }

      const { data } = await api.post('/grain/analyze', formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      setResult(data.data);
    } catch (err) {
      setProcessError(resolveProcessError(err));
    } finally {
      setProcessing(false);
    }
  };

  const downloadCsv = () => {
    if (!result?.csv) return;
    downloadBlob(`${safeStem(fileName)}_measurements.csv`, result.csv, 'text/csv;charset=utf-8');
  };

  const downloadPng = () => {
    if (!result?.overlay_png_base64) return;
    const link = document.createElement('a');
    link.href = `data:image/png;base64,${result.overlay_png_base64}`;
    link.download = `${safeStem(fileName)}_segmentation.png`;
    link.click();
  };

  const summary = result?.summary;
  const previewImages = {
    overlay: result?.overlay_png_base64,
    clusters: result?.cluster_png_base64,
    mask: result?.mask_png_base64,
    seedMask: result?.seed_mask_png_base64,
    kmeansMask: result?.kmeans_mask_png_base64,
    labels: result?.labels_png_base64,
  };
  const activePreview = previewImages[previewMode] || result?.overlay_png_base64;
  const displayImage = activePreview ? `data:image/png;base64,${activePreview}` : previewUrl;
  const calibrationImage = previewUrl && !activePreview;

  const stats = [
    {
      label: 'Số hạt đo được',
      value: summary ? String(summary.count) : '0',
      note: result ? 'Theo lần xử lý hiện tại' : 'Chưa có kết quả',
    },
    {
      label: 'Diện tích TB',
      value: summary ? formatMeasure(summary.mean_area_mm2, 'mm²', summary.mean_area_px, 'px') : '-',
      note: 'Từ contour từng hạt',
    },
    {
      label: 'Chiều dài TB',
      value: summary ? formatMeasure(summary.mean_length_mm, 'mm', summary.mean_length_px, 'px') : '-',
      note: 'Theo trục ellipse chính',
    },
    {
      label: 'Chiều rộng TB',
      value: summary ? formatMeasure(summary.mean_width_mm, 'mm', summary.mean_width_px, 'px') : '-',
      note: 'Theo trục ellipse phụ',
    },
  ];

  return (
    <Box sx={{ maxWidth: 1280 }}>
      <Grid container spacing={2} mb={3}>
        {stats.map((item) => (
          <Grid item xs={12} sm={6} lg={3} key={item.label}>
            <StatCard {...item} />
          </Grid>
        ))}
      </Grid>

      <Grid container spacing={2}>
        <Grid item xs={12} lg={7}>
          <Card sx={{ height: '100%' }}>
            <CardContent sx={{ p: 2.5 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 2, mb: 2 }}>
                <Box>
                  <Typography variant="h6" fontWeight={700}>Ảnh đầu vào và overlay</Typography>
                  <Typography variant="body2" color="text.secondary">
                    Sau khi xử lý, vùng này hiển thị contour và ID từng hạt.
                  </Typography>
                </Box>
                <Chip
                  label={result ? 'Đã xử lý' : 'Sẵn sàng'}
                  color={result ? 'primary' : 'success'}
                  variant="outlined"
                  size="small"
                />
              </Box>

              {result && (
                <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1} sx={{ mb: 1.5 }}>
                  {[
                    ['overlay', 'Overlay'],
                    ['clusters', 'Clusters'],
                    ['mask', 'Mask'],
                    ['seedMask', 'Seed mask'],
                    ['kmeansMask', 'KMeans mask'],
                    ['labels', 'Labels'],
                  ].map(([key, label]) => (
                    <Button
                      key={key}
                      size="small"
                      variant={previewMode === key ? 'contained' : 'outlined'}
                      onClick={() => setPreviewMode(key)}
                    >
                      {label}
                    </Button>
                  ))}
                </Stack>
              )}

              <Box sx={{
                minHeight: 360,
                border: '1px dashed',
                borderColor: 'divider',
                borderRadius: 1,
                bgcolor: '#FBFCFA',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                overflow: 'hidden',
                mb: 2,
                position: 'relative',
              }}>
                {displayImage ? (
                  <Box
                    sx={{ position: 'relative', width: '100%', height: 360, display: 'grid', placeItems: 'center', touchAction: calibrationImage ? 'none' : 'auto' }}
                    onPointerDown={(event) => {
                      if (!calibrationImage || processing) return;
                      const point = getCalibrationPoint(event);
                      if (!point) return;
                      setDrawingCalibration(true);
                      setCalibration((current) => ({ ...current, start: point, end: point }));
                    }}
                    onPointerMove={(event) => {
                      if (!drawingCalibration) return;
                      const point = getCalibrationPoint(event);
                      if (point) setCalibration((current) => ({ ...current, end: point }));
                    }}
                    onPointerUp={() => setDrawingCalibration(false)}
                    onPointerLeave={() => setDrawingCalibration(false)}
                  >
                    <Box component="span" sx={{ position: 'relative', display: 'inline-flex', maxWidth: '100%', maxHeight: 360 }}>
                      <Box
                        component="img"
                        ref={imageRef}
                        src={displayImage}
                        alt={fileName}
                        draggable={false}
                        sx={{ maxWidth: '100%', maxHeight: 360, objectFit: 'contain', userSelect: 'none' }}
                      />
                      {calibrationImage && renderCalibrationOverlay()}
                    </Box>
                  </Box>
                ) : (
                  <video ref={videoRef} autoPlay muted playsInline style={{ width: '100%', maxHeight: 360, display: cameraActive ? 'block' : 'none' }} />
                )}
                {!displayImage && !cameraActive && (
                  <Stack alignItems="center" spacing={1.25} sx={{ color: 'text.secondary', textAlign: 'center', px: 2 }}>
                    <Typography fontWeight={650} color="text.primary">Chưa có ảnh đầu vào</Typography>
                  </Stack>
                )}
                {processing && (
                  <Box sx={{
                    position: 'absolute',
                    inset: 0,
                    bgcolor: 'rgba(255,255,255,0.72)',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                  }}>
                    <Stack alignItems="center" spacing={1}>
                      <CircularProgress size={32} />
                      <Typography variant="body2" fontWeight={650}>Đang xử lý...</Typography>
                    </Stack>
                  </Box>
                )}
              </Box>

              {fileName && (
                <Typography variant="caption" color="text.secondary" display="block" mb={1.5}>{fileName}</Typography>
              )}
              {previewUrl && (
                <Box sx={{ mb: 1.5 }}>
                  <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1} alignItems={{ xs: 'stretch', sm: 'center' }}>
                    <TextField
                      label="Kích thước vật mốc (mm)"
                      type="number"
                      size="small"
                      value={calibration.referenceMm}
                      onChange={(event) => setCalibration((current) => ({ ...current, referenceMm: event.target.value }))}
                      inputProps={{ min: 0, step: 0.01 }}
                      sx={{ maxWidth: { sm: 220 } }}
                    />
                    <Chip
                      size="small"
                      color={calibrationReady ? 'primary' : 'default'}
                      variant="outlined"
                      label={calibrationPixels > 1 ? `${calibrationPixels.toFixed(1)} px` : 'Kéo 1 đoạn trên vật mốc'}
                    />
                    <Button
                      size="small"
                      variant="text"
                      onClick={() => setCalibration({ start: null, end: null, referenceMm: '' })}
                    >
                      Xóa vật mốc
                    </Button>
                  </Stack>
                </Box>
              )}
              {cameraError && <Alert severity="error" sx={{ mb: 1.5 }}>{cameraError}</Alert>}
              {processError && <Alert severity="error" sx={{ mb: 1.5 }}>{processError}</Alert>}

              <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1}>
                <Button variant="contained" onClick={handleCamera}>
                  Kết nối camera
                </Button>
                <Button variant="outlined" component="label">
                  Import ảnh
                  <input hidden type="file" accept="image/jpeg,image/png" onChange={handleFile} />
                </Button>
                <Button
                  variant="outlined"
                  disabled={processing || (!imageFile && !cameraActive)}
                  onClick={handleProcess}
                >
                  {processing ? 'Đang xử lý...' : (result ? 'Chạy lại' : 'Chạy xử lý')}
                </Button>
              </Stack>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} lg={5}>
          <Stack spacing={2}>
            <Card>
              <CardContent sx={{ p: 2.5 }}>
                <Typography variant="h6" fontWeight={700} mb={0.5}>Cài đặt đo lường</Typography>
                <Box mb={2} />

                <Stack spacing={1.25}>
                  <ResultRow label="Nhận dạng" value="Tự động" />
                  <ResultRow label="Đơn vị" value={calibrationReady ? 'mm' : 'px'} />
                  <ResultRow
                    label="Vật mốc"
                    value={calibrationReady ? `${calibrationPixels.toFixed(1)} px = ${calibrationMm} mm` : 'Chưa chọn'}
                  />
                </Stack>
              </CardContent>
            </Card>

            <Card>
              <CardContent sx={{ p: 2.5 }}>
                <Typography variant="h6" fontWeight={700} mb={0.5}>Kết quả và export</Typography>
                <Box mb={2} />

                {result ? (
                  <Stack spacing={1.2}>
                    <ResultRow
                      label="Tỷ lệ mm"
                      value={result.calibration?.enabled ? `${formatNumber(result.calibration.mm_per_pixel, 5)} mm/px` : 'chưa có'}
                    />
                    <ResultRow
                      label="Dài TB thật"
                      value={result.calibration?.enabled ? `${formatNumber(result.summary?.mean_length_mm, 3)} mm` : '-'}
                    />
                    <ResultRow
                      label="Rộng TB thật"
                      value={result.calibration?.enabled ? `${formatNumber(result.summary?.mean_width_mm, 3)} mm` : '-'}
                    />
                    <ResultRow label="Mã xử lý" value={result.run?.id ? result.run.id.slice(-8).toUpperCase() : '-'} />
                    <ResultRow label="Segments trước lọc" value={result.segmentation.segment_count_before_filter} />
                    <ResultRow label="Watershed markers" value={result.segmentation.marker_count} />
                    <ResultRow
                      label="Edge snap"
                      value={result.segmentation.edge_snap?.enabled ? `${result.segmentation.edge_snap.input_segments} -> ${result.segmentation.edge_snap.output_segments}` : 'off'}
                    />
                    <ResultRow
                      label="Fill holes"
                      value={result.segmentation.label_fill?.enabled ? `${result.segmentation.label_fill.filled_pixels} px` : 'off'}
                    />
                    <ResultRow label="Mask pixels raw" value={result.segmentation.raw_mask_pixels ?? result.segmentation.mask_pixels} />
                    <ResultRow label="Mask pixels" value={result.segmentation.mask_pixels} />
                    <ResultRow
                      label="Mask components"
                      value={`${result.segmentation.mask_filter?.component_count_before ?? '-'} -> ${result.segmentation.mask_filter?.component_count_after ?? '-'}`}
                    />
                    <ResultRow
                      label="Auto candidates"
                      value={result.segmentation.dynamic_thresholds?.candidate_count ?? '-'}
                    />
                    <ResultRow
                      label="Effective area"
                      value={`${result.segmentation.effective_thresholds?.minArea ?? '-'} -> ${result.segmentation.effective_thresholds?.maxArea ?? '-'}`}
                    />
                    <ResultRow label="PCA variance PC" value={`${(result.features.pca_explained_variance[result.features.pc_index] * 100).toFixed(1)}%`} />
                    <Divider />
                    <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1}>
                      <Button variant="contained" onClick={downloadCsv}>
                        Export CSV
                      </Button>
                      <Button variant="outlined" onClick={downloadPng}>
                        Export PNG
                      </Button>
                    </Stack>
                  </Stack>
                ) : (
                  <Alert severity="info">Chưa có kết quả. Import ảnh và bấm Chạy xử lý.</Alert>
                )}
              </CardContent>
            </Card>
          </Stack>
        </Grid>
      </Grid>
    </Box>
  );
}

const ResultRow = ({ label, value }) => (
  <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 2 }}>
    <Typography variant="body2" color="text.secondary">{label}</Typography>
    <Typography variant="body2" fontWeight={650}>{value}</Typography>
  </Box>
);

const formatNumber = (value, digits = 2) => (
  Number.isFinite(Number(value)) ? Number(value).toFixed(digits) : '-'
);

const formatMeasure = (primary, primaryUnit, fallback, fallbackUnit) => (
  Number.isFinite(Number(primary))
    ? `${formatNumber(primary, primaryUnit === 'mm²' ? 3 : 2)} ${primaryUnit}`
    : `${formatNumber(fallback)} ${fallbackUnit}`
);

const safeStem = (name = 'seed-image') => (
  name.replace(/\.[^.]+$/, '').replace(/[^a-z0-9_-]+/gi, '_') || 'seed-image'
);

const resolveProcessError = (err) => {
  if (err.response?.status === 401) {
    return 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại rồi chạy xử lý.';
  }

  const message = err.response?.data?.message;
  if (message) return message;
  if (err.response?.status === 503 || (err.response?.status === 500 && typeof err.response?.data === 'string')) {
    return 'Backend API chưa chạy hoặc Vite không proxy được tới http://localhost:3000. Hãy chạy backend rồi thử lại.';
  }
  if (err.code === 'ERR_NETWORK') {
    return 'Không kết nối được backend. Kiểm tra server backend và kết nối mạng nội bộ.';
  }
  return 'Xử lý ảnh thất bại. Kiểm tra backend, MongoDB và Python dependencies.';
};

const downloadBlob = (fileName, content, mimeType) => {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = fileName;
  link.click();
  URL.revokeObjectURL(url);
};
