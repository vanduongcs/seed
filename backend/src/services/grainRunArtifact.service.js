import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const backendRoot = path.resolve(__dirname, '..', '..');
const artifactRoot = path.join(backendRoot, 'storage', 'grain-runs');

export const writeGrainRunArtifact = async ({ userId, runId, result }) => {
  const userDir = path.join(artifactRoot, safePathSegment(userId));
  await fs.promises.mkdir(userDir, { recursive: true });

  const artifactFile = path.join(userDir, `${safePathSegment(runId)}.json`);
  await fs.promises.writeFile(artifactFile, JSON.stringify(result), 'utf8');

  return path.relative(backendRoot, artifactFile).replace(/\\/g, '/');
};

export const readGrainRunArtifact = async (artifactPath) => {
  const artifactFile = resolveArtifactPath(artifactPath);
  const content = await fs.promises.readFile(artifactFile, 'utf8');
  return JSON.parse(content);
};

export const deleteGrainRunArtifact = async (artifactPath) => {
  if (!artifactPath) return;
  const artifactFile = resolveArtifactPath(artifactPath);
  await fs.promises.rm(artifactFile, { force: true });
};

const resolveArtifactPath = (artifactPath) => {
  if (!artifactPath) {
    throw new Error('Artifact path is empty');
  }

  const artifactFile = path.resolve(backendRoot, artifactPath);
  const expectedRoot = path.resolve(artifactRoot);
  if (!artifactFile.startsWith(`${expectedRoot}${path.sep}`)) {
    throw new Error('Artifact path is outside grain storage');
  }

  return artifactFile;
};

const safePathSegment = (value) => (
  String(value || 'unknown').replace(/[^a-zA-Z0-9_-]/g, '_')
);
