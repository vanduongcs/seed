import { useState } from 'react';
import { Outlet, useNavigate, useLocation } from 'react-router-dom';
import {
  AppBar, Box, Drawer, IconButton, List, ListItem,
  ListItemButton, ListItemIcon, ListItemText, Toolbar,
  Typography, Avatar, Tooltip, Divider, alpha,
} from '@mui/material';
import {
  Menu as MenuIcon,
  DashboardOutlined as DashboardIcon,
  Inventory2Outlined as StorageIcon,
  AccountCircleOutlined as AccountIcon,
  Logout as LogoutIcon,
  Agriculture as SeedIcon,
} from '@mui/icons-material';
import { api } from '@/api/axios.js';
import { useAuthStore } from '@/store/auth.store.js';

const DRAWER_WIDTH = 260;

const navItems = [
  { label: 'Trang chủ', icon: <DashboardIcon />, path: '/dashboard' },
  { label: 'Lưu trữ', icon: <StorageIcon />, path: '/storage' },
  { label: 'Tài khoản', icon: <AccountIcon />, path: '/account' },
];

export default function Layout() {
  const [mobileOpen, setMobileOpen] = useState(false);
  const { user, logout } = useAuthStore();
  const navigate = useNavigate();
  const location = useLocation();

  const handleLogout = async () => {
    try {
      await api.post('/auth/logout');
    } catch {
      // Local logout should still complete if the token is already expired.
    } finally {
      logout();
      navigate('/login');
    }
  };

  const drawer = (
    <Box sx={{ height: '100%', display: 'flex', flexDirection: 'column', bgcolor: 'background.paper' }}>
      <Box sx={{ p: 2.5, display: 'flex', alignItems: 'center', gap: 1.5 }}>
        <Box sx={{
          width: 36,
          height: 36,
          borderRadius: 1.5,
          bgcolor: (t) => alpha(t.palette.primary.main, 0.1),
          border: '1px solid',
          borderColor: (t) => alpha(t.palette.primary.main, 0.24),
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}>
          <SeedIcon sx={{ color: 'primary.main', fontSize: 20 }} />
        </Box>
        <Box minWidth={0}>
          <Typography variant="h6" fontWeight={700} lineHeight={1.1}>Seed</Typography>
          <Typography variant="caption" color="text.secondary">Đo hình thái hạt</Typography>
        </Box>
      </Box>

      <Divider />

      <List sx={{ px: 1.5, pt: 1.5, flex: 1 }}>
        {navItems.map((item) => {
          const active = location.pathname.startsWith(item.path);
          return (
            <ListItem key={item.path} disablePadding sx={{ mb: 0.5 }}>
              <ListItemButton
                onClick={() => navigate(item.path)}
                sx={{
                  borderRadius: 1,
                  py: 1.1,
                  bgcolor: active ? (t) => alpha(t.palette.primary.main, 0.1) : 'transparent',
                  color: active ? 'primary.dark' : 'text.secondary',
                  '&:hover': { bgcolor: (t) => alpha(t.palette.primary.main, 0.08), color: 'primary.dark' },
                }}
              >
                <ListItemIcon sx={{ minWidth: 38, color: 'inherit' }}>{item.icon}</ListItemIcon>
                <ListItemText primary={item.label} primaryTypographyProps={{ fontWeight: active ? 650 : 500 }} />
              </ListItemButton>
            </ListItem>
          );
        })}
      </List>

      <Divider />
      <Box sx={{ p: 2, display: 'flex', alignItems: 'center', gap: 1.5 }}>
        <Avatar sx={{ width: 36, height: 36, bgcolor: 'secondary.main', fontSize: 14 }}>
          {user?.name?.[0]?.toUpperCase() || 'U'}
        </Avatar>
        <Box flex={1} minWidth={0}>
          <Typography variant="body2" fontWeight={650} noWrap>{user?.name}</Typography>
          <Typography variant="caption" color="text.secondary" noWrap>{user?.email}</Typography>
        </Box>
        <Tooltip title="Đăng xuất">
          <IconButton size="small" onClick={handleLogout} sx={{ color: 'text.secondary', '&:hover': { color: 'error.main' } }}>
            <LogoutIcon fontSize="small" />
          </IconButton>
        </Tooltip>
      </Box>
    </Box>
  );

  return (
    <Box sx={{ display: 'flex', minHeight: '100vh' }}>
      <AppBar position="fixed" sx={{ display: { md: 'none' }, zIndex: (t) => t.zIndex.drawer + 1 }}>
        <Toolbar>
          <IconButton color="inherit" onClick={() => setMobileOpen(!mobileOpen)}><MenuIcon /></IconButton>
          <Typography variant="h6" fontWeight={700} ml={1}>Seed</Typography>
        </Toolbar>
      </AppBar>

      <Box component="nav" sx={{ width: { md: DRAWER_WIDTH }, flexShrink: { md: 0 } }}>
        <Drawer variant="temporary" open={mobileOpen} onClose={() => setMobileOpen(false)}
          sx={{ display: { xs: 'block', md: 'none' }, '& .MuiDrawer-paper': { width: DRAWER_WIDTH, boxSizing: 'border-box', border: 'none' } }}>
          {drawer}
        </Drawer>
        <Drawer variant="permanent"
          sx={{ display: { xs: 'none', md: 'block' }, '& .MuiDrawer-paper': { width: DRAWER_WIDTH, boxSizing: 'border-box', border: 'none', borderRight: '1px solid', borderColor: 'divider' } }}>
          {drawer}
        </Drawer>
      </Box>

      <Box component="main" sx={{ flexGrow: 1, p: { xs: 2, md: 3 }, mt: { xs: 8, md: 0 }, minHeight: '100vh', bgcolor: 'background.default' }}>
        <Outlet />
      </Box>
    </Box>
  );
}
