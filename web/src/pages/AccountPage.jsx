import { useState } from 'react';
import {
  Box, Typography, Card, CardContent, Grid, TextField,
  Button, Dialog, DialogTitle, DialogContent, DialogActions,
} from '@mui/material';
import { useAuthStore } from '@/store/auth.store.js';

export default function AccountPage() {
  const user = useAuthStore((s) => s.user);
  const [settingsOpen, setSettingsOpen] = useState(false);

  return (
    <Box sx={{ maxWidth: 760 }}>
      <Typography variant="h5" fontWeight={700} mb={0.75}>Tài khoản</Typography>
      <Typography variant="body2" color="text.secondary" mb={2.5}>
        Thông tin người dùng và cấu hình website.
      </Typography>

      <Card>
        <CardContent sx={{ p: 3 }}>
          <Grid container spacing={2}>
            <Grid item xs={12} sm={6}>
              <TextField label="Họ và tên" defaultValue={user?.name || ''} fullWidth />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField label="Email" defaultValue={user?.email || ''} fullWidth disabled />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField label="Vai trò" defaultValue={user?.role || 'user'} fullWidth disabled />
            </Grid>
            <Grid item xs={12} display="flex" gap={1}>
              <Button variant="contained">Lưu thay đổi</Button>
              <Button variant="outlined" onClick={() => setSettingsOpen(true)}>Cài đặt</Button>
            </Grid>
          </Grid>
        </CardContent>
      </Card>

      <Dialog open={settingsOpen} onClose={() => setSettingsOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>Cài đặt website</DialogTitle>
        <DialogContent>
          <Typography variant="body2" color="text.secondary">
            Các tùy chọn hiển thị, đơn vị đo và cấu hình xử lý sẽ được đặt tại đây.
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setSettingsOpen(false)}>Đóng</Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
