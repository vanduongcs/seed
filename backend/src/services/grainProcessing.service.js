import { spawn } from 'child_process';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath } from 'url';

import { grainDefaultParams } from '../config/grain.defaults.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const backendRoot = path.resolve(__dirname, '..', '..');
const workerScript = path.join(backendRoot, 'python', 'analyze_grains.py');

const PYTHON_TIMEOUT_MS = parseInt(process.env.GRAIN_PROCESS_TIMEOUT_MS || '180000', 10);

const numericFields = new Set([
  'maxSide',
  'pcIndex',
  'k',
  'rgbIndexWeight',
  'minArea',
  'maxArea',
  'minLength',
  'maxLength',
  'splitSensitivity',
  'openingRadius',
  'closingRadius',
  'noiseSize',
  'holeSize',
  'referencePixels',
  'referenceMm',
  'referenceX1',
  'referenceY1',
  'referenceX2',
  'referenceY2',
  'referenceExcludePadding',
  'referenceExcludeOverlapRatio',
  'maskMinArea',
  'maxForegroundAreaRatio',
  'borderMargin',
  'maxAspectRatio',
  'minSolidity',
  'minExtent',
  'maxClusterExtent',
  'maxClusterSolidity',
  'clusterBlockAreaMultiplier',
  'minComponentSeednessMean',
  'minComponentSeednessP80',
  'contrastRingRadius',
  'minLabContrast',
  'minSeednessContrast',
  'minWidth',
  'maxWidth',
  'maxSegmentAspectRatio',
  'minSegmentSolidity',
  'minSegmentExtent',
  'minSegmentSeednessMean',
  'seedHueCenter',
  'seedHueWidth',
  'seednessThreshold',
  'minSeedSaturation',
  'seedMaxValue',
  'seedBrightSoftness',
  'backgroundBorderWidth',
  'backgroundDistanceMin',
  'backgroundDistanceSoftness',
  'backgroundGateStrength',
  'maxSeedMaskRatio',
  'markerShrinkFactor',
  'denseMarkerMinDistance',
  'densePeakPercentile',
  'denseMaskPercentile',
  'denseMaskClosingRadius',
  'denseMaskMinArea',
  'edgeSnapRadius',
  'edgeSnapMarkerErode',
  'edgeSnapSeednessScale',
  'edgeSnapMaxExtraRatio',
  'edgeSnapMinMarkerFraction',
  'edgeSnapGradientWeight',
  'edgeSnapValleyWeight',
  'edgeSnapColorWeight',
  'edgeSnapSeednessWeight',
  'segmentHoleSize',
  'segmentClosingRadius',
  'contourFillMinArea',
  'contourFillMaxArea',
  'contourFillClosingRadius',
  'samMinAreaRatio',
  'samMaxAreaRatio',
  'samMaxOverlapRatio',
  'samMinNewAreaRatio',
  'samConf',
  'samIou',
  'samMaxDet',
  'samTileSize',
  'samTileOverlap',
  'seedColorModelSeednessFloor',
  'maxSeedColorDistance',
  'minNonSeedObjectSeedness',
  'largeNonSeedAreaMultiplier',
  'hardMaxObjectAreaRatio',
  'riceMarkerMinDistance',
  'riceMaskPercentile',
  'ricePeakPercentile',
  'denseAutoTargetCount',
  'denseAutoMaxCount',
]);

const booleanFields = new Set([
  'includeIntermediate',
  'rejectBorderComponents',
  'rejectSuspiciousBorderComponents',
  'rejectBorderSegments',
  'dynamicThresholds',
  'dynamicAreaThresholds',
  'dynamicDiagonalThresholds',
  'dynamicMarkerSearch',
  'edgeSnap',
  'fillSegmentHoles',
  'fillContourMasks',
  'useSamInstances',
  'showMeasurementAxes',
  'samUseTiling',
  'rejectNonSeedObjects',
  'autoImageProfile',
  'autoSurfaceTune',
]);

const requestOverrideFields = new Set([
  'referencePixels',
  'referenceMm',
  'referencePixelSpace',
  'referenceX1',
  'referenceY1',
  'referenceX2',
  'referenceY2',
  'referenceExcludePadding',
  'referenceExcludeOverlapRatio',
]);

// String fields that pass through without numeric/boolean coercion
const passthroughFields = new Set([
  'maskSource',
  'samModelType',
  'samCheckpoint',
  'clusterSpace',
  'watershedMode',
  'pcaMethod',
  'referencePixelSpace',
  'segmentationMode',
]);

