import 'dotenv/config';

export const env = {
  PORT: parseInt(process.env.PORT || '3000', 10),
  NODE_ENV: process.env.NODE_ENV || 'development',
  MONGODB_URI: process.env.MONGODB_URI || 'mongodb://localhost:27017/seed_db',
  JWT: {
    ACCESS_SECRET: process.env.JWT_ACCESS_SECRET || 'access_secret_dev',
    REFRESH_SECRET: process.env.JWT_REFRESH_SECRET || 'refresh_secret_dev',
    ACCESS_EXPIRES_IN: process.env.JWT_ACCESS_EXPIRES_IN || '15m',
    REFRESH_EXPIRES_IN: process.env.JWT_REFRESH_EXPIRES_IN || '7d',
  },
  AI: {
    PROVIDER: process.env.AI_PROVIDER || 'openai',
    OPENAI_API_KEY: process.env.OPENAI_API_KEY || '',
    GEMINI_API_KEY: process.env.GEMINI_API_KEY || '',
    OLLAMA_BASE_URL: process.env.OLLAMA_BASE_URL || 'http://localhost:11434',
  },
  ALLOWED_ORIGINS: (process.env.ALLOWED_ORIGINS || 'http://localhost:5173')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
  RATE_LIMIT: {
    WINDOW_MS: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '900000', 10),
    MAX: parseInt(process.env.RATE_LIMIT_MAX || '100', 10),
  },
  get isProd() { return this.NODE_ENV === 'production'; },
  get isDev()  { return this.NODE_ENV === 'development'; },
};
