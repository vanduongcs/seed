// Shared Constants — dùng chung cho backend & web
export const API_ROUTES = {
  AUTH: {
    REGISTER: '/api/auth/register',
    LOGIN: '/api/auth/login',
    LOGOUT: '/api/auth/logout',
    REFRESH: '/api/auth/refresh',
    ME: '/api/auth/me',
  },
  USERS: {
    BASE: '/api/users',
    ME: '/api/users/me',
  },
  AI: {
    CHAT: '/api/ai/chat',
    CONVERSATIONS: '/api/ai/conversations',
  },
  GRAIN: {
    HEALTH: '/api/grain/health',
    ANALYZE: '/api/grain/analyze',
    RUNS: '/api/grain/runs',
    RUN: (id) => `/api/grain/runs/${id}`,
  },
};

export const USER_ROLES = {
  ADMIN: 'admin',
  USER: 'user',
};

// Grain analysis mask source options
export const GRAIN_MASK_SOURCES = {
  AUTO: 'auto',
  HYBRID: 'hybrid',
  SAM: 'sam',
  SAM_HYBRID: 'sam+hybrid',
};

// Grain analysis model types for SAM
export const GRAIN_SAM_MODELS = {
  MOBILE_SAM: 'mobile_sam',
  SAM2_TINY: 'sam2_tiny',
  SAM2_SMALL: 'sam2_small',
  FAST_SAM: 'fast_sam',
  AUTO: 'auto',
};

export const HTTP_STATUS = {
  OK: 200,
  CREATED: 201,
  BAD_REQUEST: 400,
  UNAUTHORIZED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  CONFLICT: 409,
  INTERNAL_SERVER_ERROR: 500,
};
