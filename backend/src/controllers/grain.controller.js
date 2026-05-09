import { analyzeGrainImageBuffer, getGrainWorkerInfo } from '../services/grainProcessing.service.js';
import { sendSuccess, sendError } from '../utils/response.util.js';

export const getGrainHealth = (_req, res) => {
  sendSuccess(res, getGrainWorkerInfo(), 'Grain analysis worker configured');
};

export const analyzeGrainImage = async (req, res) => {
  try {
    if (!req.file) {
      return sendError(res, 'Vui lòng upload ảnh với field name là image', 400);
    }

    const result = await analyzeGrainImageBuffer({
      buffer: req.file.buffer,
      originalName: req.file.originalname,
      params: req.body,
    });

    return sendSuccess(res, result, 'Phân tích ảnh thành công');
  } catch (err) {
    return sendError(res, err.message || 'Phân tích ảnh thất bại', err.statusCode || 500);
  }
};
