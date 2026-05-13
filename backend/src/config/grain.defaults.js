const baseGrainDefaults = {
  maxSide: 2000,
  pcIndex: 0,
  k: 5,
  rgbIndexWeight: 0.65,
  minArea: 60,
  maxArea: 6000,
  minLength: 3,
  maxLength: 220,
  splitSensitivity: 8,
  openingRadius: 1,
  closingRadius: 1,
  noiseSize: 45,
  holeSize: 2500,
  seednessThreshold: 0.24,
  maskMinArea: 30,
  maxSegmentAspectRatio: 14,
  minSegmentSolidity: 0.35,
  minSegmentExtent: 0.10,
  dynamicThresholds: true,
  markerShrinkFactor: 0.5,
  denseMarkerMinDistance: 18,
  densePeakPercentile: 62,
  denseMaskPercentile: 28,
  edgeSnap: false,
  edgeSnapRadius: 4,
  edgeSnapMarkerErode: 2,
  edgeSnapSeednessScale: 0.55,
  fillContourMasks: true,
  contourFillClosingRadius: 2,
  fillSegmentHoles: true,
  segmentHoleSize: 2500,
  segmentClosingRadius: 1,
  clusterSpace: 'pca3',
  pcaMethod: 'correlation',
  watershedMode: 'dense',
  segmentationMode: 'auto',
  maskSource: 'sam',
  samModelType: 'fast_sam',
  useSamInstances: true,
};

const parseEnvDefaults = () => {
  const raw = process.env.GRAIN_DEFAULT_PARAMS_JSON;
  if (!raw) return {};

  try {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      return parsed;
    }
  } catch (error) {
    console.warn(`Invalid GRAIN_DEFAULT_PARAMS_JSON: ${error.message}`);
  }
  return {};
};

export const grainDefaultParams = Object.freeze({
  ...baseGrainDefaults,
  ...parseEnvDefaults(),
});
