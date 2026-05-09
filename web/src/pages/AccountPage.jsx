import { useEffect, useState } from 'react';
import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Divider,
  FormControlLabel,
  Grid,
  MenuItem,
  Switch,
  TextField,
  Typography,
} from '@mui/material';

import { api } from '@/api/axios.js';
import { useAuthStore } from '@/store/auth.store.js';

export default function AccountPage() {
  const user = useAuthStore((s) => s.user);
  const setUser = useAuthStore((s) => s.setUser);
  const [form, setForm] = useState({ name: user?.name || '', email: user?.email || '', role: user?.role || 'user' });
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    const loadProfile = async () => {
      setLoading(true);
      setError('');
      try {
        const { data } = await api.get('/users/me');
        const profile = data.data;
        setUser(profile);
        setForm({
          name: profile?.name || '',
          email: profile?.email || '',
          role: profile?.role || 'user',
        });
      } catch (err) {
        setError(err.response?.data?.message || 'Không tải được thông tin tài khoản');
      } finally {
        setLoading(false);
      }
    };

    loadProfile();
  }, [setUser]);

  const handleSave = async () => {
    setSaving(true);
    setMessage('');
    setError('');
    try {
      const { data } = await api.patch('/users/me', { name: form.name.trim() });
      setUser(data.data);
      setForm((current) => ({ ...current, name: data.data.name || current.name }));
      setMessage('Đã cập nhật tài khoản');
    } catch (err) {
      setError(err.response?.data?.message || 'Cập nhật tài khoản thất bại');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Box sx={{ maxWidth: 860 }}>
      <Typography variant="h5" fontWeight={700} mb={0.75}>Tài khoản</Typography>
      <Typography variant="body2" color="text.secondary" mb={2.5}>
        Thông tin người dùng được đọc và cập nhật qua backend, dùng chung cho web và mobile.
      </Typography>

      {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}
      {message && <Alert severity="success" sx={{ mb: 2 }}>{message}</Alert>}

      <Card>
        <CardContent sx={{ p: 3 }}>
          <Typography variant="h6" fontWeight={700} mb={2}>Thông tin tài khoản</Typography>
          {loading ? (
            <Box sx={{ py: 5, display: 'grid', placeItems: 'center' }}>
              <CircularProgress size={30} />
            </Box>
          ) : (
            <Grid container spacing={2}>
              <Grid item xs={12} sm={6}>
                <TextField
                  label="Họ và tên"
                  value={form.name}
                  onChange={(event) => setForm((current) => ({ ...current, name: event.target.value }))}
                  fullWidth
                />
              </Grid>
              <Grid item xs={12} sm={6}>
                <TextField label="Email" value={form.email} fullWidth disabled />
              </Grid>
              <Grid item xs={12} sm={6}>
                <TextField label="Vai trò" value={form.role} fullWidth disabled />
              </Grid>
              <Grid item xs={12} sm={6}>
                <TextField label="Đơn vị đo mặc định" value="Milimét (mm)" fullWidth disabled />
              </Grid>
              <Grid item xs={12} display="flex" gap={1} flexWrap="wrap">
                <Button variant="contained" onClick={handleSave} disabled={saving || form.name.trim().length < 2}>
                  {saving ? 'Đang lưu...' : 'Lưu thay đổi'}
                </Button>
                <Button variant="outlined" onClick={() => setSettingsOpen(true)}>Cài đặt</Button>
              </Grid>
            </Grid>
          )}
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
