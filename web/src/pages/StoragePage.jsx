import { useEffect, useState } from 'react';
import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  Chip,
  CircularProgress,
  Collapse,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Divider,
  Grid,
  IconButton,
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
  ExpandLess,
  ExpandMore,
  RefreshOutlined,
  VisibilityOutlined,
} from '@mui/icons-material';

import { api } from '@/api/axios.js';
import { formatAnalysisMethod, formatMeasure, safeStem } from '@/components/grain/format.js';
import { useAuthStore } from '@/store/auth.store.js';
import { deleteGuestRun, readGuestRuns } from '@/utils/guestRuns.js';

function reportedStat(summary, rawKey, robustKey) {
  return summary?.qc?.robust_used_for_reporting === false
    ? summary?.[rawKey]
    : (summary?.[robustKey] ?? summary?.[rawKey]);
}

export default function StoragePage() {
  const isGuest = useAuthStore((state) => state.isGuest);
  const [runs, setRuns] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [detailLoading, setDetailLoading] = useState(false);
  const [selected, setSelected] = useState(null);
  const [detailPreviewMode, setDetailPreviewMode] = useState('overlay');
  const [showAdvanced, setShowAdvanced] = useState(false);

  const loadRuns = async () => {
    setLoading(true);
    setError('');
    try {
      if (isGuest) {
        setRuns(readGuestRuns().map((item) => ({
          ...(item.result?.run || {}),
          id: item.clientRunId,
          sourceFileName: item.sourceFileName,
          createdAt: item.createdAt,
          image: item.result?.image || {},
          summary: item.result?.summary || {},
          localOnly: true,
        })));
        return;
      }
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
  }, [isGuest]);

  const openDetail = async (runId) => {
    setDetailLoading(true);
    setError('');
    try {
      if (isGuest) {
        const local = readGuestRuns().find((item) => item.clientRunId === runId);
        if (!local) throw new Error('Không tìm thấy bản xử lý local');
        setSelected({
          run: {
            ...(local.result?.run || {}),
            id: local.clientRunId,
            sourceFileName: local.sourceFileName,
            createdAt: local.createdAt,
          },
          result: local.result,
        });
        setDetailPreviewMode('overlay');
        return;
      }
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
      if (isGuest) {
        deleteGuestRun(run.id);
        setRuns((current) => current.filter((item) => item.id !== run.id));
        if (selected?.run?.id === run.id) setSelected(null);
        return;
      }
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
    original: detailResult?.original_png_base64,
    preprocessed: detailResult?.preprocessed_png_base64,
    overlay: detailResult?.overlay_png_base64,
    mask: detailResult?.mask_png_base64,
    labels: detailResult?.labels_png_base64,
  };
  const detailPreviewImage = detailPreviewImages[detailPreviewMode] || detailResult?.overlay_png_base64;

  return (
    <Box sx={{ maxWidth: 1200, minWidth: 0 }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 2, mb: 2.5, flexWrap: 'wrap' }}>
        <Box>
          <Typography variant="h5" fontWeight={700} mb={0.75}>Lưu trữ</Typography>
          {isGuest && (
            <Typography variant="body2" color="text.secondary">
              Các bản xử lý này lưu trên trình duyệt hiện tại. Đăng nhập để đồng bộ vào tài khoản.
            </Typography>
          )}
        </Box>
        <IconButton color="primary" onClick={loadRuns} disabled={loading} aria-label="Làm mới">
          <RefreshOutlined />
        </IconButton>
      </Box>

      {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}

      <Grid container spacing={2}>
        <Grid item xs={12}>
          <Card>
            <CardContent sx={{ p: 0 }}>
              <TableContainer sx={{ overflowX: 'auto' }}>
                <Table sx={{ minWidth: 920 }}>
                  <TableHead>
                    <TableRow>
                      <TableCell>Mã xử lý</TableCell>
                      <TableCell>Ảnh đầu vào</TableCell>
                      <TableCell>Thời gian</TableCell>
                      <TableCell align="right">Số hạt</TableCell>
                      <TableCell align="right">ĐLC dài (báo cáo)</TableCell>
                      <TableCell align="right">ĐLC rộng (báo cáo)</TableCell>
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
                          <Typography variant="body2" fontWeight={650} sx={{ maxWidth: 220 }} noWrap>{run.sourceFileName}</Typography>
                          <Typography variant="caption" color="text.secondary">
                            {run.image?.width || '-'} x {run.image?.height || '-'} px
                          </Typography>
                        </TableCell>
                        <TableCell>{formatDate(run.createdAt)}</TableCell>
                        <TableCell align="right">{run.summary?.count ?? 0}</TableCell>
                        <TableCell align="right">{formatMeasure(reportedStat(run.summary, 'std_length_mm', 'robust_std_length_mm'), 'mm', reportedStat(run.summary, 'std_length_px', 'robust_std_length_px'), 'px')}</TableCell>
                        <TableCell align="right">{formatMeasure(reportedStat(run.summary, 'std_width_mm', 'robust_std_width_mm'), 'mm', reportedStat(run.summary, 'std_width_px', 'robust_std_width_px'), 'px')}</TableCell>
                        <TableCell>
                          <Chip label={isGuest ? 'Lưu local' : 'Hoàn tất'} size="small" color="success" variant="outlined" />
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

      <Dialog open={Boolean(selected)} onClose={() => { setSelected(null); setShowAdvanced(false); }} maxWidth="lg" fullWidth>
        <DialogTitle>Chi tiết xử lý {detailRun ? shortRunId(detailRun.id) : ''}</DialogTitle>
        <DialogContent dividers>
          {detailResult && (
            <Grid container spacing={2}>
              <Grid item xs={12} md={7}>
                <Box sx={{
                  display: 'flex',
                  flexWrap: 'wrap',
                  gap: 1,
                  mb: 1.5,
                }}>
                  {[
                    ['original', 'Ảnh gốc'],
                    ['overlay', 'Đánh dấu'],
                    ['mask', 'Hình dạng'],
                    ['labels', 'Đánh số'],
                  ].map(([key, label]) => (
                    <Button
                      key={key}
                      size="small"
                      variant={detailPreviewMode === key ? 'contained' : 'outlined'}
                      disabled={!detailPreviewImages[key]}
                      onClick={() => setDetailPreviewMode(key)}
                      sx={{
                        flex: '0 1 auto',
                        minWidth: 0,
                        maxWidth: '100%',
                        whiteSpace: 'nowrap',
                      }}
                    >
                      {label}
                    </Button>
                  ))}
                </Box>
                <Box sx={{
                  border: '1px solid',
                  borderColor: 'divider',
                  borderRadius: 1,
                  bgcolor: '#FBFCFA',
                  minHeight: 320,
                  width: '100%',
                  display: 'grid',
                  placeItems: 'center',
                  overflow: 'hidden',
                }}>
                  {detailPreviewImage ? (
                    <Box
                      component="img"
                      src={`data:image/png;base64,${detailPreviewImage}`}
                      alt={detailRun?.sourceFileName || 'overlay'}
                      sx={{ width: '100%', maxHeight: 420, objectFit: 'contain', display: 'block' }}
                    />
                  ) : (
                    <Typography variant="body2" color="text.secondary">Không có overlay</Typography>
                  )}
                </Box>
              </Grid>
              <Grid item xs={12} md={5}>
                <Stack spacing={1.2}>
                  <ResultRow label="Tên tệp ảnh" value={detailRun?.sourceFileName || '-'} />
                  <ResultRow label="Thời gian quét" value={formatDate(detailRun?.createdAt)} />
                  <ResultRow label="Tổng số hạt đo được" value={detailResult.summary?.count ?? 0} />
                  <ResultRow label="ĐLC chiều dài (báo cáo)" value={formatMeasure(reportedStat(detailResult.summary, 'std_length_mm', 'robust_std_length_mm'), 'mm', reportedStat(detailResult.summary, 'std_length_px', 'robust_std_length_px'), 'px')} />
                  <ResultRow label="ĐLC chiều rộng (báo cáo)" value={formatMeasure(reportedStat(detailResult.summary, 'std_width_mm', 'robust_std_width_mm'), 'mm', reportedStat(detailResult.summary, 'std_width_px', 'robust_std_width_px'), 'px')} />
                  <ResultRow label="Vùng nghi nhiễu (QC)" value={String(detailResult.summary?.qc?.suspect_count ?? 0)} />
                  <ResultRow label="Tỷ lệ thước đo" value={detailResult.calibration?.enabled ? `${formatNumber(detailResult.calibration.mm_per_pixel, 5)} mm/px` : 'Chưa thiết lập'} />
                  
                  <Divider sx={{ my: 1 }} />
                  
                  <Button
                    size="small"
                    variant="text"
                    endIcon={showAdvanced ? <ExpandLess /> : <ExpandMore />}
                    onClick={() => setShowAdvanced(!showAdvanced)}
                    sx={{ alignSelf: 'flex-start', mb: 0.5, textTransform: 'none', color: 'text.secondary', p: 0 }}
                  >
                    {showAdvanced ? 'Ẩn thông số kỹ thuật' : 'Hiển thị thông số kỹ thuật'}
                  </Button>

                  <Collapse in={showAdvanced}>
                    <Stack spacing={1.2} sx={{ pl: 1.5, borderLeft: '2px solid', borderColor: 'divider', my: 1 }}>
                      <ResultRow label="Phương thức phân tích" value={formatAnalysisMethod(detailResult.segmentation)} />
                      {detailResult.segmentation?.confidence && (
                        <ResultRow label="Độ tin cậy nhận dạng" value={`${(Number(detailResult.segmentation.confidence) * 100).toFixed(0)}%`} />
                      )}
                      {detailResult.segmentation?.iou && (
                        <ResultRow label="Độ khớp mặt nạ (IoU)" value={`${(Number(detailResult.segmentation.iou) * 100).toFixed(0)}%`} />
                      )}
                    </Stack>
                  </Collapse>

                  <Divider />
                  <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1} useFlexGap flexWrap="wrap" pt={1}>
                    <Button
                      variant="contained"
                      startIcon={<DownloadOutlined />}
                      disabled={!detailResult.csv}
                      onClick={() => downloadBlob(`${safeStem(detailRun?.sourceFileName)}_measurements.csv`, detailResult.csv, 'text/csv;charset=utf-8')}
                    >
                      Xuất CSV
                    </Button>
                    <Button
                      variant="outlined"
                      startIcon={<DownloadOutlined />}
                      disabled={!detailResult.overlay_png_base64}
                      onClick={() => downloadPng(detailRun?.sourceFileName, detailResult.overlay_png_base64)}
                    >
                      Xuất ảnh kết quả
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
  <Box sx={{
    display: 'grid',
    gridTemplateColumns: 'minmax(92px, max-content) minmax(0, 1fr)',
    alignItems: 'start',
    gap: 2,
  }}>
    <Typography variant="body2" color="text.secondary" sx={{ whiteSpace: 'nowrap' }}>{label}</Typography>
    <Typography
      variant="body2"
      fontWeight={650}
      textAlign="right"
      sx={{ minWidth: 0, overflowWrap: 'anywhere' }}
    >
      {value}
    </Typography>
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
