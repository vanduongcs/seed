import { env } from '../config/env.js';
import OpenAI from 'openai';

let openaiClient = null;
const getOpenAI = () => {
  if (!openaiClient) openaiClient = new OpenAI({ apiKey: env.AI.OPENAI_API_KEY });
  return openaiClient;
};

export const chatWithAI = async (messages, model) => {
  const provider = env.AI.PROVIDER;
  if (provider === 'openai') return chatOpenAI(messages, model || 'gpt-4o-mini');
  if (provider === 'ollama') return chatOllama(messages, model || 'llama3');
  if (provider === 'gemini') return chatGemini(messages, model || 'gemini-pro');
  throw new Error(`AI provider không được hỗ trợ: ${provider}`);
};

const chatOpenAI = async (messages, model) => {
  const openai = getOpenAI();
  const completion = await openai.chat.completions.create({
    model,
    messages: messages.map((m) => ({ role: m.role, content: m.content })),
    temperature: 0.7,
    max_tokens: 2048,
  });
  return completion.choices[0]?.message?.content || '';
};

const chatOllama = async (messages, model) => {
  const response = await fetch(`${env.AI.OLLAMA_BASE_URL}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, messages, stream: false }),
  });
  if (!response.ok) throw new Error(`Ollama lỗi: ${response.statusText}`);
  const data = await response.json();
  return data.message.content;
};

const chatGemini = async (messages, _model) => {
  const lastUserMsg = messages.filter((m) => m.role === 'user').pop();
  if (!lastUserMsg) throw new Error('Không tìm thấy tin nhắn người dùng');
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=${env.AI.GEMINI_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ contents: [{ parts: [{ text: lastUserMsg.content }] }] }),
    }
  );
  if (!response.ok) throw new Error(`Gemini lỗi: ${response.statusText}`);
  const data = await response.json();
  return data.candidates[0]?.content?.parts[0]?.text || '';
};
