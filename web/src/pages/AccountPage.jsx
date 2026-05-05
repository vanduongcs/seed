import { useState } from 'react';
import {
  Box, Typography, Card, CardContent, Grid, TextField,
  Button, Dialog, DialogTitle, DialogContent, DialogActions,
  FormControlLabel, Switch, Divider, MenuItem,
} from '@mui/material';
import { useAuthStore } from '@/store/auth.store.js';

export default function AccountPage() {
  const user = useAuthStore((s) => s.user);
  const [settingsOpen, setSettingsOpen] = useState(false);

  return (
    <Box sx={{ maxWidth: 860 }}>
      <Typography variant="h5" fontWeight={700} mb={0.75}>Tài khoản</Typography>
      <Typography variant="body2" color="text.secondary" mb={2.5}>
        Quản lý thông tin người dùng và cấu hình thao tác trên website.
      </Typography>

      <Card>
        <CardContent sx={{ p: 3 }}>
          <Typography variant="h6" fontWeight={700} mb={2}>Thông tin tài khoản</Typography>
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
            <Grid item xs={12} sm={6}>
              <TextField label="Đơn vị/Phòng ban" defaultValue="Phòng thí nghiệm hạt giống" fullWidth />
            </Grid>
            <Grid item xs={12} display="flex" gap={1} flexWrap="wrap">
              <Button variant="contained">Lưu thay đổi</Button>
              <Button variant="outlined" onClick={() => setSettingsOpen(true)}>Cài đặt</Button>
            </Grid>
          </Grid>
        </CardContent>
      </Card>

      <Dialog open={settingsOpen} onClose={() => setSettingsOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>Cài đặt website</DialogTitle>
        <DialogContent>
          <Box sx={{ pt: 1 }}>
            <TextField select label="Đơn vị đo mặc định" defaultValue="mm" fullWidth sx={{ mb: 2 }}>
              <MenuItem value="mm">Milimét (mm)</MenuItem>
              <MenuItem value="cm">Centimét (cm)</MenuItem>
            </TextField>
            <TextField select label="Chế độ lưu ảnh" defaultValue="processed" fullWidth sx={{ mb: 2 }}>
              <MenuItem value="processed">Lưu ảnh đã xử lý</MenuItem>
              <MenuItem value="original">Lưu ảnh gốc</MenuItem>
              <MenuItem value="both">Lưu cả hai</MenuItem>
            </TextField>
            <Divider sx={{ my: 1.5 }} />
            <FormControlLabel control={<Switch defaultChecked />} label="Tự động lưu kết quả sau xử lý" />
            <FormControlLabel control={<Switch />} label="Hiển thị lưới tham chiếu khi xem ảnh" />
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setSettingsOpen(false)}>Hủy</Button>
          <Button variant="contained" onClick={() => setSettingsOpen(false)}>Lưu cài đặt</Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
