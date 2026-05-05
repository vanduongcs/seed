import {
  Box, Typography, Card, CardContent, Grid, Chip,
  Table, TableBody, TableCell, TableContainer, TableHead, TableRow,
} from '@mui/material';

const records = [
  {
    id: 'RUN-2026-0505-001',
    time: '05/05/2026 21:18',
    operator: 'Nguyễn Văn Dương',
    seedCount: 124,
    length: '7,42 mm',
    width: '3,18 mm',
    status: 'Hoàn tất',
  },
  {
    id: 'RUN-2026-0504-003',
    time: '04/05/2026 16:40',
    operator: 'Nguyễn Văn Dương',
    seedCount: 96,
    length: '7,11 mm',
    width: '3,05 mm',
    status: 'Hoàn tất',
  },
  {
    id: 'RUN-2026-0503-002',
    time: '03/05/2026 09:12',
    operator: 'Trần Minh',
    seedCount: 143,
    length: '7,66 mm',
    width: '3,22 mm',
    status: 'Cần kiểm tra',
  },
];

const ImagePreview = ({ id }) => (
  <Box sx={{
    width: 92,
    height: 58,
    borderRadius: 1,
    border: '1px solid',
    borderColor: 'divider',
    bgcolor: '#EEF3EA',
    display: 'grid',
    placeItems: 'center',
    color: 'text.secondary',
    fontSize: 11,
    fontWeight: 650,
  }}>
    {id.slice(-3)}
  </Box>
);

export default function StoragePage() {
  return (
    <Box sx={{ maxWidth: 1200 }}>
      <Typography variant="h5" fontWeight={700} mb={0.75}>Lưu trữ</Typography>
      <Typography variant="body2" color="text.secondary" mb={2.5}>
        Lịch sử các lần xử lý, output số liệu, người thực hiện và hình ảnh liên quan.
      </Typography>

      <Grid container spacing={2}>
        <Grid item xs={12}>
          <Card>
            <CardContent sx={{ p: 0 }}>
              <TableContainer>
                <Table>
                  <TableHead>
                    <TableRow>
                      <TableCell>Hình ảnh</TableCell>
                      <TableCell>Mã xử lý</TableCell>
                      <TableCell>Thời gian</TableCell>
                      <TableCell>Người thực hiện</TableCell>
                      <TableCell align="right">Số hạt</TableCell>
                      <TableCell align="right">Dài TB</TableCell>
                      <TableCell align="right">Rộng TB</TableCell>
                      <TableCell>Trạng thái</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {records.map((record) => (
                      <TableRow key={record.id} hover>
                        <TableCell><ImagePreview id={record.id} /></TableCell>
                        <TableCell>{record.id}</TableCell>
                        <TableCell>{record.time}</TableCell>
                        <TableCell>{record.operator}</TableCell>
                        <TableCell align="right">{record.seedCount}</TableCell>
                        <TableCell align="right">{record.length}</TableCell>
                        <TableCell align="right">{record.width}</TableCell>
                        <TableCell>
                          <Chip
                            label={record.status}
                            size="small"
                            color={record.status === 'Hoàn tất' ? 'success' : 'warning'}
                            variant="outlined"
                          />
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </TableContainer>
            </CardContent>
          </Card>
        </Grid>
      </Grid>
    </Box>
  );
}
