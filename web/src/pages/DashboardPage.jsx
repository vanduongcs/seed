import { useEffect, useRef, useState } from 'react';
import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  Checkbox,
  Chip,
  CircularProgress,
  Divider,
  FormControlLabel,
  FormGroup,
  Grid,
  Slider,
  Stack,
  TextField,
  Typography,
  alpha,
} from '@mui/material';
import {
  CameraAltOutlined,
  DownloadOutlined,
  GrainOutlined,
  ImageSearchOutlined,
  Straighten,
  UploadFileOutlined,
} from '@mui/icons-material';

import { api } from '@/api/axios.js';

const initialControls = {
  maxSide: 2000,
  pcIndex: 0,
  k: 5,
  rgbIndexWeight: 0.65,
  minArea: 60,
  maxArea: 2500,
  minLength: 3,
  maxLength: 160,
  splitSensitivity: 8,
  openingRadius: 1,
  closingRadius: 1,
  noiseSize: 45,
  holeSize: 64,
  seednessThreshold: 0.32,
  maskMinArea: 50,
  maxSegmentAspectRatio: 10.5,
  minSegmentSolidity: 0.52,
  minSegmentExtent: 0.18,
  dynamicThresholds: true,
  markerShrinkFactor: 0.5,
};

const clusterPalette = [
  '#2d6cbf',
  '#db5756',
  '#49a078',
  '#ebae49',
  '#8462ae',
  '#4db0c4',
  '#c970a5',
  '#7a7e87',
  '#6d8f31',
  '#b26b2d',
];

const StatCard = ({ label, value, note, icon }) => (
  <Card sx={{ height: '100%' }}>
    <CardContent sx={{ p: 2.25 }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 2, mb: 1.25 }}>
        <Typography variant="body2" color="text.secondary">{label}</Typography>
        <Box sx={{
          width: 32,
          height: 32,
          borderRadius: 1,
          bgcolor: (t) => alpha(t.palette.primary.main, 0.09),
          color: 'primary.main',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          flexShrink: 0,
        }}>
          {icon}
        </Box>
      </Box>
      <Typography variant="h5" fontWeight={700}>{value}</Typography>
      <Typography variant="caption" color="text.secondary">{note}</Typography>
    </CardContent>
  </Card>
);

const NumberControl = ({ label, value, min, max, step = 1, onChange }) => (
  <TextField
    label={label}
    type="number"
    size="small"
    value={value}
    onChange={(event) => {
      const next = Number(event.target.value);
      if (Number.isFinite(next)) onChange(Math.max(min, Math.min(max, next)));
    }}
    inputProps={{ min, max, step }}
    fullWidth
  />
);

