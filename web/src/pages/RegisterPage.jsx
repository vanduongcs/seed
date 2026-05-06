import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import {
  Box, Button, TextField, Typography, Card, CardContent,
  InputAdornment, IconButton, Alert, CircularProgress, alpha,
} from '@mui/material';
import { Email, Lock, Person, Visibility, VisibilityOff, Agriculture } from '@mui/icons-material';
import { useAuthStore } from '@/store/auth.store.js';
import { api } from '@/api/axios.js';

export default function RegisterPage() {
  const navigate = useNavigate();
  const setAuth = useAuthStore((s) => s.setAuth);

  const [form, setForm] = useState({ name: '', email: '', password: '' });
  const [showPass, setShowPass] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleChange = (e) => setForm({ ...form, [e.target.name]: e.target.value });

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError('');
    try {
      const { data } = await api.post('/auth/register', form);
      setAuth(data.data.user, data.data.accessToken, data.data.refreshToken);
      navigate('/dashboard');
    } catch (err) {
      setError(err.response?.data?.message || 'Đăng ký thất bại');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Box sx={{
      minHeight: '100vh',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      bgcolor: 'background.default',
      px: 2,
    }}>
      <Card sx={{ width: '100%', maxWidth: 420 }}>
        <CardContent sx={{ p: 4 }}>
          <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', mb: 3.5 }}>
            <Box sx={{
              width: 52,
              height: 52,
              borderRadius: 1.5,
              mb: 2,
              bgcolor: (t) => alpha(t.palette.primary.main, 0.1),
              border: '1px solid',
              borderColor: (t) => alpha(t.palette.primary.main, 0.24),
              color: 'primary.main',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}>
              <Agriculture sx={{ fontSize: 28 }} />
            </Box>
            <Typography variant="h5" fontWeight={700}>Tạo tài khoản</Typography>
            <Typography variant="body2" color="text.secondary" mt={0.5}>Dành cho người vận hành đo mẫu</Typography>
          </Box>

          {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}

          <Box component="form" onSubmit={handleSubmit} sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            <TextField
              id="register-name" name="name" label="Họ và tên"
              value={form.name} onChange={handleChange} required fullWidth
              InputProps={{ startAdornment: <InputAdornment position="start"><Person sx={{ color: 'text.secondary', fontSize: 18 }} /></InputAdornment> }}
            />
            <TextField
              id="register-email" name="email" label="Email" type="email"
              value={form.email} onChange={handleChange} required fullWidth
              InputProps={{ startAdornment: <InputAdornment position="start"><Email sx={{ color: 'text.secondary', fontSize: 18 }} /></InputAdornment> }}
            />
            <TextField
              id="register-password" name="password" label="Mật khẩu"
              type={showPass ? 'text' : 'password'}
              value={form.password} onChange={handleChange} required fullWidth
              helperText="Có thể dùng mật khẩu đơn giản"
              InputProps={{
                startAdornment: <InputAdornment position="start"><Lock sx={{ color: 'text.secondary', fontSize: 18 }} /></InputAdornment>,
                endAdornment: (
                  <InputAdornment position="end">
                    <IconButton size="small" onClick={() => setShowPass(!showPass)} edge="end">
                      {showPass ? <VisibilityOff fontSize="small" /> : <Visibility fontSize="small" />}
                    </IconButton>
                  </InputAdornment>
                ),
              }}
            />
            <Button id="register-submit" type="submit" variant="contained" fullWidth size="large"
              disabled={loading} sx={{ mt: 1, py: 1.3 }}>
              {loading ? <CircularProgress size={22} color="inherit" /> : 'Đăng ký'}
            </Button>
          </Box>

          <Typography variant="body2" align="center" mt={3} color="text.secondary">
            Đã có tài khoản?{' '}
            <Link to="/login" style={{ color: '#2F6B4F', textDecoration: 'none', fontWeight: 600 }}>Đăng nhập</Link>
          </Typography>
        </CardContent>
      </Card>
    </Box>
  );
}
