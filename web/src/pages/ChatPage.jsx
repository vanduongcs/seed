import { useState, useRef, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import {
  Box, Typography, TextField, IconButton, Paper,
  CircularProgress, alpha, Tooltip, Divider,
} from '@mui/material';
import { Send, Add, AutoAwesome, Person } from '@mui/icons-material';
import { api } from '@/api/axios.js';

const MessageBubble = ({ msg }) => {
  const isUser = msg.role === 'user';
  return (
    <Box sx={{ display: 'flex', justifyContent: isUser ? 'flex-end' : 'flex-start', mb: 2 }}>
      {!isUser && (
        <Box sx={{ width: 32, height: 32, borderRadius: '50%', background: 'linear-gradient(135deg, #7C3AED, #06B6D4)', display: 'flex', alignItems: 'center', justifyContent: 'center', mr: 1.5, flexShrink: 0, mt: 0.5 }}>
          <AutoAwesome sx={{ color: '#fff', fontSize: 16 }} />
        </Box>
      )}
      <Box sx={{
        maxWidth: '72%',
        px: 2.5, py: 1.5, borderRadius: isUser ? '18px 18px 4px 18px' : '18px 18px 18px 4px',
        bgcolor: isUser ? 'primary.main' : (t) => alpha(t.palette.primary.main, 0.1),
        border: isUser ? 'none' : '1px solid',
        borderColor: isUser ? 'transparent' : (t) => alpha(t.palette.primary.main, 0.2),
      }}>
        <Typography variant="body2" sx={{ whiteSpace: 'pre-wrap', lineHeight: 1.7 }}>
          {msg.content}
        </Typography>
      </Box>
      {isUser && (
        <Box sx={{ width: 32, height: 32, borderRadius: '50%', bgcolor: 'primary.dark', display: 'flex', alignItems: 'center', justifyContent: 'center', ml: 1.5, flexShrink: 0, mt: 0.5 }}>
          <Person sx={{ color: '#fff', fontSize: 16 }} />
        </Box>
      )}
    </Box>
  );
};

export default function ChatPage() {
  const { id } = useParams();
  const navigate = useNavigate();
  const [messages, setMessages] = useState([]);
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [conversationId, setConversationId] = useState(id || null);
  const bottomRef = useRef(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  useEffect(() => {
    if (id) { setConversationId(id); loadConversation(id); }
    else { setConversationId(null); setMessages([]); }
  }, [id]);

  const loadConversation = async (cid) => {
    try {
      const { data } = await api.get(`/ai/conversations/${cid}`);
      setMessages(data.data.messages || []);
    } catch { /* ignore */ }
  };

  const handleSend = async () => {
    const msg = input.trim();
    if (!msg || loading) return;

    setInput('');
    setMessages((prev) => [...prev, { role: 'user', content: msg }]);
    setLoading(true);

    try {
      const { data } = await api.post('/ai/chat', { message: msg, conversationId });
      const newId = data.data.conversationId;
      if (!conversationId) {
        setConversationId(newId);
        navigate(`/chat/${newId}`, { replace: true });
      }
      setMessages((prev) => [...prev, data.data.message]);
    } catch (err) {
      setMessages((prev) => [...prev, { role: 'assistant', content: '❌ ' + (err.response?.data?.message || 'Có lỗi xảy ra, vui lòng thử lại.') }]);
    } finally {
      setLoading(false);
    }
  };

  const handleKeyDown = (e) => {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleSend(); }
  };

  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', height: 'calc(100vh - 48px)' }}>
      {/* Header */}
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
          <Box sx={{ width: 36, height: 36, borderRadius: 2, background: 'linear-gradient(135deg, #7C3AED, #06B6D4)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <AutoAwesome sx={{ color: '#fff', fontSize: 18 }} />
          </Box>
          <Box>
            <Typography variant="h6" fontWeight={600}>AI Chat</Typography>
            <Typography variant="caption" color="text.secondary">Powered by OpenAI / Gemini / Ollama</Typography>
          </Box>
        </Box>
        <Tooltip title="Cuộc trò chuyện mới">
          <IconButton onClick={() => navigate('/chat')} sx={{ bgcolor: (t) => alpha(t.palette.primary.main, 0.1), '&:hover': { bgcolor: (t) => alpha(t.palette.primary.main, 0.2) } }}>
            <Add />
          </IconButton>
        </Tooltip>
      </Box>

      <Divider sx={{ borderColor: (t) => alpha(t.palette.primary.main, 0.1), mb: 2 }} />

      {/* Messages */}
      <Box sx={{ flex: 1, overflowY: 'auto', pr: 1, '&::-webkit-scrollbar': { width: 4 }, '&::-webkit-scrollbar-thumb': { borderRadius: 2, bgcolor: (t) => alpha(t.palette.primary.main, 0.2) } }}>
        {messages.length === 0 && (
          <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100%', gap: 2, opacity: 0.5 }}>
            <Box sx={{ width: 64, height: 64, borderRadius: 3, background: 'linear-gradient(135deg, #7C3AED, #06B6D4)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <AutoAwesome sx={{ color: '#fff', fontSize: 32 }} />
            </Box>
            <Typography variant="h6" fontWeight={600}>Bắt đầu cuộc trò chuyện</Typography>
            <Typography variant="body2" color="text.secondary">Gõ tin nhắn bên dưới để chat với AI</Typography>
          </Box>
        )}
        {messages.map((msg, i) => <MessageBubble key={i} msg={msg} />)}
        {loading && (
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mb: 2 }}>
            <Box sx={{ width: 32, height: 32, borderRadius: '50%', background: 'linear-gradient(135deg, #7C3AED, #06B6D4)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <AutoAwesome sx={{ color: '#fff', fontSize: 16 }} />
            </Box>
            <Paper sx={{ px: 2.5, py: 1.5, borderRadius: '18px 18px 18px 4px', bgcolor: (t) => alpha(t.palette.primary.main, 0.1) }}>
              <CircularProgress size={16} sx={{ color: 'primary.light' }} />
            </Paper>
          </Box>
        )}
        <div ref={bottomRef} />
      </Box>

      {/* Input */}
      <Box sx={{ mt: 2, display: 'flex', gap: 1, alignItems: 'flex-end' }}>
        <TextField
          id="chat-input"
          multiline maxRows={4} fullWidth
          placeholder="Nhập tin nhắn... (Enter để gửi, Shift+Enter xuống dòng)"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={handleKeyDown}
          disabled={loading}
          sx={{ '& .MuiOutlinedInput-root': { borderRadius: 3, fontSize: '0.9rem' } }}
        />
        <IconButton
          id="chat-send"
          onClick={handleSend}
          disabled={!input.trim() || loading}
          sx={{
            width: 48, height: 48, mb: 0.1,
            background: input.trim() && !loading ? 'linear-gradient(135deg, #7C3AED, #5B21B6)' : undefined,
            '&:hover': { background: 'linear-gradient(135deg, #8B5CF6, #6D28D9)' },
            '&.Mui-disabled': { opacity: 0.4 },
          }}
        >
          <Send sx={{ color: input.trim() && !loading ? '#fff' : 'text.secondary', fontSize: 20 }} />
        </IconButton>
      </Box>
    </Box>
  );
}