export default function DashboardPage() {
  const videoRef = useRef(null);
  const [cameraActive, setCameraActive] = useState(false);
  const [previewUrl, setPreviewUrl] = useState('');
  const [imageFile, setImageFile] = useState(null);
  const [fileName, setFileName] = useState('');
  const [cameraError, setCameraError] = useState('');
  const [processing, setProcessing] = useState(false);
  const [processError, setProcessError] = useState('');
  const [result, setResult] = useState(null);
  const [controls, setControls] = useState(initialControls);
  const [selectedClusters, setSelectedClusters] = useState([]);
  const [previewMode, setPreviewMode] = useState('overlay');

  useEffect(() => () => {
    if (videoRef.current?.srcObject) {
      videoRef.current.srcObject.getTracks().forEach((track) => track.stop());
    }
    if (previewUrl) URL.revokeObjectURL(previewUrl);
  }, [previewUrl]);

  const updateControl = (key, value) => {
    setControls((current) => ({ ...current, [key]: value }));
  };

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
    setSelectedClusters([]);
    setPreviewMode('overlay');
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

      await api.get('/grain/health');

      const formData = new FormData();
      formData.append('image', file);
      Object.entries(controls).forEach(([key, value]) => formData.append(key, String(value)));
      formData.append('clusterSpace', 'pca3');
      formData.append('pcaMethod', 'correlation');
      formData.append('watershedMode', 'dense');
      formData.append('maskSource', selectedClusters.length ? 'hybrid' : 'auto');
      if (selectedClusters.length) formData.append('selectedClusters', selectedClusters.join(','));

      const { data } = await api.post('/grain/analyze', formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      setResult(data.data);
      if (!selectedClusters.length && data.data?.kmeans?.selected_clusters) {
        setSelectedClusters(data.data.kmeans.selected_clusters);
      }
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

  const stats = [
    {
      label: 'Số hạt đo được',
      value: summary ? String(summary.count) : '0',
      note: result ? 'Theo lần xử lý hiện tại' : 'Chưa có kết quả',
      icon: <GrainOutlined />,
    },
    {
      label: 'Diện tích TB',
      value: summary ? `${summary.mean_area_px} px` : '-',
      note: 'Từ contour từng hạt',
      icon: <ImageSearchOutlined />,
    },
    {
      label: 'Chiều dài TB',
      value: summary ? `${summary.mean_length_px} px` : '-',
      note: 'Theo trục ellipse chính',
      icon: <Straighten />,
    },
    {
      label: 'Chiều rộng TB',
      value: summary ? `${summary.mean_width_px} px` : '-',
      note: 'Theo trục ellipse phụ',
      icon: <Straighten />,
    },
  ];

  return (
    <Box sx={{ maxWidth: 1280 }}>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" fontWeight={700} mb={0.75}>Phân tích ảnh hạt giống</Typography>
        <Typography variant="body2" color="text.secondary">
          Upload một ảnh, backend sẽ chạy PCA, KMeans, watershed và đo area/length/width để xuất CSV.
        </Typography>
      </Box>

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
                  <Box component="img" src={displayImage} alt={fileName} sx={{ width: '100%', height: 360, objectFit: 'contain' }} />
                ) : (
                  <video ref={videoRef} autoPlay muted playsInline style={{ width: '100%', maxHeight: 360, display: cameraActive ? 'block' : 'none' }} />
                )}
                {!displayImage && !cameraActive && (
                  <Stack alignItems="center" spacing={1.25} sx={{ color: 'text.secondary', textAlign: 'center', px: 2 }}>
                    <ImageSearchOutlined sx={{ fontSize: 46, color: 'primary.main' }} />
                    <Typography fontWeight={650} color="text.primary">Chưa có ảnh đầu vào</Typography>
                    <Typography variant="body2">Import file ảnh hạt giống để bắt đầu xử lý.</Typography>
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
                      <Typography variant="body2" fontWeight={650}>Đang chạy PCA + KMeans + watershed...</Typography>
                    </Stack>
                  </Box>
                )}
              </Box>

              {fileName && (
                <Typography variant="caption" color="text.secondary" display="block" mb={1.5}>{fileName}</Typography>
              )}
              {cameraError && <Alert severity="error" sx={{ mb: 1.5 }}>{cameraError}</Alert>}
              {processError && <Alert severity="error" sx={{ mb: 1.5 }}>{processError}</Alert>}

              <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1}>
                <Button variant="contained" startIcon={<CameraAltOutlined />} onClick={handleCamera}>
                  Kết nối camera
                </Button>
                <Button variant="outlined" component="label" startIcon={<UploadFileOutlined />}>
                  Import ảnh
                  <input hidden type="file" accept="image/jpeg,image/png" onChange={handleFile} />
                </Button>
                <Button
                  variant="outlined"
                  startIcon={<ImageSearchOutlined />}
                  disabled={processing || (!imageFile && !cameraActive)}
                  onClick={handleProcess}
                >
                  {result ? 'Chạy lại' : 'Chạy xử lý'}
                </Button>
              </Stack>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} lg={5}>
          <Stack spacing={2}>
            <Card>
              <CardContent sx={{ p: 2.5 }}>
                <Typography variant="h6" fontWeight={700} mb={0.5}>Tham số xử lý</Typography>
                <Typography variant="body2" color="text.secondary" mb={2}>
                  Điều chỉnh các ngưỡng này rồi bấm chạy lại để refine segmentation.
                </Typography>

                {result?.kmeans && (
                  <Box sx={{ mb: 2 }}>
                    <Typography variant="body2" fontWeight={650} mb={0.75}>Chọn cluster là hạt</Typography>
                    <Typography variant="caption" color="text.secondary" display="block" mb={1}>
                      Mặc định dùng seed-color mask. Tick cluster để giới hạn thêm khi ảnh có nhiều vật màu vàng-nâu không phải hạt.
                    </Typography>
                    <FormGroup sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 0.25 }}>
                      {Array.from({ length: result.kmeans.k }, (_, index) => {
                        const checked = selectedClusters.includes(index);
                        const count = result.kmeans.counts?.[index] || 0;
                        const ratio = count / Math.max(1, result.image.width * result.image.height);
                        return (
                          <FormControlLabel
                            key={index}
                            control={(
                              <Checkbox
                                checked={checked}
                                onChange={(event) => {
                                  setSelectedClusters((current) => (
                                    event.target.checked
                                      ? [...new Set([...current, index])].sort((a, b) => a - b)
                                      : current.filter((item) => item !== index)
                                  ));
                                }}
                                size="small"
                              />
                            )}
                            label={(
                              <Box component="span" sx={{ display: 'inline-flex', alignItems: 'center', gap: 0.75 }}>
                                <Box
                                  component="span"
                                  sx={{
                                    width: 12,
                                    height: 12,
                                    borderRadius: 0.5,
                                    bgcolor: clusterPalette[index % clusterPalette.length],
                                    border: '1px solid rgba(0,0,0,0.2)',
                                  }}
                                />
                                {`C${index + 1} (${(ratio * 100).toFixed(1)}%)`}
                              </Box>
                            )}
                          />
                        );
                      })}
                    </FormGroup>
                    <Button
                      size="small"
                      variant="text"
                      onClick={() => setSelectedClusters(result.kmeans.selected_clusters || [])}
                      sx={{ mt: 0.5 }}
                    >
                      Khôi phục gợi ý auto
                    </Button>
                  </Box>
                )}

                <Grid container spacing={1.5}>
                  <Grid item xs={6}>
                    <NumberControl label="PC index" value={controls.pcIndex} min={0} max={2} onChange={(value) => updateControl('pcIndex', value)} />
                  </Grid>
                  <Grid item xs={6}>
                    <NumberControl label="KMeans K" value={controls.k} min={1} max={10} onChange={(value) => updateControl('k', value)} />
                  </Grid>
                  <Grid item xs={6}>
                    <NumberControl label="min_area" value={controls.minArea} min={0} max={1000000} onChange={(value) => updateControl('minArea', value)} />
                  </Grid>
                  <Grid item xs={6}>
                    <NumberControl label="max_area" value={controls.maxArea} min={1} max={10000000} onChange={(value) => updateControl('maxArea', value)} />
                  </Grid>
                  <Grid item xs={6}>
                    <NumberControl label="min_length" value={controls.minLength} min={0} max={100000} onChange={(value) => updateControl('minLength', value)} />
                  </Grid>
                  <Grid item xs={6}>
                    <NumberControl label="max_length" value={controls.maxLength} min={1} max={100000} onChange={(value) => updateControl('maxLength', value)} />
                  </Grid>
                </Grid>

                <Box sx={{ mt: 2 }}>
                  <Typography variant="body2" color="text.secondary" gutterBottom>
                    RGB/index PCA weight: {controls.rgbIndexWeight.toFixed(2)}
                  </Typography>
                  <Slider
                    value={controls.rgbIndexWeight}
                    min={0}
                    max={1}
                    step={0.02}
                    onChange={(_, value) => updateControl('rgbIndexWeight', value)}
                  />
                </Box>

                <Box sx={{ mt: 2 }}>
                  <Typography variant="body2" color="text.secondary" gutterBottom>
                    seed mask threshold: {controls.seednessThreshold.toFixed(2)}
                  </Typography>
                  <Slider
                    value={controls.seednessThreshold}
                    min={0.05}
                    max={0.75}
                    step={0.01}
                    onChange={(_, value) => updateControl('seednessThreshold', value)}
                  />
                </Box>

                <Box sx={{ mt: 2 }}>
                  <Typography variant="body2" color="text.secondary" gutterBottom>
                    split sensitivity: {controls.splitSensitivity}
                  </Typography>
                  <Slider
                    value={controls.splitSensitivity}
                    min={1}
                    max={10}
                    step={1}
                    marks
                    onChange={(_, value) => updateControl('splitSensitivity', value)}
                  />
                </Box>

                <Divider sx={{ my: 2 }} />
                <FormControlLabel
                  control={(
                    <Checkbox
                      checked={controls.dynamicThresholds}
                      onChange={(event) => updateControl('dynamicThresholds', event.target.checked)}
                      size="small"
                    />
                  )}
                  label="auto thresholds"
                  sx={{ mb: 1 }}
                />
                <Grid container spacing={1.5}>
                  <Grid item xs={6}>
                    <NumberControl label="opening" value={controls.openingRadius} min={0} max={8} onChange={(value) => updateControl('openingRadius', value)} />
                  </Grid>
                  <Grid item xs={6}>
                    <NumberControl label="closing" value={controls.closingRadius} min={0} max={10} onChange={(value) => updateControl('closingRadius', value)} />
                  </Grid>
                  <Grid item xs={6}>
                    <NumberControl label="noise size" value={controls.noiseSize} min={1} max={50000} onChange={(value) => updateControl('noiseSize', value)} />
                  </Grid>
                  <Grid item xs={6}>
                    <NumberControl label="hole size" value={controls.holeSize} min={1} max={50000} onChange={(value) => updateControl('holeSize', value)} />
                  </Grid>
                  <Grid item xs={6}>
                    <NumberControl label="mask_min_area" value={controls.maskMinArea} min={1} max={1000000} onChange={(value) => updateControl('maskMinArea', value)} />
                  </Grid>
                  <Grid item xs={6}>
                    <NumberControl label="max_aspect" value={controls.maxSegmentAspectRatio} min={1.2} max={50} step={0.1} onChange={(value) => updateControl('maxSegmentAspectRatio', value)} />
                  </Grid>
                  <Grid item xs={6}>
                    <NumberControl label="min_solidity" value={controls.minSegmentSolidity} min={0} max={0.99} step={0.01} onChange={(value) => updateControl('minSegmentSolidity', value)} />
                  </Grid>
                  <Grid item xs={6}>
                    <NumberControl label="min_extent" value={controls.minSegmentExtent} min={0} max={0.99} step={0.01} onChange={(value) => updateControl('minSegmentExtent', value)} />
                  </Grid>
                  <Grid item xs={6}>
                    <NumberControl label="marker_shrink" value={controls.markerShrinkFactor} min={0.15} max={1} step={0.05} onChange={(value) => updateControl('markerShrinkFactor', value)} />
                  </Grid>
                </Grid>
              </CardContent>
            </Card>

            <Card>
              <CardContent sx={{ p: 2.5 }}>
                <Typography variant="h6" fontWeight={700} mb={0.5}>Kết quả và export</Typography>
                <Typography variant="body2" color="text.secondary" mb={2}>
                  API trả measurements, CSV và ảnh overlay cho web/mobile dùng chung.
                </Typography>

                {result ? (
                  <Stack spacing={1.2}>
                    <ResultRow label="Segments trước lọc" value={result.segmentation.segment_count_before_filter} />
                    <ResultRow label="Watershed markers" value={result.segmentation.marker_count} />
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
                      <Button variant="contained" startIcon={<DownloadOutlined />} onClick={downloadCsv}>
                        Export CSV
                      </Button>
                      <Button variant="outlined" startIcon={<DownloadOutlined />} onClick={downloadPng}>
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

const safeStem = (name = 'seed-image') => (
  name.replace(/\.[^.]+$/, '').replace(/[^a-z0-9_-]+/gi, '_') || 'seed-image'
);

const resolveProcessError = (err) => {
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
