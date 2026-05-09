import mongoose from 'mongoose';

import { GrainAnalysisRun } from '../models/GrainAnalysisRun.js';
import {
  analyzeGrainImageBuffer,
  getGrainWorkerInfo,
  normalizeGrainParams,
} from '../services/grainProcessing.service.js';
import {
  deleteGrainRunArtifact,
  readGrainRunArtifact,
  writeGrainRunArtifact,
} from '../services/grainRunArtifact.service.js';
import { sendSuccess, sendError } from '../utils/response.util.js';

export const getGrainHealth = (_req, res) => {
  sendSuccess(res, getGrainWorkerInfo(), 'Grain analysis worker configured');
};

export const analyzeGrainImage = async (req, res) => {
  let run = null;
  try {
    if (!req.file) {
      return sendError(res, 'Vui lòng upload ảnh với field name là image', 400);
    }

    const params = normalizeGrainParams(req.body);
    const result = await analyzeGrainImageBuffer({
      buffer: req.file.buffer,
      originalName: req.file.originalname,
      params,
    });

    run = await GrainAnalysisRun.create({
      userId: req.user.userId,
      sourceFileName: req.file.originalname || 'image.png',
      params,
      image: result.image,
      summary: result.summary,
      segmentation: result.segmentation,
      kmeans: {
        k: result.kmeans?.k,
        cluster_space: result.kmeans?.cluster_space,
        counts: result.kmeans?.counts,
        selected_clusters: result.kmeans?.selected_clusters,
      },
      features: result.features,
    });
    run.artifactPath = await writeGrainRunArtifact({
      userId: req.user.userId,
      runId: run._id.toString(),
      result,
    });
    await run.save();

    return sendSuccess(
      res,
      {
        ...result,
        run: serializeRunSummary(run),
      },
      'Phân tích ảnh thành công'
    );
  } catch (err) {
    if (run?._id) {
      await GrainAnalysisRun.findByIdAndDelete(run._id).catch(() => {});
      await deleteGrainRunArtifact(run.artifactPath).catch(() => {});
    }
    return sendError(res, err.message || 'Phân tích ảnh thất bại', err.statusCode || 500);
  }
};

export const listGrainRuns = async (req, res) => {
  try {
    const limit = Math.max(1, Math.min(Number(req.query.limit) || 50, 100));
    const runs = await GrainAnalysisRun.find({ userId: req.user.userId })
      .sort({ createdAt: -1 })
      .limit(limit)
      .lean({ virtuals: true });

    return sendSuccess(res, {
      items: runs.map(serializeLeanRunSummary),
      total: runs.length,
    });
  } catch (err) {
    return sendError(res, 'Lấy lịch sử phân tích thất bại', 500, String(err));
  }
};

export const getGrainRun = async (req, res) => {
  try {
    if (!mongoose.isValidObjectId(req.params.id)) {
      return sendError(res, 'Mã xử lý không hợp lệ', 400);
    }

    const run = await GrainAnalysisRun.findOne({
      _id: req.params.id,
      userId: req.user.userId,
    }).select('+artifactPath');

    if (!run) return sendError(res, 'Không tìm thấy lần xử lý', 404);
    const result = await loadRunResult(run);

    return sendSuccess(res, {
      run: serializeRunSummary(run),
      result,
    });
  } catch (err) {
    return sendError(res, 'Lấy chi tiết phân tích thất bại', 500, String(err));
  }
};

export const deleteGrainRun = async (req, res) => {
  try {
    if (!mongoose.isValidObjectId(req.params.id)) {
      return sendError(res, 'Mã xử lý không hợp lệ', 400);
    }

    const deleted = await GrainAnalysisRun.findOneAndDelete({
      _id: req.params.id,
      userId: req.user.userId,
    }).select('+artifactPath');

    if (!deleted) return sendError(res, 'Không tìm thấy lần xử lý', 404);
    await deleteGrainRunArtifact(deleted.artifactPath).catch(() => {});
    return sendSuccess(res, null, 'Đã xóa lần xử lý');
  } catch (err) {
    return sendError(res, 'Xóa lần xử lý thất bại', 500, String(err));
  }
};

const serializeRunSummary = (run) => serializeLeanRunSummary(run.toJSON ? run.toJSON() : run);

const serializeLeanRunSummary = (run) => ({
  id: run.id || run._id?.toString(),
  sourceFileName: run.sourceFileName,
  params: run.params || {},
  image: run.image || {},
  summary: run.summary || {},
  segmentation: run.segmentation || {},
  kmeans: run.kmeans || {},
  features: run.features || {},
  createdAt: run.createdAt,
  updatedAt: run.updatedAt,
});

const serializeRunResult = (run) => ({
  image: run.image || {},
  features: run.features || {},
  kmeans: run.kmeans || {},
  segmentation: run.segmentation || {},
  summary: run.summary || {},
  measurements: [],
  csv: '',
  overlay_png_base64: '',
  cluster_png_base64: '',
  mask_png_base64: '',
  seed_mask_png_base64: '',
  kmeans_mask_png_base64: '',
  labels_png_base64: '',
});

const loadRunResult = async (run) => {
  try {
    return await readGrainRunArtifact(run.artifactPath);
  } catch {
    return serializeRunResult(run);
  }
};