export const analyzeGrainImageBuffer = async ({ buffer, originalName, params }) => {
  if (!buffer?.length) {
    const error = new Error('Không có dữ liệu ảnh đầu vào');
    error.statusCode = 400;
    throw error;
  }

  const tempDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'seed-grain-'));
  const extension = safeExtension(originalName);
  const imagePath = path.join(tempDir, `input${extension}`);

  try {
    await fs.promises.writeFile(imagePath, buffer);
    const payload = await runPythonWorker(imagePath, normalizeGrainParams(params));
    if (!payload.ok) {
      const error = new Error(payload.error || 'Phân tích ảnh thất bại');
      error.statusCode = 422;
      throw error;
    }
    return payload.data;
  } finally {
    fs.promises.rm(tempDir, { recursive: true, force: true }).catch(() => {});
  }
};

export const getGrainWorkerInfo = () => ({
  python: resolvePythonExecutable(),
  workerScript,
  timeoutMs: PYTHON_TIMEOUT_MS,
  defaultParams: grainDefaultParams,
});

const runPythonWorker = (imagePath, params) => new Promise((resolve, reject) => {
  const python = resolvePythonExecutable();
  const child = spawn(python, [
    workerScript,
    '--image',
    imagePath,
    '--params-json',
    JSON.stringify(params),
  ], {
    cwd: backendRoot,
    windowsHide: true,
  });

  let stdout = '';
  let stderr = '';
  let settled = false;

  const timer = setTimeout(() => {
    settled = true;
    child.kill('SIGKILL');
    const error = new Error('Xử lý ảnh quá thời gian cho phép');
    error.statusCode = 504;
    reject(error);
  }, PYTHON_TIMEOUT_MS);

  child.stdout.on('data', (chunk) => {
    stdout += chunk.toString('utf8');
  });

  child.stderr.on('data', (chunk) => {
    stderr += chunk.toString('utf8');
  });

  child.on('error', (err) => {
    if (settled) return;
    settled = true;
    clearTimeout(timer);
    const error = new Error(`Không chạy được Python worker: ${err.message}`);
    error.statusCode = 500;
    reject(error);
  });

  child.on('close', (code) => {
    if (settled) return;
    settled = true;
    clearTimeout(timer);

    try {
      const jsonStart = stdout.indexOf('{"ok"');
      const jsonText = jsonStart >= 0 ? stdout.slice(jsonStart) : stdout;
      const parsed = JSON.parse(jsonText || '{}');
      if (code !== 0 && parsed?.error) {
        const error = new Error(`${parsed.error}${stderr ? ` (${stderr.trim()})` : ''}`);
        error.statusCode = 422;
        reject(error);
        return;
      }
      resolve(parsed);
    } catch {
      const error = new Error(`Python worker trả dữ liệu không hợp lệ${stderr ? `: ${stderr.trim()}` : ''}`);
      error.statusCode = 500;
      reject(error);
    }
  });
});

export const normalizeGrainParams = (params = {}) => {
  const normalized = { ...grainDefaultParams };
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null || value === '') continue;
    if (!requestOverrideFields.has(key)) continue;

    if (numericFields.has(key)) {
      const parsed = Number(value);
      if (Number.isFinite(parsed)) normalized[key] = parsed;
      continue;
    }

    if (booleanFields.has(key)) {
      normalized[key] = value === true || value === 'true' || value === '1' || value === 1;
      continue;
    }

    if (passthroughFields.has(key)) {
      normalized[key] = String(value).trim();
      continue;
    }

    normalized[key] = value;
  }
  return normalized;
};

const safeExtension = (name = '') => {
  const ext = path.extname(name).toLowerCase();
  if (['.jpg', '.jpeg', '.png'].includes(ext)) return ext;
  return '.png';
};

const resolvePythonExecutable = () => {
  if (process.env.GRAIN_PYTHON_BIN) return process.env.GRAIN_PYTHON_BIN;

  const winVenv = path.join(backendRoot, '.venv', 'Scripts', 'python.exe');
  const posixVenv = path.join(backendRoot, '.venv', 'bin', 'python');
  if (fs.existsSync(winVenv)) return winVenv;
  if (fs.existsSync(posixVenv)) return posixVenv;
  return process.platform === 'win32' ? 'python' : 'python3';
};
