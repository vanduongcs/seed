import { useState } from 'react';
import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  Chip,
  CircularProgress,
  Dialog,
  DialogContent,
  Divider,
  IconButton,
  LinearProgress,
  Stack,
  TextField,
  Typography,
} from '@mui/material';
import { HelpOutline, Close, Stars, CompareArrows, Edit, Check, TouchApp } from '@mui/icons-material';

const PREVIEW_MODES = [
  ['overlay', 'Đánh dấu'],
  ['mask', 'Hình dạng'],
  ['labels', 'Đánh số'],
];

const SlideContent = ({ title, description, diagram }) => (
  <Stack alignItems="center" spacing={2} sx={{ px: 2, py: 1, textAlign: 'center', height: '100%' }}>
    <Typography variant="subtitle1" fontWeight={750} color="primary">
      {title}
    </Typography>
    <Typography variant="body2" color="text.secondary" sx={{ height: 48, lineHeight: 1.45 }}>
      {description}
    </Typography>
    <Box sx={{ flexGrow: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: 110, mt: 1 }}>
      {diagram}
    </Box>
  </Stack>
);

export const DashboardPreviewPanel = ({
  cameraActive,
  cameraError,
  calibration,
  calibrationImage,
  calibrationPixels,
  calibrationReady,
  displayImage,
  drawingCalibration,
  fileName,
  imageRef,
  previewMode,
  previewUrl,
  processError,
  processing,
  result,
  videoRef,
  onCamera,
  onFile,
  onProcess,
  onCalibrationChange,
  onDrawingCalibrationChange,
  onPreviewModeChange,
  getCalibrationPoint,
  renderCalibrationOverlay,
  progress,
  progressPhase,
}) => {
  const [guideOpen, setGuideOpen] = useState(false);
  const [currentStep, setCurrentStep] = useState(0);

  const handleNext = () => {
    if (currentStep < 3) {
      setCurrentStep((prev) => prev + 1);
    } else {
      setGuideOpen(false);
    }
  };

  const handleBack = () => {
    setCurrentStep((prev) => Math.max(prev - 1, 0));
  };

  const renderSlideDiagram = (step) => {
    switch (step) {
      case 0:
        return (
          <Stack direction="row" spacing={3} alignItems="center">
            <Box sx={{
              width: 50,
              height: 50,
              borderRadius: '50%',
              background: 'linear-gradient(135deg, #FBBF24 0%, #D97706 100%)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              boxShadow: '0 3px 6px rgba(0,0,0,0.12)'
            }}>
              <Stars sx={{ color: 'white', fontSize: 26 }} />
            </Box>
            <CompareArrows sx={{ color: 'text.secondary', fontSize: 28 }} />
            <Stack direction="row" spacing={0.5}>
              {[0, 1, 2].map((i) => (
                <Box key={i} sx={{
                  width: 12,
                  height: 22,
                  borderRadius: 1.5,
                  bgcolor: '#EAB308',
                  border: '1.5px solid #CA8A04'
                }} />
              ))}
            </Stack>
          </Stack>
        );
      case 1:
        return (
          <Box sx={{
            width: 180,
            height: 100,
            bgcolor: '#F3F4F6',
            borderRadius: 2,
            border: '1px solid #E5E7EB',
            position: 'relative',
            overflow: 'hidden'
          }}>
            <Box sx={{
              position: 'absolute',
              top: '50%',
              left: '50%',
              transform: 'translate(-50%, -50%)',
              width: 100,
              height: 28,
              bgcolor: '#D1D5DB',
              borderRadius: 1,
              border: '1px dashed #9CA3AF',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center'
            }}>
              <Typography variant="caption" color="text.secondary" fontWeight={600} sx={{ fontSize: 9 }}>Vật mốc</Typography>
            </Box>
            <Box sx={{
              position: 'absolute',
              left: 45,
              top: 50,
              width: 90,
              height: 2,
              bgcolor: '#1D4ED8'
            }} />
            <Box sx={{
              position: 'absolute',
              left: 38,
              top: 43,
              width: 16,
              height: 16,
              borderRadius: '50%',
              bgcolor: '#1D4ED8',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              boxShadow: '0 1px 3px rgba(0,0,0,0.15)'
            }}>
              <Typography sx={{ color: 'white', fontSize: 8, fontWeight: 'bold' }}>A</Typography>
            </Box>
            <Box sx={{
              position: 'absolute',
              right: 38,
              top: 43,
              width: 16,
              height: 16,
              borderRadius: '50%',
              bgcolor: '#1D4ED8',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              boxShadow: '0 1px 3px rgba(0,0,0,0.15)'
            }}>
              <Typography sx={{ color: 'white', fontSize: 8, fontWeight: 'bold' }}>B</Typography>
            </Box>
            <TouchApp sx={{
              position: 'absolute',
              right: 25,
              bottom: 8,
              color: 'primary.main',
              fontSize: 24,
            }} />
          </Box>
        );
      case 2:
        return (
          <Stack spacing={1} sx={{ textAlign: 'left', width: '100%', maxWidth: 210 }}>
            <Stack direction="row" spacing={1} alignItems="center">
              <Check color="primary" sx={{ fontSize: 16 }} />
              <Typography variant="caption" fontWeight={650}>Kéo thả chuột chính xác</Typography>
            </Stack>
            <Typography variant="caption" color="text.secondary" sx={{ pl: 3.25, mt: -0.5, fontSize: 10, lineHeight: 1.25 }}>
              Giữ chuột trái ở đầu A, kéo thẳng sang đầu B của vật mốc rồi thả ra để hoàn tất vẽ.
            </Typography>
            <Stack direction="row" spacing={1} alignItems="center">
              <Check color="primary" sx={{ fontSize: 16 }} />
              <Typography variant="caption" fontWeight={650}>Xóa vẽ lại dễ dàng</Typography>
            </Stack>
            <Typography variant="caption" color="text.secondary" sx={{ pl: 3.25, mt: -0.5, fontSize: 10, lineHeight: 1.25 }}>
              Click nút "Xóa vật mốc" để vẽ lại từ đầu bất cứ lúc nào.
            </Typography>
          </Stack>
        );
      case 3:
        return (
          <Box sx={{
            display: 'flex',
            alignItems: 'center',
            gap: 1.5,
            p: 1.25,
            bgcolor: 'background.paper',
            borderRadius: 1.5,
            border: '1.5px solid',
            borderColor: 'primary.main',
            boxShadow: '0 4px 10px rgba(47, 107, 79, 0.06)'
          }}>
            <Edit sx={{ color: 'primary.main', fontSize: 14 }} />
            <Typography variant="body2" fontWeight={600} color="text.primary">
              Vật mốc (mm): <Box component="span" sx={{ color: 'primary.main', fontWeight: 750 }}>20.0</Box>
            </Typography>
            <Box sx={{
              width: 18,
              height: 18,
              borderRadius: '50%',
              bgcolor: '#2E7D32',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center'
            }}>
              <Check sx={{ color: 'white', fontSize: 11 }} />
            </Box>
          </Box>
        );
      default:
        return null;
    }
  };

  const getSlideTitle = (step) => {
    switch (step) {
      case 0: return '1. Ý nghĩa của vật mốc';
      case 1: return '2. Cách vẽ thước đo';
      case 2: return '3. Cách thao tác kéo thả';
      case 3: return '4. Nhập chiều dài thực tế';
      default: return '';
    }
  };

  const getSlideDescription = (step) => {
    switch (step) {
      case 0: return 'Vật mốc vật lý (đồng xu, thước đo...) đặt cạnh các hạt giúp quy đổi chính xác kích thước pixel trên ảnh sang milimét trong thực tế.';
      case 1: return 'Dùng chuột nhấp và kéo một đường đo thẳng khớp từ đầu này sang đầu kia của vật mốc trên hình ảnh để đo độ dài điểm ảnh.';
      case 2: return 'Nhấp giữ chuột trái ở một đầu của vật mốc, giữ và kéo thẳng chuột sang đầu bên kia rồi buông chuột ra. Đường đo sẽ tự động được vẽ.';
      case 3: return 'Cuối cùng, nhập kích thước thực của vật mốc (ví dụ: 20 mm cho đồng xu 2cm) để hoàn tất quy đổi tỷ lệ hạt.';
      default: return '';
    }
  };

  return (
    <>
      <Card sx={{ height: '100%' }}>
        <CardContent sx={{ p: 2.5 }}>
          <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 2, mb: 2 }}>
            <Box sx={{ display: 'flex', alignItems: 'flex-start', gap: 0.75 }}>
              <Box>
                <Typography variant="h6" fontWeight={700}>Hình ảnh hiển thị</Typography>
                <Typography variant="body2" color="text.secondary">
                  Xem trước ảnh chụp từ camera hoặc tệp ảnh tải lên để phân tích kích thước hạt.
                </Typography>
              </Box>
              <IconButton
                size="small"
                color="primary"
                onClick={() => {
                  setCurrentStep(0);
                  setGuideOpen(true);
                }}
                title="Xem hướng dẫn căn mốc"
                aria-label="Xem hướng dẫn căn mốc"
              >
                <HelpOutline fontSize="small" />
              </IconButton>
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
              {PREVIEW_MODES.map(([key, label]) => (
                <Button
                  key={key}
                  size="small"
                  variant={previewMode === key ? 'contained' : 'outlined'}
                  onClick={() => onPreviewModeChange(key)}
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
                  onDrawingCalibrationChange(true);
                  onCalibrationChange((current) => ({ ...current, start: point, end: point }));
                }}
                onPointerMove={(event) => {
                  if (!drawingCalibration) return;
                  const point = getCalibrationPoint(event);
                  if (point) onCalibrationChange((current) => ({ ...current, end: point }));
                }}
                onPointerUp={() => onDrawingCalibrationChange(false)}
                onPointerLeave={() => onDrawingCalibrationChange(false)}
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
                bgcolor: 'rgba(255,255,255,0.85)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                p: 3,
              }}>
                <Stack alignItems="center" spacing={1.5} sx={{ width: '80%', maxWidth: 360 }}>
                  <CircularProgress size={36} thickness={4.5} />
                  <Box sx={{ width: '100%', mt: 1 }}>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 0.5 }}>
                      <Typography variant="body2" color="text.secondary" fontWeight={600}>
                        {progressPhase || 'Đang xử lý...'}
                      </Typography>
                      <Typography variant="body2" fontWeight={750} color="primary">
                        {Math.round(progress)}%
                      </Typography>
                    </Box>
                    <Box sx={{ width: '100%', bgcolor: 'divider', borderRadius: 1, overflow: 'hidden', height: 6 }}>
                      <Box sx={{
                        width: `${progress}%`,
                        bgcolor: 'primary.main',
                        height: '100%',
                        transition: 'width 0.4s ease',
                      }} />
                    </Box>
                  </Box>
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
                  onChange={(event) => onCalibrationChange((current) => ({ ...current, referenceMm: event.target.value }))}
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
                  onClick={() => onCalibrationChange({ start: null, end: null, referenceMm: '' })}
                >
                  Xóa vật mốc
                </Button>
              </Stack>
            </Box>
          )}
          {cameraError && <Alert severity="error" sx={{ mb: 1.5 }}>{cameraError}</Alert>}
          {processError && <Alert severity="error" sx={{ mb: 1.5 }}>{processError}</Alert>}

          <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1}>
            <Button variant="contained" onClick={onCamera}>
              Kết nối camera
            </Button>
            <Button variant="outlined" component="label">
              Import ảnh
              <input hidden type="file" accept="image/jpeg,image/png" onChange={onFile} />
            </Button>
            <Button
              variant="outlined"
              disabled={processing || (!fileName && !cameraActive)}
              onClick={onProcess}
            >
              {processing ? 'Đang xử lý...' : (result ? 'Chạy lại' : 'Chạy xử lý')}
            </Button>
          </Stack>

          {processing && (
            <Box sx={{ width: '100%', mt: 2.5 }}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
                <Typography variant="body2" color="text.secondary" fontWeight={600}>
                  {progressPhase || 'Đang xử lý...'}
                </Typography>
                <Typography variant="body2" fontWeight={750} color="primary.main">
                  {Math.round(progress)}%
                </Typography>
              </Box>
              <LinearProgress
                variant="determinate"
                value={progress}
                sx={{
                  height: 6,
                  borderRadius: 3,
                  bgcolor: 'rgba(47, 107, 79, 0.08)',
                  '& .MuiLinearProgress-bar': {
                    borderRadius: 3,
                    bgcolor: 'primary.main',
                  }
                }}
              />
            </Box>
          )}
        </CardContent>
      </Card>

      {/* Web Calibration Guide Dialog */}
      <Dialog
        open={guideOpen}
        onClose={() => setGuideOpen(false)}
        maxWidth="xs"
        fullWidth
        PaperProps={{
          sx: { borderRadius: 3, p: 2 }
        }}
      >
        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 1.5 }}>
          <Stack direction="row" spacing={1} alignItems="center">
            <HelpOutline color="primary" sx={{ fontSize: 22 }} />
            <Typography variant="h6" fontWeight={750} color="text.primary" sx={{ fontSize: '1rem' }}>
              Hướng dẫn căn vật mốc
            </Typography>
          </Stack>
          <IconButton size="small" onClick={() => setGuideOpen(false)} sx={{ color: 'text.secondary' }}>
            <Close fontSize="small" />
          </IconButton>
        </Box>
        
        <Divider sx={{ mb: 2 }} />
        
        <Box sx={{ minHeight: 220, display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
          <SlideContent
            title={getSlideTitle(currentStep)}
            description={getSlideDescription(currentStep)}
            diagram={renderSlideDiagram(currentStep)}
          />
        </Box>
        
        <Divider sx={{ mt: 2, mb: 1.5 }} />
        
        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          {/* Custom dots indicators */}
          <Stack direction="row" spacing={0.75}>
            {[0, 1, 2, 3].map((step) => (
              <Box
                key={step}
                sx={{
                  width: currentStep === step ? 16 : 6,
                  height: 6,
                  borderRadius: 3,
                  bgcolor: currentStep === step ? 'primary.main' : 'divider',
                  transition: 'all 0.3s ease'
                }}
              />
            ))}
          </Stack>
          
          <Stack direction="row" spacing={1}>
            {currentStep > 0 && (
              <Button size="small" color="inherit" onClick={handleBack} sx={{ fontWeight: 600 }}>
                Quay lại
              </Button>
            )}
            <Button
              size="small"
              variant="contained"
              onClick={handleNext}
              sx={{ fontWeight: 700, px: 2 }}
            >
              {currentStep === 3 ? 'Bắt đầu' : 'Tiếp theo'}
            </Button>
          </Stack>
        </Box>
      </Dialog>
    </>
  );
};
