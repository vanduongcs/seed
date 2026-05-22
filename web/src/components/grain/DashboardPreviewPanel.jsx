import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  Chip,
  CircularProgress,
  LinearProgress,
  Stack,
  TextField,
  Typography,
} from '@mui/material';

const PREVIEW_MODES = [
  ['overlay', 'Đánh dấu'],
  ['mask', 'Hình dạng'],
  ['labels', 'Đánh số'],
];

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
}) => (
  <Card sx={{ height: '100%' }}>
    <CardContent sx={{ p: 2.5 }}>
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 2, mb: 2 }}>
        <Box>
          <Typography variant="h6" fontWeight={700}>Hình ảnh hiển thị</Typography>
          <Typography variant="body2" color="text.secondary">
            Xem trước ảnh chụp từ camera hoặc tệp ảnh tải lên để phân tích kích thước hạt.
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
);
