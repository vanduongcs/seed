import { api } from '@/api/axios.js';

const GUEST_RUNS_KEY = 'seed-guest-runs';

export const saveGuestRun = ({ result, sourceFileName }) => {
  const pending = readGuestRuns();
  pending.unshift({
    clientRunId: result.run?.id || `web-local-${Date.now()}`,
    sourceFileName: sourceFileName || result.run?.sourceFileName || 'image.png',
    createdAt: result.run?.createdAt || new Date().toISOString(),
    result,
  });
  localStorage.setItem(GUEST_RUNS_KEY, JSON.stringify(pending));
};

export const syncGuestRuns = async () => {
  const pending = readGuestRuns();
  if (!pending.length) return 0;
  await api.post('/grain/runs/import', { items: pending });
  localStorage.removeItem(GUEST_RUNS_KEY);
  return pending.length;
};

const readGuestRuns = () => {
  try {
    const value = JSON.parse(localStorage.getItem(GUEST_RUNS_KEY) || '[]');
    return Array.isArray(value) ? value : [];
  } catch {
    return [];
  }
};
