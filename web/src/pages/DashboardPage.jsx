import { useEffect, useRef, useState } from 'react';
import { Box, Grid } from '@mui/material';

import { api, ensureFreshAccessToken, publicApi } from '@/api/axios.js';
import { useAuthStore } from '@/store/auth.store.js';
import { DashboardPreviewPanel } from '@/components/grain/DashboardPreviewPanel.jsx';
import { DashboardResultPanel } from '@/components/grain/DashboardResultPanel.jsx';
import { formatMeasure, safeStem } from '@/components/grain/format.js';
import { StatCard } from '@/components/grain/StatCard.jsx';
import { saveGuestRun } from '@/utils/guestRuns.js';

const emptyCalibration = { start: null, end: null, referenceMm: '' };

export default function DashboardPage() {
  const isGuest = useAuthStore((state) => state.isGuest);
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
  const [calibration, setCalibration] = useState(emptyCalibration);
  const [drawingCalibration, setDrawingCalibration] = useState(false);
  const [progress, setProgress] = useState(0);
  const [progressPhase, setProgressPhase] = useState('');
  const progressTimerRef = useRef(null);

  useEffect(() => () => {
    if (videoRef.current?.srcObject) {
      videoRef.current.srcObject.getTracks().forEach((track) => track.stop());
    }
  }, []);

  const resetRunState = () => {
    setResult(null);
    setPreviewMode('overlay');
    setCalibration(emptyCalibration);
  };

  const handleCamera = async () => {
    setCameraError('');
    setProcessError('');
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: true });
      if (videoRef.current) videoRef.current.srcObject = stream;
      setImageFile(null);
      setPreviewUrl('');
      setFileName('camera-frame.png');
      setCameraActive(true);
      resetRunState();
    } catch {
      setCameraError('Không thể kết nối camera. Kiểm tra quyền truy cập hoặc thiết bị.');
    }
  };

  const handleFile = (event) => {
    const file = event.target.files?.[0];
    if (!file) return;

    setPreviewUrl('');
    setImageFile(file);
    setFileName(file.name);
    setCameraActive(false);
    setProcessError('');
    resetRunState();

    const reader = new FileReader();
    reader.onload = () => {
      setPreviewUrl(typeof reader.result === 'string' ? reader.result : '');
    };
    reader.onerror = () => {
      setPreviewUrl('');
      setProcessError('Không thể đọc ảnh đã chọn. Vui lòng thử ảnh JPG hoặc PNG khác.');
    };
    reader.readAsDataURL(file);

    event.target.value = '';
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
  const calibrationLineReady = calibrationPixels > 1;
  const calibrationReady = calibrationLineReady && Number.isFinite(calibrationMm) && calibrationMm > 0;

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
    setProgress(5);
    setProgressPhase('Chuẩn bị ảnh');

    const startProgressDrift = () => {
      if (progressTimerRef.current) clearInterval(progressTimerRef.current);
      progressTimerRef.current = setInterval(() => {
        setProgress((prev) => {
          if (prev < 90) return Math.min(90, prev + 2);
          return prev;
        });
      }, 700);
    };

    try {
      const file = await getImageForProcessing();
      if (!file) {
        setProcessError('Vui lòng import ảnh hoặc bật camera trước khi xử lý.');
        setProgress(0);
        setProgressPhase('');
        setProcessing(false);
        return;
      }

      setProgress(20);
      setProgressPhase(isGuest ? 'Chuẩn bị xử lý' : 'Xác thực phiên');
      if (!isGuest) await ensureFreshAccessToken(true);

      const formData = new FormData();
      formData.append('image', file);
      if (calibrationLineReady) {
        formData.append('referencePixels', String(calibrationPixels));
        formData.append('referencePixelSpace', 'original');
        formData.append('referenceX1', String(calibration.start.x));
        formData.append('referenceY1', String(calibration.start.y));
        formData.append('referenceX2', String(calibration.end.x));
        formData.append('referenceY2', String(calibration.end.y));
        if (calibrationReady) {
          formData.append('referenceMm', String(calibrationMm));
        }
      }

      setProgress(50);
      setProgressPhase('Phân tích ảnh bằng YOLO ONNX');
      startProgressDrift();

      const analysisApi = isGuest ? publicApi : api;
      const analysisPath = isGuest ? '/grain/analyze-public' : '/grain/analyze';
      const { data } = await analysisApi.post(analysisPath, formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
        timeout: 300000,
      });

      if (progressTimerRef.current) clearInterval(progressTimerRef.current);
      setProgress(96);
      setProgressPhase('Lưu kết quả');
      setResult(data.data);
      if (isGuest) {
        saveGuestRun({ result: data.data, sourceFileName: file.name });
      }
      setPreviewMode('overlay');
      setProgress(100);
      setProgressPhase('Hoàn tất');
    } catch (err) {
      if (progressTimerRef.current) clearInterval(progressTimerRef.current);
      setProgress(0);
      setProgressPhase('');
      setProcessError(resolveProcessError(err));
    } finally {
      if (progressTimerRef.current) clearInterval(progressTimerRef.current);
      setProcessing(false);
      setTimeout(() => {
        setProgress(0);
        setProgressPhase('');
      }, 500);
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
    mask: result?.mask_png_base64,
    labels: result?.labels_png_base64,
    preprocessed: result?.preprocessed_png_base64,
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
      label: 'Diện tích trung bình',
      value: summary ? formatMeasure(summary.mean_area_mm2, 'mm2', summary.mean_area_px, 'px') : '-',
      note: 'Từ contour từng hạt',
    },
    {
      label: 'Chiều dài trung bình',
      value: summary ? formatMeasure(summary.mean_length_mm, 'mm', summary.mean_length_px, 'px') : '-',
      note: 'Theo trục chính',
    },
    {
      label: 'Chiều rộng trung bình',
      value: summary ? formatMeasure(summary.mean_width_mm, 'mm', summary.mean_width_px, 'px') : '-',
      note: 'Theo trục phụ',
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
          <DashboardPreviewPanel
            cameraActive={cameraActive}
            cameraError={cameraError}
            calibration={calibration}
            calibrationImage={calibrationImage}
            calibrationPixels={calibrationPixels}
            calibrationReady={calibrationReady}
            displayImage={displayImage}
            drawingCalibration={drawingCalibration}
            fileName={fileName}
            imageRef={imageRef}
            previewMode={previewMode}
            previewUrl={previewUrl}
            processError={processError}
            processing={processing}
            result={result}
            videoRef={videoRef}
            onCamera={handleCamera}
            onFile={handleFile}
            onProcess={handleProcess}
            onCalibrationChange={setCalibration}
            onDrawingCalibrationChange={setDrawingCalibration}
            onPreviewModeChange={setPreviewMode}
            getCalibrationPoint={getCalibrationPoint}
            renderCalibrationOverlay={renderCalibrationOverlay}
            progress={progress}
            progressPhase={progressPhase}
          />
        </Grid>

        <Grid item xs={12} lg={5}>
          <DashboardResultPanel
            calibrationMm={calibrationMm}
            calibrationPixels={calibrationPixels}
            calibrationReady={calibrationReady}
            result={result}
            onDownloadCsv={downloadCsv}
            onDownloadPng={downloadPng}
          />
        </Grid>
      </Grid>
    </Box>
  );
}

const resolveProcessError = (err) => {
  if (err.response?.status === 401) {
    return 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại rồi chạy xử lý.';
  }

  const message = err.response?.data?.message;
  if (message) return message;
  if (err.code === 'ECONNABORTED') {
    return 'Xử lý quá lâu (quá 300 giây). Hãy thử ảnh nhỏ hơn hoặc kiểm tra backend/Python worker.';
  }
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
