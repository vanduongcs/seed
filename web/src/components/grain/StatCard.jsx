import { Box, Card, CardContent, Typography } from '@mui/material';

export const StatCard = ({ label, value, note }) => (
  <Card sx={{ height: '100%' }}>
    <CardContent sx={{ p: 2.25 }}>
      <Box sx={{ mb: 1.25 }}>
        <Typography variant="body2" color="text.secondary">{label}</Typography>
      </Box>
      <Typography variant="h5" fontWeight={700}>{value}</Typography>
      <Typography variant="caption" color="text.secondary">{note}</Typography>
    </CardContent>
  </Card>
);
