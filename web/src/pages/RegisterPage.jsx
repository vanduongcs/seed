import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import {
  Box, Button, TextField, Typography,
  InputAdornment, IconButton, Alert, CircularProgress,
} from '@mui/material';
import { Email, Lock, Person, Visibility, VisibilityOff } from '@mui/icons-material';
import { useAuthStore } from '@/store/auth.store.js';
import { api } from '@/api/axios.js';
import { syncGuestRuns } from '@/utils/guestRuns.js';

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

    // Client-side simple validations
    if (form.name.trim().length < 2) {
      setError('Họ và tên ít nhất phải có 2 ký tự');
      setLoading(false);
      return;
    }

    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(form.email)) {
      setError('Định dạng email không hợp lệ');
      setLoading(false);
      return;
    }

    try {
      const { data } = await api.post('/auth/register', form);
      setAuth(data.data.user, data.data.accessToken, data.data.refreshToken);
      await syncGuestRuns(data.data.user?._id || data.data.user?.id).catch(() => {});
      navigate('/dashboard');
    } catch (err) {
      setError(err.response?.data?.message || 'Đăng ký thất bại. Vui lòng thử lại.');
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
      bgcolor: '#F5F7F5',
      backgroundImage: 'radial-gradient(circle at 50% 50%, #FCFDFC 0%, #E6ECE6 100%)',
      position: 'relative',
      overflow: 'hidden',
      px: 2.5,
      py: 6,
    }}>
      {/* Decorative ultra-thin grid background overlay */}
      <Box sx={{
        position: 'absolute',
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        backgroundImage: 'linear-gradient(rgba(47, 107, 79, 0.018) 1px, transparent 1px), linear-gradient(90deg, rgba(47, 107, 79, 0.018) 1px, transparent 1px)',
        backgroundSize: '40px 40px',
        pointerEvents: 'none',
      }} />

      {/* Floating premium glassmorphic card */}
      <Box sx={{
        width: '100%',
        maxWidth: 430,
        bgcolor: 'rgba(255, 255, 255, 0.85)',
        backdropFilter: 'blur(16px)',
        border: '1px solid rgba(47, 107, 79, 0.12)',
        borderRadius: '24px',
        p: { xs: 4, sm: 5 },
        boxShadow: '0 24px 60px rgba(0, 0, 0, 0.06), 0 1px 1px rgba(0, 0, 0, 0.03)',
        zIndex: 1,
      }}>
        {/* Elegant Sprout/Seed Brand Logo */}
        <Box sx={{ display: 'flex', justifyContent: 'center', mb: 3.5 }}>
          <Box sx={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            width: 52,
            height: 52,
            borderRadius: '14px',
            bgcolor: 'rgba(47, 107, 79, 0.05)',
            border: '1px solid rgba(47, 107, 79, 0.12)',
            boxShadow: '0 2px 8px rgba(47, 107, 79, 0.04)',
          }}>
            <svg width="26" height="26" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
              <path d="M12 2C12 2 12.5 6.5 16.5 7.5C19.5 8.25 21 11 21 14C21 18 17.5 21 12 21C6.5 21 3 18 3 14C3 11 4.5 8.25 7.5 7.5C11.5 6.5 12 2 12 2Z" stroke="#2F6B4F" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
              <path d="M12 7.5V21" stroke="#2F6B4F" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
              <path d="M12 12C9.5 13 8 15 8 17" stroke="#2F6B4F" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
              <path d="M12 10.5C14.5 11.5 16 13.5 16 15.5" stroke="#2F6B4F" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
            </svg>
          </Box>
        </Box>

        {/* Header - Only "Đăng ký" as requested */}
        <Typography variant="h4" fontWeight={850} sx={{ color: '#1B2C21', letterSpacing: '-0.8px', mb: 4, textAlign: 'center' }}>
          Đăng ký
        </Typography>

        {error && (
          <Alert severity="error" variant="outlined" sx={{
            mb: 3,
            borderRadius: '10px',
            border: '1px solid rgba(240, 68, 56, 0.3)',
            bgcolor: 'rgba(240, 68, 56, 0.02)',
            color: '#B42318',
            '& .MuiAlert-icon': { color: '#D92D20' }
          }}>
            {error}
          </Alert>
        )}

        <Box component="form" autoComplete="off" onSubmit={handleSubmit} sx={{ display: 'flex', flexDirection: 'column', gap: 2.8 }}>
          {/* Name field */}
          <Box>
            <Typography variant="body2" fontWeight={600} sx={{ color: '#4D5C52', mb: 0.9, fontSize: '0.88rem', letterSpacing: '0.3px' }}>HỌ VÀ TÊN</Typography>
            <TextField
              id="register-name"
              name="name"
              type="text"
              autoComplete="off"
              placeholder="Nhập họ và tên của bạn"
              value={form.name}
              onChange={handleChange}
              required
              fullWidth
              InputProps={{
                startAdornment: (
                  <InputAdornment position="start">
                    <Person sx={{ color: '#6B7C72', fontSize: 19 }} />
                  </InputAdornment>
                ),
                sx: {
                  height: '48px',
                  color: '#1B2C21',
                  bgcolor: '#F8FAF8',
                  '& fieldset': { borderColor: 'rgba(47, 107, 79, 0.12)', borderRadius: '10px' },
                  '&:hover fieldset': { borderColor: 'rgba(47, 107, 79, 0.3)' },
                  '&.Mui-focused fieldset': { borderColor: '#2F6B4F', borderWidth: '1.5px' },
                  '&.Mui-focused': { boxShadow: '0 0 10px rgba(47, 107, 79, 0.08)' }
                }
              }}
            />
          </Box>

          {/* Email field */}
          <Box>
            <Typography variant="body2" fontWeight={600} sx={{ color: '#4D5C52', mb: 0.9, fontSize: '0.88rem', letterSpacing: '0.3px' }}>ĐỊA CHỈ EMAIL</Typography>
            <TextField
              id="register-email"
              name="email"
              type="email"
              autoComplete="off"
              placeholder="email@example.com"
              value={form.email}
              onChange={handleChange}
              required
              fullWidth
              InputProps={{
                startAdornment: (
                  <InputAdornment position="start">
                    <Email sx={{ color: '#6B7C72', fontSize: 19 }} />
                  </InputAdornment>
                ),
                sx: {
                  height: '48px',
                  color: '#1B2C21',
                  bgcolor: '#F8FAF8',
                  '& fieldset': { borderColor: 'rgba(47, 107, 79, 0.12)', borderRadius: '10px' },
                  '&:hover fieldset': { borderColor: 'rgba(47, 107, 79, 0.3)' },
                  '&.Mui-focused fieldset': { borderColor: '#2F6B4F', borderWidth: '1.5px' },
                  '&.Mui-focused': { boxShadow: '0 0 10px rgba(47, 107, 79, 0.08)' }
                }
              }}
            />
          </Box>

          {/* Password field */}
          <Box>
            <Typography variant="body2" fontWeight={600} sx={{ color: '#4D5C52', mb: 0.9, fontSize: '0.88rem', letterSpacing: '0.3px' }}>MẬT KHẨU</Typography>
            <TextField
              id="register-password"
              name="password"
              placeholder="Nhập mật khẩu"
              autoComplete="new-password"
              type={showPass ? 'text' : 'password'}
              value={form.password}
              onChange={handleChange}
              required
              fullWidth
              InputProps={{
                startAdornment: (
                  <InputAdornment position="start">
                    <Lock sx={{ color: '#6B7C72', fontSize: 19 }} />
                  </InputAdornment>
                ),
                endAdornment: (
                  <InputAdornment position="end">
                    <IconButton size="small" onClick={() => setShowPass(!showPass)} edge="end" sx={{ color: '#6B7C72' }}>
                      {showPass ? <VisibilityOff sx={{ fontSize: 19 }} /> : <Visibility sx={{ fontSize: 19 }} />}
                    </IconButton>
                  </InputAdornment>
                ),
                sx: {
                  height: '48px',
                  color: '#1B2C21',
                  bgcolor: '#F8FAF8',
                  '& fieldset': { borderColor: 'rgba(47, 107, 79, 0.12)', borderRadius: '10px' },
                  '&:hover fieldset': { borderColor: 'rgba(47, 107, 79, 0.3)' },
                  '&.Mui-focused fieldset': { borderColor: '#2F6B4F', borderWidth: '1.5px' },
                  '&.Mui-focused': { boxShadow: '0 0 10px rgba(47, 107, 79, 0.08)' }
                }
              }}
            />
          </Box>

          {/* Submit Button */}
          <Button
            id="register-submit"
            type="submit"
            variant="contained"
            fullWidth
            disabled={loading}
            sx={{
              mt: 1.5,
              height: '48px',
              borderRadius: '10px',
              backgroundColor: '#2F6B4F',
              fontSize: '0.98rem',
              fontWeight: 700,
              color: '#FFFFFF',
              boxShadow: '0 4px 12px rgba(47, 107, 79, 0.2)',
              textTransform: 'none',
              transition: 'all 0.2s ease-in-out',
              '&:hover': {
                backgroundColor: '#1E4633',
                boxShadow: '0 6px 16px rgba(47, 107, 79, 0.3)',
                transform: 'translateY(-1px)',
              },
              '&:active': {
                transform: 'translateY(0)',
              },
              '&.Mui-disabled': {
                backgroundColor: 'rgba(47, 107, 79, 0.2)',
                color: 'rgba(255, 255, 255, 0.6)'
              }
            }}
          >
            {loading ? <CircularProgress size={22} sx={{ color: '#FFFFFF' }} /> : 'Đăng ký'}
          </Button>
        </Box>

        <Typography variant="body2" align="center" mt={4} sx={{ color: '#6B7C72' }}>
          Đã có tài khoản?{' '}
          <Link to="/login" style={{ color: '#2F6B4F', textDecoration: 'none', fontWeight: 700, marginLeft: '4px' }}>
            Đăng nhập ngay
          </Link>
        </Typography>
      </Box>
    </Box>
  );
}
