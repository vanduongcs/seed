import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import {
  Box, Button, TextField, Typography, Card, CardContent,
  InputAdornment, IconButton, Alert, CircularProgress, alpha,
} from '@mui/material';
import {
  Email, Lock, Visibility, VisibilityOff, AutoAwesome,
} from '@mui/icons-material';
import { useAuthStore } from '@/store/auth.store.js';
import { api } from '@/api/axios.js';

export default function LoginPage() {
  const navigate = useNavigate();
  const setAuth = useAuthStore((s) => s.setAuth);

  const [form, setForm] = useState({ email: '', password: '' });
  const [showPass, setShowPass] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleChange = (e) => setForm({ ...form, [e.target.name]: e.target.value });

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError('');
    try {
      const { data } = await api.post('/auth/login', form);
      setAuth(data.data.user, data.data.accessToken, data.data.refreshToken);
      navigate('/dashboard');
    } catch (err) {
      setError(err.response?.data?.message || 'Đăng nhập thất bại');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Box sx={{
      minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center',
      bgcolor: 'background.default', position: 'relative', overflow: 'hidden',
    }}>
      {/* Background glow */}
      <Box sx={{ position: 'absolute', width: 500, height: 500, borderRadius: '50%', top: '10%', left: '50%', transform: 'translateX(-50%)', background: 'radial-gradient(circle, rgba(124,58,237,0.15) 0%, transparent 70%)', pointerEvents: 'none' }} />

      <Card sx={{ width: '100%', maxWidth: 420, mx: 2, bgcolor: alpha('#111118', 0.95), backdropFilter: 'blur(20px)' }}>
        <CardContent sx={{ p: 4 }}>
          {/* Logo */}
          <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', mb: 4 }}>
            <Box sx={{
              width: 56, height: 56, borderRadius: 3, mb: 2,
              background: 'linear-gradient(135deg, #7C3AED, #06B6D4)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              boxShadow: '0 0 30px rgba(124,58,237,0.4)',
            }}>
              <AutoAwesome sx={{ color: '#fff', fontSize: 28 }} />
            </Box>
            <Typography variant="h5" fontWeight={700}>Chào mừng trở lại</Typography>
            <Typography variant="body2" color="text.secondary" mt={0.5}>Đăng nhập vào tài khoản của bạn</Typography>
          </Box>

          {error && <Alert severity="error" sx={{ mb: 2, borderRadius: 2 }}>{error}</Alert>}

          <Box component="form" onSubmit={handleSubmit} sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            <TextField
              id="login-email" name="email" label="Email" type="email"
              value={form.email} onChange={handleChange} required fullWidth
              InputProps={{ startAdornment: <InputAdornment position="start"><Email sx={{ color: 'text.secondary', fontSize: 18 }} /></InputAdornment> }}
            />
            <TextField
              id="login-password" name="password" label="Mật khẩu"
              type={showPass ? 'text' : 'password'}
              value={form.password} onChange={handleChange} required fullWidth
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

            <Button id="login-submit" type="submit" variant="contained" fullWidth size="large"
              disabled={loading} sx={{ mt: 1, py: 1.4 }}>
              {loading ? <CircularProgress size={22} color="inherit" /> : 'Đăng nhập'}
            </Button>
          </Box>

          <Typography variant="body2" align="center" mt={3} color="text.secondary">
            Chưa có tài khoản?{' '}
            <Link to="/register" style={{ color: '#A78BFA', textDecoration: 'none', fontWeight: 600 }}>
              Đăng ký ngay
            </Link>
          </Typography>
        </CardContent>
      </Card>
    </Box>
  );
}
