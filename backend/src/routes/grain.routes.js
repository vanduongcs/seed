import { Router } from 'express';
import multer from 'multer';

import {
  analyzeGrainImage,
  deleteGrainRun,
  getGrainHealth,
  getGrainRun,
  listGrainRuns,
} from '../controllers/grain.controller.js';
import { authenticate } from '../middleware/auth.middleware.js';

const router = Router();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 25 * 1024 * 1024,
  },
  fileFilter: (_req, file, cb) => {
    if (['image/jpeg', 'image/png'].includes(file.mimetype)) {
      cb(null, true);
      return;
    }
    const error = new Error('Chỉ hỗ trợ ảnh JPG hoặc PNG');
    error.statusCode = 400;
    cb(error);
  },
});

router.get('/health', getGrainHealth);
router.get('/runs', authenticate, listGrainRuns);
router.get('/runs/:id', authenticate, getGrainRun);
router.delete('/runs/:id', authenticate, deleteGrainRun);
router.post('/analyze', authenticate, upload.single('image'), analyzeGrainImage);

export default router;
