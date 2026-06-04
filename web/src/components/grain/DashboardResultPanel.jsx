import { Alert, Box, Button, Card, CardContent, Divider, Stack, Typography } from '@mui/material';

import { ResultRow } from './ResultRow.jsx';

export const DashboardResultPanel = ({
  calibrationMm,
  calibrationPixels,
  calibrationReady,
  result,
  onDownloadCsv,
  onDownloadPng,
}) => {
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

      {result && (
        <Card>
          <CardContent sx={{ p: 2.5 }}>
            <Typography variant="h6" fontWeight={700} mb={0.5}>Kết quả phân tích</Typography>
            <Box mb={2} />

            <Stack spacing={1.2}>
              <ResultRow label="Mã lần quét" value={result.run?.id ? result.run.id.slice(-8).toUpperCase() : '-'} />
              <ResultRow label="Tổng số hạt đo được" value={result.segmentation?.segment_count ?? result.summary?.count ?? '-'} />
              {(result.summary?.qc?.suspect_count ?? 0) > 0 && (
                <Alert severity="warning">
                  Hệ thống đang nghi {result.summary.qc.suspect_count} hạt có thể bị tách vùng ảnh sai hoặc có kích thước bất thường. {result.summary.qc.robust_used_for_reporting !== false ? `Độ lệch chuẩn báo cáo được tính trên ${result.summary.qc.inlier_count} hạt hợp lệ sau kiểm tra.` : 'Tỷ lệ hạt nghi ngờ cao, nên hệ thống giữ độ lệch chuẩn thô và cần người dùng xem lại ảnh.'} Có thể dùng nút "Chỉnh hạt nghi ngờ" ở khung ảnh để sửa thủ công.
                  {result.summary.qc.suspect_ids?.length ? ` ID hạt nghi ngờ: ${result.summary.qc.suspect_ids.slice(0, 8).map((id) => `#${id}`).join(', ')}${result.summary.qc.suspect_ids.length > 8 ? ', ...' : ''}.` : ''}
                </Alert>
              )}

              <Divider sx={{ my: 1 }} />

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
          </CardContent>
        </Card>
      )}
    </Stack>
  );
};
