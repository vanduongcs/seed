import { Router } from 'express';
import {
  chat,
  getConversations,
  getConversation,
  deleteConversation,
} from '../controllers/ai.controller.js';
import { validate } from '../middleware/validate.middleware.js';
import { authenticate } from '../middleware/auth.middleware.js';
import { chatSchema } from '../../../shared/src/index.js';

const router = Router();

router.use(authenticate);

router.post('/chat', validate(chatSchema), chat);
router.get('/conversations', getConversations);
router.get('/conversations/:id', getConversation);
router.delete('/conversations/:id', deleteConversation);

export default router;
