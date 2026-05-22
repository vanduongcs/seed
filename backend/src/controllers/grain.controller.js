import mongoose from 'mongoose';

import { GrainAnalysisRun } from '../models/GrainAnalysisRun.js';
import {
  analyzeGrainImageBuffer,
  getGrainWorkerInfo,
  normalizeGrainParams,
} from '../services/grainProcessing.service.js';
import {
  checksumGrainRunArtifact,
  deleteGrainRunArtifact,
  readGrainRunArtifact,
  statGrainRunArtifact,
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
      calibration: result.calibration,
      features: result.features,
    });
    const artifactPath = await writeGrainRunArtifact({
      userId: req.user.userId,
      runId: run._id.toString(),
      result,
    });
    const [artifactStat, artifactChecksum] = await Promise.all([
      statGrainRunArtifact(artifactPath).catch(() => null),
      checksumGrainRunArtifact(artifactPath).catch(() => ''),
    ]);
    run.artifactPath = artifactPath;
    run.artifactMeta = {
      schemaVersion: 2,
      checksumSha256: artifactChecksum || '',
      sizeBytes: artifactStat?.sizeBytes || 0,
    };
    await run.save();

    return sendSuccess(
      res,
      {
        ...compactAnalyzeResponse(result),
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
    const before = parseBeforeCursor(req.query.before);
    const filter = { userId: req.user.userId };
    if (before) {
      filter.$or = [
        { createdAt: { $lt: before.createdAt } },
        { createdAt: before.createdAt, _id: { $lt: before.id } },
      ];
    }
    const runs = await GrainAnalysisRun.find(filter)
      .sort({ createdAt: -1, _id: -1 })
      .limit(limit)
      .lean({ virtuals: true });
    const total = await GrainAnalysisRun.countDocuments({ userId: req.user.userId });
    const last = runs[runs.length - 1];
    const nextBefore = last ? encodeBeforeCursor(last.createdAt, last._id) : null;

    return sendSuccess(res, {
      items: runs.map(serializeLeanRunSummary),
      total,
      page: {
        limit,
        hasMore: runs.length === limit,
        nextBefore,
      },
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
  calibration: run.calibration || {},
  features: run.features || {},
  artifactMeta: run.artifactMeta || {},
  createdAt: run.createdAt,
  updatedAt: run.updatedAt,
});

const serializeRunResult = (run) => ({
  image: run.image || {},
  features: run.features || {},
  segmentation: run.segmentation || {},
  calibration: run.calibration || {},
  summary: run.summary || {},
  measurements: [],
  csv: '',
  original_png_base64: '',
  preprocessed_png_base64: '',
  overlay_png_base64: '',
  sam_mask_png_base64: '',
  mask_png_base64: '',
  labels_png_base64: '',
  stages: {
    input: 'original_png_base64',
    preprocessed: 'preprocessed_png_base64',
    original: 'original_png_base64',
    labels_final: 'labels_png_base64',
    overlay_final: 'overlay_png_base64',
    mask: 'mask_png_base64',
  },
});

const loadRunResult = async (run) => {
  try {
    const artifact = await readGrainRunArtifact(run.artifactPath);
    return {
      ...serializeRunResult(run),
      ...artifact,
    };
  } catch {
    return serializeRunResult(run);
  }
};

const compactAnalyzeResponse = (result) => ({
  image: result.image || {},
  features: result.features || {},
  segmentation: result.segmentation || {},
  calibration: result.calibration || {},
  summary: result.summary || {},
  measurements: result.measurements || [],
  csv: result.csv || '',
  overlay_png_base64: result.overlay_png_base64 || '',
  sam_mask_png_base64: result.sam_mask_png_base64 || '',
  preprocessed_png_base64: result.preprocessed_png_base64 || '',
  mask_png_base64: result.mask_png_base64 || '',
  labels_png_base64: result.labels_png_base64 || '',
});

const parseBeforeCursor = (value) => {
  if (!value) return null;
  try {
    const raw = Buffer.from(String(value), 'base64url').toString('utf8');
    const parsed = JSON.parse(raw);
    if (!parsed?.createdAt || !parsed?.id || !mongoose.isValidObjectId(parsed.id)) return null;
    const createdAt = new Date(parsed.createdAt);
    if (Number.isNaN(createdAt.getTime())) return null;
    return { createdAt, id: parsed.id };
  } catch {
    return null;
  }
};

const encodeBeforeCursor = (createdAt, id) => {
  const payload = JSON.stringify({
    createdAt: new Date(createdAt).toISOString(),
    id: id.toString(),
  });
  return Buffer.from(payload, 'utf8').toString('base64url');
};
