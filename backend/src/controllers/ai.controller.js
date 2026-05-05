import { Conversation } from '../models/Conversation.js';
import { chatWithAI } from '../services/ai.service.js';
import { sendSuccess, sendError } from '../utils/response.util.js';

export const chat = async (req, res) => {
  try {
    const { message, conversationId, model } = req.body;
    const userId = req.user.userId;

    let conversation;
    if (conversationId) {
      conversation = await Conversation.findOne({ _id: conversationId, userId });
      if (!conversation) return sendError(res, 'Không tìm thấy cuộc trò chuyện', 404);
    } else {
      conversation = await Conversation.create({
        userId,
        title: message.slice(0, 60),
        messages: [],
        model: model || 'gpt-4o-mini',
      });
    }

    const userMessage = { role: 'user', content: message, createdAt: new Date().toISOString() };
    conversation.messages.push(userMessage);

    const aiReply = await chatWithAI(conversation.messages, model);
    const assistantMessage = { role: 'assistant', content: aiReply, createdAt: new Date().toISOString() };
    conversation.messages.push(assistantMessage);
    await conversation.save();

    sendSuccess(res, { conversationId: conversation._id, message: assistantMessage });
  } catch (err) {
    sendError(res, 'AI chat thất bại', 500, String(err));
  }
};

export const getConversations = async (req, res) => {
  try {
    const conversations = await Conversation.find({ userId: req.user.userId })
      .select('_id title model updatedAt')
      .sort({ updatedAt: -1 })
      .limit(50);
    sendSuccess(res, conversations);
  } catch (err) {
    sendError(res, 'Lấy danh sách thất bại', 500, String(err));
  }
};

export const getConversation = async (req, res) => {
  try {
    const conversation = await Conversation.findOne({ _id: req.params.id, userId: req.user.userId });
    if (!conversation) return sendError(res, 'Không tìm thấy', 404);
    sendSuccess(res, conversation);
  } catch (err) {
    sendError(res, 'Lỗi lấy dữ liệu', 500, String(err));
  }
};

export const deleteConversation = async (req, res) => {
  try {
    await Conversation.findOneAndDelete({ _id: req.params.id, userId: req.user.userId });
    sendSuccess(res, null, 'Đã xóa cuộc trò chuyện');
  } catch (err) {
    sendError(res, 'Xóa thất bại', 500, String(err));
  }
};
