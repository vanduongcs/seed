import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import compression from 'compression';
import rateLimit from 'express-rate-limit';
import { createServer } from 'http';
import { Server as SocketServer } from 'socket.io';

import { env } from './config/env.js';
import { connectDB } from './config/db.js';
import { errorHandler, notFound } from './middleware/error.middleware.js';

import authRoutes from './routes/auth.routes.js';
import userRoutes from './routes/user.routes.js';
import aiRoutes from './routes/ai.routes.js';

const app = express();
const httpServer = createServer(app);

// ---- Socket.IO ----
const io = new SocketServer(httpServer, {
  cors: { origin: env.ALLOWED_ORIGINS, methods: ['GET', 'POST'] },
});
io.on('connection', (socket) => {
  console.log(`🔌 Socket connected: ${socket.id}`);
  socket.on('disconnect', () => console.log(`🔌 Socket disconnected: ${socket.id}`));
});

// ---- Middleware ----
app.use(helmet());
app.use(cors({ origin: env.ALLOWED_ORIGINS, credentials: true }));
app.use(compression());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));
app.use(morgan(env.isDev ? 'dev' : 'combined'));

// ---- Rate Limiter ----
app.use('/api', rateLimit({
  windowMs: env.RATE_LIMIT.WINDOW_MS,
  max: env.RATE_LIMIT.MAX,
  message: { success: false, message: 'Quá nhiều yêu cầu, vui lòng thử lại sau.' },
}));

// ---- Health Check ----
app.get('/health', (_req, res) => {
  res.json({ success: true, message: 'Server đang chạy', timestamp: new Date().toISOString() });
});

// ---- Routes ----
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/ai', aiRoutes);

// ---- Error Handling ----
app.use(notFound);
app.use(errorHandler);

httpServer.on('error', (error) => {
  if (error.code === 'EADDRINUSE') {
    console.error(`Port ${env.PORT} is already in use. Stop the existing server or set PORT to a different value in .env.`);
    process.exit(1);
  }

  console.error(error);
  process.exit(1);
});

// ---- Start ----
const start = async () => {
  await connectDB();
  httpServer.listen(env.PORT, () => {
    console.log(`🚀 Server: http://localhost:${env.PORT}`);
    console.log(`📡 AI Provider: ${env.AI.PROVIDER}`);
    console.log(`🌍 Environment: ${env.NODE_ENV}`);
  });
};

start().catch(console.error);

export { io };
