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
  Divider,
  IconButton,
  LinearProgress,
  Stack,
  TextField,
  Tooltip,
  Typography,
} from '@mui/material';
import { HelpOutline, Close, Edit, Check, Mouse, CameraAlt, Straighten } from '@mui/icons-material';

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
  qcEditMode,
  onToggleQcEditMode,
  onToggleMeasurementQc,
}) => {
  const [guideOpen, setGuideOpen] = useState(false);
  const [currentStep, setCurrentStep] = useState(0);
  const [draggingHandle, setDraggingHandle] = useState(null);

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

  const getNearestCalibrationHandle = (point) => {
    const image = imageRef.current;
    if (!point || !image?.naturalWidth || !calibration.start || !calibration.end) return null;

    const rect = image.getBoundingClientRect();
    const threshold = (16 / Math.max(1, rect.width)) * image.naturalWidth;
    const startDistance = Math.hypot(point.x - calibration.start.x, point.y - calibration.start.y);
    const endDistance = Math.hypot(point.x - calibration.end.x, point.y - calibration.end.y);

    if (Math.min(startDistance, endDistance) > threshold) return null;
    return startDistance <= endDistance ? 'start' : 'end';
  };

  // Diagram: bước 0 — chụp ảnh có vật mốc
  const DiagramStep0 = () => (
    <Stack spacing={1.5} alignItems="center">
      <Stack direction="row" spacing={2} alignItems="flex-end" justifyContent="center">
        {/* Vật mốc: đồng xu */}
        <Stack alignItems="center" spacing={0.5}>
          <Box sx={{
            width: 38, height: 38, borderRadius: '50%',
            background: 'linear-gradient(135deg, #FBBF24, #D97706)',
            border: '2px solid #B45309',
            display: 'flex', alignItems: 'center', justifyContent: 'center'
          }}>
            <Typography sx={{ fontSize: 8, color: 'white', fontWeight: 'bold', lineHeight: 1 }}>500đ</Typography>
          </Box>
          <Typography variant="caption" sx={{ fontSize: 9, color: 'text.secondary' }}>Vật mốc</Typography>
        </Stack>
        {/* Các hạt */}
        <Stack alignItems="center" spacing={0.5}>
          <Stack direction="row" spacing={0.5}>
            {[14, 18, 12, 16].map((h, i) => (
              <Box key={i} sx={{ width: 10, height: h, borderRadius: 1, bgcolor: '#EAB308', border: '1px solid #CA8A04' }} />
            ))}
          </Stack>
          <Typography variant="caption" sx={{ fontSize: 9, color: 'text.secondary' }}>Hạt cần đo</Typography>
        </Stack>
      </Stack>
      <Stack direction="row" spacing={0.75} alignItems="center">
        <CameraAlt sx={{ fontSize: 16, color: 'text.secondary' }} />
        <Typography variant="caption" sx={{ fontSize: 10, color: 'text.secondary' }}>Chụp cùng một khung ảnh</Typography>
      </Stack>
    </Stack>
  );

  // Diagram: bước 1 — kéo thả chuột từ trái sang phải
  const DiagramStep1 = () => (
    <Box sx={{ position: 'relative', width: 200, height: 90, bgcolor: '#F3F4F6', borderRadius: 2, border: '1px solid #E5E7EB', overflow: 'hidden' }}>
      {/* Vật mốc */}
      <Box sx={{ position: 'absolute', left: 20, top: 28, width: 160, height: 34, bgcolor: '#D1D5DB', borderRadius: 1, border: '1px dashed #9CA3AF', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <Typography sx={{ fontSize: 9, color: '#6B7280', fontWeight: 600 }}>Vật mốc (đồng xu / thước)</Typography>
      </Box>
      {/* Đường đo */}
      <Box sx={{ position: 'absolute', left: 22, top: 44, width: 156, height: 2, bgcolor: '#2563EB' }} />
      {/* Chốt A */}
      <Box sx={{ position: 'absolute', left: 14, top: 37, width: 16, height: 16, borderRadius: '50%', bgcolor: '#2563EB', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 0 0 4px rgba(37,99,235,0.18)' }}>
        <Typography sx={{ color: 'white', fontSize: 8, fontWeight: 'bold' }}>A</Typography>
      </Box>
      {/* Chốt B */}
      <Box sx={{ position: 'absolute', right: 14, top: 37, width: 16, height: 16, borderRadius: '50%', bgcolor: '#2563EB', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <Typography sx={{ color: 'white', fontSize: 8, fontWeight: 'bold' }}>B</Typography>
      </Box>
      {/* Mũi tên hướng kéo */}
      <Mouse sx={{ position: 'absolute', left: 8, bottom: 6, fontSize: 16, color: '#6B7280' }} />
      <Typography sx={{ position: 'absolute', left: 26, bottom: 8, fontSize: 9, color: '#6B7280' }}>Kéo chuột để tạo đoạn tham chiếu</Typography>
    </Box>
  );

  // Diagram: bước 2 — kéo chốt để căn lại
  const DiagramStep2 = () => (
    <Stack spacing={1.25} sx={{ width: '100%', maxWidth: 210 }}>
      <Stack direction="row" spacing={1.25} alignItems="flex-start">
        <Box sx={{ mt: 0.25, width: 18, height: 18, borderRadius: '50%', bgcolor: 'primary.main', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
          <Typography sx={{ color: 'white', fontSize: 10, fontWeight: 'bold' }}>1</Typography>
        </Box>
        <Typography variant="caption" sx={{ lineHeight: 1.45 }}>
          Kéo <Box component="span" sx={{ fontWeight: 700 }}>chốt A</Box> hoặc <Box component="span" sx={{ fontWeight: 700 }}>chốt B</Box> sát mép vật mốc.
        </Typography>
      </Stack>
      <Stack direction="row" spacing={1.25} alignItems="flex-start">
        <Box sx={{ mt: 0.25, width: 18, height: 18, borderRadius: '50%', bgcolor: 'primary.main', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
          <Typography sx={{ color: 'white', fontSize: 10, fontWeight: 'bold' }}>2</Typography>
        </Box>
        <Typography variant="caption" sx={{ lineHeight: 1.45 }}>
          Số <Box component="span" sx={{ fontWeight: 700 }}>px</Box> tự cập nhật khi di chuyển chốt.
        </Typography>
      </Stack>
      <Stack direction="row" spacing={1.25} alignItems="flex-start">
        <Box sx={{ mt: 0.25, width: 18, height: 18, borderRadius: '50%', bgcolor: 'success.main', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
          <Check sx={{ color: 'white', fontSize: 12 }} />
        </Box>
        <Typography variant="caption" sx={{ lineHeight: 1.45, color: 'text.secondary' }}>
          Xóa đoạn tham chiếu nếu cần đặt lại từ đầu.
        </Typography>
      </Stack>
    </Stack>
  );

  // Diagram: bước 3 — nhập mm
  const DiagramStep3 = () => (
    <Stack spacing={1} alignItems="center">
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, p: 1.25, bgcolor: 'background.paper', borderRadius: 1.5, border: '1.5px solid', borderColor: 'primary.main', width: 190 }}>
        <Edit sx={{ color: 'primary.main', fontSize: 14 }} />
        <Typography variant="body2" fontWeight={600} sx={{ flexGrow: 1 }}>
          Kích thước vật mốc (mm):
        </Typography>
      </Box>
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, p: 1, bgcolor: '#F0FDF4', borderRadius: 1.5, border: '1px solid #86EFAC', width: 190 }}>
        <Straighten sx={{ color: 'success.main', fontSize: 14 }} />
        <Typography variant="body2" fontWeight={700} color="success.dark">20</Typography>
        <Typography variant="caption" color="text.secondary">mm (ví dụ: đồng xu 500đ ≈ 20 mm)</Typography>
      </Box>
      <Stack direction="row" spacing={0.5} alignItems="center">
        <Check sx={{ color: 'success.main', fontSize: 14 }} />
        <Typography variant="caption" color="text.secondary">Hệ thống tự tính tỷ lệ mm/px</Typography>
      </Stack>
    </Stack>
  );

  const renderSlideDiagram = (step) => {
    switch (step) {
      case 0: return <DiagramStep0 />;
      case 1: return <DiagramStep1 />;
      case 2: return <DiagramStep2 />;
      case 3: return <DiagramStep3 />;
      default: return null;
    }
  };

  const getSlideTitle = (step) => {
    switch (step) {
      case 0: return '1. Chụp kèm vật mốc';
      case 1: return '2. Tạo đoạn tham chiếu';
      case 2: return '3. Kéo chốt để căn chính xác';
      case 3: return '4. Nhập kích thước thực tế (mm)';
      default: return '';
    }
  };

  const getSlideDescription = (step) => {
    switch (step) {
      case 0: return 'Đặt vật mốc có kích thước biết trước cạnh hạt và chụp chung trong một khung ảnh.';
      case 1: return 'Kéo chuột dọc theo vật mốc để tạo đoạn tham chiếu.';
      case 2: return 'Kéo chốt A hoặc chốt B sát hai mép vật mốc.';
      case 3: return 'Nhập kích thước thực tế của vật mốc để quy đổi kết quả sang mm.';
      default: return '';
    }
  };

  const imageWidth = Number(result?.image?.width) || imageRef.current?.naturalWidth || 1;
  const imageHeight = Number(result?.image?.height) || imageRef.current?.naturalHeight || 1;
  const measurementMasks = (result?.measurements || [])
    .filter((measurement) => (
      (Number(measurement.length_px) > 0 && Number(measurement.width_px) > 0)
      || (Number(measurement.bbox_w) > 0 && Number(measurement.bbox_h) > 0)
    ))
    .map((measurement) => ({
      id: measurement.id,
      outlier: measurement.qc_outlier === true,
      manual: measurement.qc_manual_override === true,
      centerX: (Number(measurement.centroid_x ?? (Number(measurement.bbox_x) + Number(measurement.bbox_w) / 2)) / imageWidth) * 100,
      centerY: (Number(measurement.centroid_y ?? (Number(measurement.bbox_y) + Number(measurement.bbox_h) / 2)) / imageHeight) * 100,
      width: (Math.max(Number(measurement.length_px) || 0, Number(measurement.bbox_w) || 0) / imageWidth) * 100,
      height: (Math.max(Number(measurement.width_px) || 0, Math.min(Number(measurement.bbox_h) || 0, Number(measurement.bbox_w) || 0)) / imageHeight) * 100,
      angle: Number(measurement.angle_deg) || 0,
    }));

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
            <Stack spacing={1} sx={{ mb: 1.5 }}>
              <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1}>
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
                <Button
                  size="small"
                  color={qcEditMode ? 'warning' : 'primary'}
                  variant={qcEditMode ? 'contained' : 'outlined'}
                  startIcon={qcEditMode ? <Check fontSize="small" /> : <Edit fontSize="small" />}
                  onClick={onToggleQcEditMode}
                  sx={{ fontWeight: 750 }}
                >
                  {qcEditMode ? 'Xong sửa QC' : 'Sửa QC'}
                </Button>
              </Stack>
              {qcEditMode && (
                <Alert severity="info" sx={{ py: 0.5 }}>
                  Click vào hạt để đổi giữa nghi ngờ và hợp lệ. Hạt nghi ngờ hiển thị bằng mask đỏ, không vẽ ô chữ nhật.
                </Alert>
              )}
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
                  if (qcEditMode) return;
                  if (!calibrationImage || processing) return;
                  const point = getCalibrationPoint(event);
                  if (!point) return;
                  const handle = getNearestCalibrationHandle(point);
                  event.currentTarget.setPointerCapture(event.pointerId);
                  if (handle) {
                    setDraggingHandle(handle);
                    return;
                  }
                  setDraggingHandle(null);
                  onDrawingCalibrationChange(true);
                  onCalibrationChange((current) => ({ ...current, start: point, end: point }));
                }}
                onPointerMove={(event) => {
                  const point = getCalibrationPoint(event);
                  if (!point) return;
                  if (draggingHandle) {
                    onCalibrationChange((current) => ({ ...current, [draggingHandle]: point }));
                    return;
                  }
                  if (drawingCalibration) onCalibrationChange((current) => ({ ...current, end: point }));
                }}
                onPointerUp={(event) => {
                  setDraggingHandle(null);
                  onDrawingCalibrationChange(false);
                  if (event.currentTarget.hasPointerCapture(event.pointerId)) {
                    event.currentTarget.releasePointerCapture(event.pointerId);
                  }
                }}
                onPointerCancel={() => {
                  setDraggingHandle(null);
                  onDrawingCalibrationChange(false);
                }}
                onPointerLeave={() => {
                  if (!draggingHandle) onDrawingCalibrationChange(false);
                }}
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
                  {result && measurementMasks.map((mask) => {
                    if (!qcEditMode) return null;
                    return (
                      <Tooltip
                        key={mask.id}
                        title={`${mask.outlier ? 'Bỏ nghi ngờ' : 'Đánh dấu nghi ngờ'} #${mask.id}`}
                        arrow
                      >
                        <Box
                          component="button"
                          type="button"
                          onPointerDown={(event) => {
                            if (!qcEditMode) return;
                            event.stopPropagation();
                            onToggleMeasurementQc(mask.id);
                          }}
                          sx={{
                            position: 'absolute',
                            left: `${mask.centerX}%`,
                            top: `${mask.centerY}%`,
                            width: `${mask.width}%`,
                            height: `${mask.height}%`,
                            minWidth: 10,
                            minHeight: 6,
                            border: 0,
                            bgcolor: 'transparent',
                            borderRadius: '999px',
                            clipPath: 'ellipse(50% 50% at 50% 50%)',
                            transform: `translate(-50%, -50%) rotate(${mask.angle}deg)`,
                            transformOrigin: '50% 50%',
                            cursor: qcEditMode ? 'pointer' : 'default',
                            pointerEvents: 'auto',
                            p: 0,
                            opacity: 0,
                            outline: 'none',
                          }}
                        />
                      </Tooltip>
                    );
                  })}
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
