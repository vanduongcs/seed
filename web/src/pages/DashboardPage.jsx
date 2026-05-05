import { useNavigate } from 'react-router-dom';
import {
  Box, Typography, Grid, Card, CardContent, Button,
  Avatar, Chip, alpha,
} from '@mui/material';
import {
  Chat as ChatIcon, TrendingUp, AutoAwesome, ArrowForward,
} from '@mui/icons-material';
import { useAuthStore } from '@/store/auth.store.js';

const StatCard = ({ label, value, color }) => (
  <Card sx={{ height: '100%' }}>
    <CardContent sx={{ p: 3 }}>
      <Typography variant="body2" color="text.secondary" mb={1}>{label}</Typography>
      <Typography variant="h4" fontWeight={700} sx={{ color }}>{value}</Typography>
    </CardContent>
  </Card>
);

const FeatureCard = ({ icon, title, desc, action, onClick }) => (
  <Card sx={{ height: '100%', cursor: 'pointer', transition: 'all 0.2s', '&:hover': { transform: 'translateY(-4px)', borderColor: (t) => alpha(t.palette.primary.main, 0.4) } }} onClick={onClick}>
    <CardContent sx={{ p: 3 }}>
      <Box sx={{ mb: 2 }}>{icon}</Box>
      <Typography variant="h6" fontWeight={600} mb={1}>{title}</Typography>
      <Typography variant="body2" color="text.secondary" mb={2}>{desc}</Typography>
      <Button endIcon={<ArrowForward />} size="small" sx={{ px: 0 }}>{action}</Button>
    </CardContent>
  </Card>
);

export default function DashboardPage() {
  const user = useAuthStore((s) => s.user);
  const navigate = useNavigate();

  return (
    <Box>
      {/* Header */}
      <Box sx={{ mb: 4, display: 'flex', alignItems: 'center', gap: 2 }}>
        <Avatar sx={{ width: 52, height: 52, bgcolor: 'primary.main', fontSize: 20, fontWeight: 700 }}>
          {user?.name?.[0]?.toUpperCase() || 'U'}
        </Avatar>
        <Box>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <Typography variant="h5" fontWeight={700}>Xin chào, {user?.name}! 👋</Typography>
            <Chip label={user?.role} size="small" color="primary" variant="outlined" sx={{ height: 22, fontSize: 11 }} />
          </Box>
          <Typography variant="body2" color="text.secondary">Hôm nay bạn muốn làm gì?</Typography>
        </Box>
      </Box>

      {/* Stats */}
      <Grid container spacing={2} mb={4}>
        {[
          { label: 'Cuộc trò chuyện', value: '—', color: '#A78BFA' },
          { label: 'Tin nhắn hôm nay', value: '—', color: '#67E8F9' },
          { label: 'AI Provider', value: 'OpenAI', color: '#4ADE80' },
        ].map((s) => (
          <Grid item xs={12} sm={4} key={s.label}>
            <StatCard {...s} />
          </Grid>
        ))}
      </Grid>

      {/* Feature Cards */}
      <Typography variant="h6" fontWeight={600} mb={2}>Tính năng</Typography>
      <Grid container spacing={2}>
        <Grid item xs={12} sm={6} md={4}>
          <FeatureCard
            icon={<Box sx={{ width: 44, height: 44, borderRadius: 2, background: 'linear-gradient(135deg, #7C3AED, #A78BFA)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><ChatIcon sx={{ color: '#fff' }} /></Box>}
            title="AI Chat"
            desc="Trò chuyện với AI thông minh, hỗ trợ OpenAI, Gemini và Ollama"
            action="Bắt đầu chat"
            onClick={() => navigate('/chat')}
          />
        </Grid>
        <Grid item xs={12} sm={6} md={4}>
          <FeatureCard
            icon={<Box sx={{ width: 44, height: 44, borderRadius: 2, background: 'linear-gradient(135deg, #06B6D4, #67E8F9)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><TrendingUp sx={{ color: '#fff' }} /></Box>}
            title="Phân tích"
            desc="Xem thống kê và lịch sử sử dụng của bạn"
            action="Xem thống kê"
            onClick={() => {}}
          />
        </Grid>
        <Grid item xs={12} sm={6} md={4}>
          <FeatureCard
            icon={<Box sx={{ width: 44, height: 44, borderRadius: 2, background: 'linear-gradient(135deg, #F59E0B, #FCD34D)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><AutoAwesome sx={{ color: '#fff' }} /></Box>}
            title="Cài đặt AI"
            desc="Tùy chỉnh provider, model và các tham số AI"
            action="Cài đặt"
            onClick={() => {}}
          />
        </Grid>
      </Grid>
    </Box>
  );
}
