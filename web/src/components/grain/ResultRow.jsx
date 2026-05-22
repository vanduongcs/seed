import { Box, Typography } from '@mui/material';

export const ResultRow = ({ label, value }) => (
  <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 2 }}>
    <Typography variant="body2" color="text.secondary">{label}</Typography>
    <Typography variant="body2" fontWeight={650}>{value}</Typography>
  </Box>
);
