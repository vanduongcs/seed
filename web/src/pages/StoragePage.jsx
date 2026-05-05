import { Box, Typography, Card, CardContent } from '@mui/material';

export default function StoragePage() {
  return (
    <Box sx={{ maxWidth: 1120 }}>
      <Typography variant="h5" fontWeight={700} mb={0.75}>Lưu trữ</Typography>
      <Typography variant="body2" color="text.secondary" mb={2.5}>
        Danh sách các lần xử lý mẫu sẽ hiển thị tại đây.
      </Typography>

      <Card>
        <CardContent sx={{ p: 3 }}>
          <Typography variant="body2" color="text.secondary">
            Chưa có dữ liệu lưu trữ.
          </Typography>
        </CardContent>
      </Card>
    </Box>
  );
}
