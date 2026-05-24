import { useState } from 'react';
import { Alert, Box, Button, Card, CardContent, Divider, Stack, Typography, Collapse } from '@mui/material';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import ExpandLessIcon from '@mui/icons-material/ExpandLess';

import { formatAnalysisMethod, formatMeasure, formatNumber } from './format.js';
import { ResultRow } from './ResultRow.jsx';

export const DashboardResultPanel = ({
  calibrationMm,
  calibrationPixels,
  calibrationReady,
  result,
  onDownloadCsv,
  onDownloadPng,
}) => {
  const [showAdvanced, setShowAdvanced] = useState(false);

  // Format decimal confidence/iou values into clean percentages
  const formatPercent = (val) => {
    const num = Number(val);
    return Number.isFinite(num) && num > 0 ? `${(num * 100).toFixed(0)}%` : '-';
  };

  return (
    <Stack spacing={2}>
      <Card>
        <CardContent sx={{ p: 2.5 }}>
          <Typography variant="h6" fontWeight={700} mb={0.5}>Thông số tham chiếu</Typography>
          <Box mb={2} />

          <Stack spacing={1.25}>
            <ResultRow label="Đơn vị đo" value={calibrationReady ? 'Milimét (mm)' : 'Điểm ảnh (px)'} />
            <ResultRow
              label="Tỷ lệ thước đo"
              value={calibrationReady ? `${calibrationPixels.toFixed(1)} px = ${calibrationMm} mm` : 'Chưa thiết lập'}
            />
          </Stack>
        </CardContent>
      </Card>

      <Card>
        <CardContent sx={{ p: 2.5 }}>
          <Typography variant="h6" fontWeight={700} mb={0.5}>Kết quả phân tích</Typography>
          <Box mb={2} />

          {result ? (
            <Stack spacing={1.2}>
              <ResultRow label="Mã lần quét" value={result.run?.id ? result.run.id.slice(-8).toUpperCase() : '-'} />
              <ResultRow label="Tổng số hạt đo được" value={result.segmentation?.segment_count ?? result.summary?.count ?? '-'} />
              {(result.summary?.qc?.suspect_count ?? 0) > 0 && (
                <Alert severity="warning">
                  QC phát hiện {result.summary.qc.suspect_count} vùng nghi nhiễu/outlier. {result.summary.qc.robust_used_for_reporting !== false ? `ĐLC báo cáo tính trên ${result.summary.qc.inlier_count} hạt sau QC.` : 'Tỷ lệ nghi ngờ cao; ĐLC báo cáo giữ nguyên SD thô, không tự loại vùng.'} Kiểm tra ảnh đánh số trước khi kết luận.
                  {result.summary.qc.suspect_ids?.length ? ` ID nghi ngờ: ${result.summary.qc.suspect_ids.slice(0, 8).map((id) => `#${id}`).join(', ')}${result.summary.qc.suspect_ids.length > 8 ? ', ...' : ''}.` : ''}
                </Alert>
              )}
              
              <Divider sx={{ my: 1 }} />
              
              <Button
                size="small"
                variant="text"
                endIcon={showAdvanced ? <ExpandLessIcon /> : <ExpandMoreIcon />}
                onClick={() => setShowAdvanced(!showAdvanced)}
                sx={{ alignSelf: 'flex-start', mb: 1, textTransform: 'none', color: 'text.secondary' }}
              >
                {showAdvanced ? 'Ẩn thông số kỹ thuật' : 'Hiển thị thông số kỹ thuật'}
              </Button>

              <Collapse in={showAdvanced}>
                <Stack spacing={1.2} sx={{ pl: 1.5, borderLeft: '2px solid', borderColor: 'divider', mb: 1.5 }}>
                  <ResultRow label="Phương thức phân tích" value={formatAnalysisMethod(result.segmentation)} />
                  <ResultRow label="Độ tin cậy nhận dạng" value={formatPercent(result.segmentation?.confidence)} />
                  <ResultRow label="Độ khớp mặt nạ (IoU)" value={formatPercent(result.segmentation?.iou)} />
                  <ResultRow label="Quét phân mảnh (Tiled)" value={result.segmentation?.tiled_inference ? 'Đang bật' : 'Đang tắt'} />
                  {result.segmentation?.tiled_inference && (
                    <ResultRow
                      label="Kích thước ô quét / Độ đè"
                      value={`${result.segmentation?.tile_size ?? '-'} px / ${formatPercent(result.segmentation?.tile_overlap)}`}
                    />
                  )}
                  <ResultRow
                    label="Vật mốc đã loại khỏi thống kê"
                    value={String(result.segmentation?.mask_filter?.excluded_reference_object_count ?? 0)}
                  />
                  <ResultRow
                    label="ĐLC dài thô / sau QC"
                    value={`${formatMeasure(result.summary?.std_length_mm, 'mm', result.summary?.std_length_px, 'px')} / ${formatMeasure(result.summary?.robust_std_length_mm, 'mm', result.summary?.robust_std_length_px, 'px')}`}
                  />
                  <ResultRow
                    label="ĐLC rộng thô / sau QC"
                    value={`${formatMeasure(result.summary?.std_width_mm, 'mm', result.summary?.std_width_px, 'px')} / ${formatMeasure(result.summary?.robust_std_width_mm, 'mm', result.summary?.robust_std_width_px, 'px')}`}
                  />
                  <ResultRow label="Vùng nghi nhiễu (QC)" value={String(result.summary?.qc?.suspect_count ?? 0)} />
                </Stack>
              </Collapse>

              <Divider />
              <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1} pt={1}>
                <Button variant="contained" onClick={onDownloadCsv}>
                  Xuất CSV
                </Button>
                <Button variant="outlined" onClick={onDownloadPng}>
                  Xuất ảnh kết quả
                </Button>
              </Stack>
            </Stack>
          ) : (
            <Alert severity="info">Chưa có kết quả. Vui lòng tải ảnh lên hoặc kết nối camera và bấm Chạy xử lý.</Alert>
          )}
        </CardContent>
      </Card>
    </Stack>
  );
};
