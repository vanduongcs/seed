import mongoose from 'mongoose';

const mixed = mongoose.Schema.Types.Mixed;

const grainAnalysisRunSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    sourceFileName: {
      type: String,
      required: true,
      trim: true,
      default: 'image.png',
    },
    params: {
      type: mixed,
      default: {},
    },
    image: {
      type: mixed,
      default: {},
    },
    summary: {
      type: mixed,
      default: {},
    },
    segmentation: {
      type: mixed,
      default: {},
    },
    calibration: {
      type: mixed,
      default: {},
    },
    features: {
      type: mixed,
      default: {},
    },
    artifactPath: {
      type: String,
      default: '',
      select: false,
    },
    artifactMeta: {
      type: mixed,
      default: {},
    },
  },
  {
    timestamps: true,
    toJSON: {
      virtuals: true,
      transform: (_doc, ret) => {
        ret.id = ret._id.toString();
        delete ret._id;
        delete ret.__v;
        return ret;
      },
    },
  }
);

grainAnalysisRunSchema.index({ userId: 1, createdAt: -1 });

export const GrainAnalysisRun = mongoose.model('GrainAnalysisRun', grainAnalysisRunSchema);
