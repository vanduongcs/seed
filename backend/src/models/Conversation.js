import mongoose from 'mongoose';

const messageSchema = new mongoose.Schema(
  {
    role: { type: String, enum: ['user', 'assistant', 'system'], required: true },
    content: { type: String, required: true },
    createdAt: { type: String, default: () => new Date().toISOString() },
  },
  { _id: false }
);

const conversationSchema = new mongoose.Schema(
  {
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    title: { type: String, default: 'Cuộc trò chuyện mới', maxlength: 100 },
    messages: { type: [messageSchema], default: [] },
    model: { type: String, default: 'gpt-4o-mini' },
  },
  { timestamps: true, toJSON: { virtuals: true } }
);

export const Conversation = mongoose.model('Conversation', conversationSchema);
