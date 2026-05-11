import { useEffect, useState } from 'react';
import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  Chip,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Divider,
  Grid,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
} from '@mui/material';
import {
  DeleteOutline,
  DownloadOutlined,
  RefreshOutlined,
  VisibilityOutlined,
} from '@mui/icons-material';

import { api } from '@/api/axios.js';

export default function StoragePage() {
  const [runs, setRuns] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [detailLoading, setDetailLoading] = useState(false);
  const [selected, setSelected] = useState(null);
  const [detailPreviewMode, setDetailPreviewMode] = useState('overlay');

  const loadRuns = async () => {
    setLoading(true);
    setError('');
    try {
      const { data } = await api.get('/grain/runs', { params: { limit: 100 } });
      setRuns(data.data.items || []);
    } catch (err) {
      setError(err.response?.data?.message || 'Không tải được lịch sử phân tích');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadRuns();
  }, []);

  const openDetail = async (runId) => {
    setDetailLoading(true);
    setError('');
    try {
      const { data } = await api.get(`/grain/runs/${runId}`);
      setSelected(data.data);
      setDetailPreviewMode('overlay');
    } catch (err) {
      setError(err.response?.data?.message || 'Không tải được chi tiết xử lý');
    } finally {
      setDetailLoading(false);
    }
  };

  const deleteRun = async (run) => {
    const ok = window.confirm(`Xóa lần xử lý ${shortRunId(run.id)}?`);
    if (!ok) return;

    try {
      await api.delete(`/grain/runs/${run.id}`);
      setRuns((current) => current.filter((item) => item.id !== run.id));
      if (selected?.run?.id === run.id) setSelected(null);
    } catch (err) {
      setError(err.response?.data?.message || 'Xóa lần xử lý thất bại');
    }
  };

  const detailResult = selected?.result;
  const detailRun = selected?.run;
  const detailPreviewImages = {
    overlay: detailResult?.overlay_png_base64,
    clusters: detailResult?.cluster_png_base64,
    mask: detailResult?.mask_png_base64,
    seedMask: detailResult?.seed_mask_png_base64,
    kmeansMask: detailResult?.kmeans_mask_png_base64,
    labels: detailResult?.labels_png_base64,
  };
  const detailPreviewImage = detailPreviewImages[detailPreviewMode] || detailResult?.overlay_png_base64;

  return (
    <Box sx={{ maxWidth: 1200 }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 2, mb: 2.5, flexWrap: 'wrap' }}>
        <Box>
          <Typography variant="h5" fontWeight={700} mb={0.75}>Lưu trữ</Typography>
          <Typography variant="body2" color="text.secondary">
            Lịch sử được tạo trực tiếp từ pipeline phân tích ảnh: upload, worker Python, lưu run và export.
          </Typography>
        </Box>
        <Button variant="outlined" startIcon={<RefreshOutlined />} onClick={loadRuns} disabled={loading}>
          Làm mới
        </Button>
      </Box>

      {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}

      <Grid container spacing={2}>
        <Grid item xs={12}>
          <Card>
            <CardContent sx={{ p: 0 }}>
              <TableContainer>
                <Table>
                  <TableHead>
                    <TableRow>
                      <TableCell>Mã xử lý</TableCell>
                      <TableCell>Ảnh đầu vào</TableCell>
                      <TableCell>Thời gian</TableCell>
                      <TableCell align="right">Số hạt</TableCell>
                      <TableCell align="right">Dài TB</TableCell>
                      <TableCell align="right">Rộng TB</TableCell>
                      <TableCell>Trạng thái</TableCell>
                      <TableCell align="right">Thao tác</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {loading ? (
                      <TableRow>
                        <TableCell colSpan={8} align="center" sx={{ py: 5 }}>
                          <CircularProgress size={28} />
                        </TableCell>
                      </TableRow>
                    ) : runs.length ? runs.map((run) => (
                      <TableRow key={run.id} hover>
                        <TableCell>{shortRunId(run.id)}</TableCell>
                        <TableCell>
                          <Typography variant="body2" fontWeight={650}>{run.sourceFileName}</Typography>
                          <Typography variant="caption" color="text.secondary">
                            {run.image?.width || '-'} x {run.image?.height || '-'} px
                          </Typography>
                        </TableCell>
                        <TableCell>{formatDate(run.createdAt)}</TableCell>
                        <TableCell align="right">{run.summary?.count ?? 0}</TableCell>
                        <TableCell align="right">{formatMeasure(run.summary?.mean_length_mm, 'mm', run.summary?.mean_length_px, 'px')}</TableCell>
                        <TableCell align="right">{formatMeasure(run.summary?.mean_width_mm, 'mm', run.summary?.mean_width_px, 'px')}</TableCell>
                        <TableCell>
                          <Chip label="Hoàn tất" size="small" color="success" variant="outlined" />
                        </TableCell>
                        <TableCell align="right">
                          <Stack direction="row" spacing={0.5} justifyContent="flex-end">
                            <Button
                              size="small"
                              startIcon={<VisibilityOutlined />}
                              onClick={() => openDetail(run.id)}
                              disabled={detailLoading}
                            >
                              Xem
                            </Button>
                            <Button
                              size="small"
                              color="error"
                              startIcon={<DeleteOutline />}
                              onClick={() => deleteRun(run)}
                            >
                              Xóa
                            </Button>
                          </Stack>
                        </TableCell>
                      </TableRow>
                    )) : (
                      <TableRow>
                        <TableCell colSpan={8}>
                          <Alert severity="info" sx={{ m: 2 }}>
                            Chưa có lịch sử. Vào Trang chủ, import ảnh và chạy xử lý để tạo run đầu tiên.
                          </Alert>
                        </TableCell>
                      </TableRow>
                    )}
                  </TableBody>
                </Table>
              </TableContainer>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      <Dialog open={Boolean(selected)} onClose={() => setSelected(null)} maxWidth="md" fullWidth>
        <DialogTitle>Chi tiết xử lý {detailRun ? shortRunId(detailRun.id) : ''}</DialogTitle>
        <DialogContent dividers>
          {detailResult && (
            <Grid container spacing={2}>
              <Grid item xs={12} md={7}>
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
                      variant={detailPreviewMode === key ? 'contained' : 'outlined'}
                      disabled={!detailPreviewImages[key]}
                      onClick={() => setDetailPreviewMode(key)}
                    >
                      {label}
                    </Button>
                  ))}
                </Stack>
                <Box sx={{
                  border: '1px solid',
                  borderColor: 'divider',
                  borderRadius: 1,
                  bgcolor: '#FBFCFA',
                  minHeight: 320,
                  display: 'grid',
                  placeItems: 'center',
                  overflow: 'hidden',
                }}>
                  {detailPreviewImage ? (
                    <Box
                      component="img"
                      src={`data:image/png;base64,${detailPreviewImage}`}
                      alt={detailRun?.sourceFileName || 'overlay'}
                      sx={{ width: '100%', maxHeight: 420, objectFit: 'contain' }}
                    />
                  ) : (
                    <Typography variant="body2" color="text.secondary">Không có overlay</Typography>
                  )}
                </Box>
              </Grid>
              <Grid item xs={12} md={5}>
                <Stack spacing={1.2}>
                  <ResultRow label="Ảnh" value={detailRun?.sourceFileName || '-'} />
                  <ResultRow label="Thời gian" value={formatDate(detailRun?.createdAt)} />
                  <ResultRow label="Số hạt" value={detailResult.summary?.count ?? 0} />
                  <ResultRow label="Dài TB" value={formatMeasure(detailResult.summary?.mean_length_mm, 'mm', detailResult.summary?.mean_length_px, 'px')} />
                  <ResultRow label="Rộng TB" value={formatMeasure(detailResult.summary?.mean_width_mm, 'mm', detailResult.summary?.mean_width_px, 'px')} />
                  <ResultRow label="Tỷ lệ mm" value={detailResult.calibration?.enabled ? `${formatNumber(detailResult.calibration.mm_per_pixel, 5)} mm/px` : 'chưa có'} />
                  <ResultRow label="Markers" value={detailResult.segmentation?.marker_count ?? '-'} />
                  <ResultRow label="Segments trước lọc" value={detailResult.segmentation?.segment_count_before_filter ?? '-'} />
                  <Divider />
                  <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1}>
                    <Button
                      variant="contained"
                      startIcon={<DownloadOutlined />}
                      disabled={!detailResult.csv}
                      onClick={() => downloadBlob(`${safeStem(detailRun?.sourceFileName)}_measurements.csv`, detailResult.csv, 'text/csv;charset=utf-8')}
                    >
                      Export CSV
                    </Button>
                    <Button
                      variant="outlined"
                      startIcon={<DownloadOutlined />}
                      disabled={!detailResult.overlay_png_base64}
                      onClick={() => downloadPng(detailRun?.sourceFileName, detailResult.overlay_png_base64)}
                    >
                      Export PNG
                    </Button>
                  </Stack>
                </Stack>
              </Grid>
            </Grid>
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setSelected(null)}>Đóng</Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}

const ResultRow = ({ label, value }) => (
  <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 2 }}>
    <Typography variant="body2" color="text.secondary">{label}</Typography>
    <Typography variant="body2" fontWeight={650} textAlign="right">{value}</Typography>
  </Box>
);

const shortRunId = (id = '') => id ? `RUN-${id.slice(-8).toUpperCase()}` : 'RUN';

const formatDate = (value) => {
  if (!value) return '-';
  return new Intl.DateTimeFormat('vi-VN', {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(value));
};

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

const downloadBlob = (fileName, content, mimeType) => {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = fileName;
  link.click();
  URL.revokeObjectURL(url);
};

const downloadPng = (sourceName, base64) => {
  const link = document.createElement('a');
  link.href = `data:image/png;base64,${base64}`;
  link.download = `${safeStem(sourceName)}_segmentation.png`;
  link.click();
};
