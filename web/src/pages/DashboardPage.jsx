import { useEffect, useRef, useState } from 'react';
import {
  Box, Typography, Grid, Card, CardContent, Button, Stack,
  Divider, Chip, alpha,
} from '@mui/material';
import {
  CameraAltOutlined, UploadFileOutlined, ImageSearchOutlined,
  Straighten, GrainOutlined, CalendarMonthOutlined,
} from '@mui/icons-material';

const usageStats = [
  { label: 'Lượt dùng tháng này', value: '128', note: 'Tháng hiện tại', icon: <CalendarMonthOutlined /> },
  { label: 'Lượt dùng năm nay', value: '1.426', note: 'Tổng theo năm', icon: <CalendarMonthOutlined /> },
  { label: 'Tổng lượt dùng', value: '3.918', note: 'Từ khi triển khai', icon: <ImageSearchOutlined /> },
  { label: 'Hạt đã đo đạc', value: '18.240', note: 'Mẫu hợp lệ', icon: <GrainOutlined /> },
  { label: 'Chiều dài TB', value: '7,42 mm', note: 'Theo dữ liệu gần nhất', icon: <Straighten /> },
  { label: 'Chiều rộng TB', value: '3,18 mm', note: 'Theo dữ liệu gần nhất', icon: <Straighten /> },
];

const recentMetrics = [
  { label: 'Số hạt nhận dạng', value: '124' },
  { label: 'Tỉ lệ segment', value: '96,8%' },
  { label: 'Dài nhỏ nhất', value: '5,12 mm' },
  { label: 'Dài lớn nhất', value: '9,84 mm' },
];

const StatCard = ({ label, value, note, icon }) => (
  <Card sx={{ height: '100%' }}>
    <CardContent sx={{ p: 2.5 }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 2, mb: 1.5 }}>
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

export default function DashboardPage() {
  const videoRef = useRef(null);
  const [cameraActive, setCameraActive] = useState(false);
  const [previewUrl, setPreviewUrl] = useState('');
  const [fileName, setFileName] = useState('');
  const [cameraError, setCameraError] = useState('');

  useEffect(() => () => {
    if (videoRef.current?.srcObject) {
      videoRef.current.srcObject.getTracks().forEach((track) => track.stop());
    }
    if (previewUrl) URL.revokeObjectURL(previewUrl);
  }, [previewUrl]);

  const handleCamera = async () => {
    setCameraError('');
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: true });
      if (videoRef.current) videoRef.current.srcObject = stream;
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
    setFileName(file.name);
    setCameraActive(false);
  };

  return (
    <Box sx={{ maxWidth: 1200 }}>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" fontWeight={700} mb={0.75}>Trang chủ</Typography>
        <Typography variant="body2" color="text.secondary">
          Theo dõi lượt sử dụng, dữ liệu đo đạc và xử lý ảnh hạt giống.
        </Typography>
      </Box>

      <Grid container spacing={2} mb={3}>
        {usageStats.map((item) => (
          <Grid item xs={12} sm={6} lg={4} key={item.label}>
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
                  <Typography variant="h6" fontWeight={700}>Xử lý ảnh đo đạc</Typography>
                  <Typography variant="body2" color="text.secondary">
                    Kết nối camera hoặc import ảnh để nhận dạng, segment và đo thông số hạt.
                  </Typography>
                </Box>
                <Chip label="Sẵn sàng" color="success" variant="outlined" size="small" />
              </Box>

              <Box sx={{
                minHeight: 320,
                border: '1px dashed',
                borderColor: 'divider',
                borderRadius: 1.5,
                bgcolor: '#FBFCFA',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                overflow: 'hidden',
                mb: 2,
              }}>
                {previewUrl ? (
                  <Box component="img" src={previewUrl} alt={fileName} sx={{ width: '100%', height: 320, objectFit: 'contain' }} />
                ) : (
                  <video ref={videoRef} autoPlay muted playsInline style={{ width: '100%', maxHeight: 320, display: cameraActive ? 'block' : 'none' }} />
                )}
                {!previewUrl && !cameraActive && (
                  <Stack alignItems="center" spacing={1.25} sx={{ color: 'text.secondary', textAlign: 'center', px: 2 }}>
                    <ImageSearchOutlined sx={{ fontSize: 46, color: 'primary.main' }} />
                    <Typography fontWeight={650} color="text.primary">Chưa có ảnh đầu vào</Typography>
                    <Typography variant="body2">Chọn camera hoặc import file ảnh hạt giống để bắt đầu xử lý.</Typography>
                  </Stack>
                )}
              </Box>

              {cameraError && (
                <Typography variant="body2" color="error.main" mb={1.5}>{cameraError}</Typography>
              )}

              <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1}>
                <Button variant="contained" startIcon={<CameraAltOutlined />} onClick={handleCamera}>
                  Kết nối camera
                </Button>
                <Button variant="outlined" component="label" startIcon={<UploadFileOutlined />}>
                  Import ảnh
                  <input hidden type="file" accept="image/*" onChange={handleFile} />
                </Button>
                <Button variant="outlined" startIcon={<ImageSearchOutlined />} disabled={!previewUrl && !cameraActive}>
                  Chạy nhận dạng
                </Button>
              </Stack>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} lg={5}>
          <Card sx={{ height: '100%' }}>
            <CardContent sx={{ p: 2.5 }}>
              <Typography variant="h6" fontWeight={700} mb={0.5}>Kết quả đo gần nhất</Typography>
              <Typography variant="body2" color="text.secondary" mb={2}>
                Thông số mẫu sau nhận dạng và segment.
              </Typography>
              <Stack spacing={1.5}>
                {recentMetrics.map((item) => (
                  <Box key={item.label} sx={{ display: 'flex', justifyContent: 'space-between', gap: 2 }}>
                    <Typography variant="body2" color="text.secondary">{item.label}</Typography>
                    <Typography variant="body2" fontWeight={650}>{item.value}</Typography>
                  </Box>
                ))}
              </Stack>
              <Divider sx={{ my: 2 }} />
              <Typography variant="body2" color="text.secondary" mb={1}>Output số liệu</Typography>
              <Box sx={{
                border: '1px solid',
                borderColor: 'divider',
                borderRadius: 1,
                overflow: 'hidden',
              }}>
                {[
                  ['Chiều dài TB', '7,42 mm'],
                  ['Chiều rộng TB', '3,18 mm'],
                  ['Độ lệch chuẩn dài', '0,84 mm'],
                  ['Độ lệch chuẩn rộng', '0,31 mm'],
                ].map(([label, value]) => (
                  <Box key={label} sx={{ display: 'flex', justifyContent: 'space-between', px: 1.5, py: 1, borderBottom: '1px solid', borderColor: 'divider', '&:last-child': { borderBottom: 0 } }}>
                    <Typography variant="caption" color="text.secondary">{label}</Typography>
                    <Typography variant="caption" fontWeight={650}>{value}</Typography>
                  </Box>
                ))}
              </Box>
            </CardContent>
          </Card>
        </Grid>
      </Grid>
    </Box>
  );
}
