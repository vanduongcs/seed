# Seed

Seed is a monorepo for seed-grain image analysis. The web app runs the server ONNX pipeline; the mobile app runs the matching ONNX model locally and optionally syncs results through the backend. Both clients return measurements, QC statistics, CSV, and PNG previews.

## Structure

```text
backend/   Express API, MongoDB, JWT auth, Python image worker
web/       React + Vite + Material UI dashboard
mobile/    Flutter app
shared/    Shared constants and validators
```

## Main Pipeline

The active image pipeline is `yolo8_nano_segment`.

1. Backend receives `POST /api/grain/analyze`.
2. Node writes the uploaded image to a temporary folder.
3. `backend/python/analyze_grains.py` calls the Python pipeline in `backend/python/grain_pipeline/`.
4. YOLO segmentation predicts instance masks.
5. The pipeline filters masks, measures geometry, applies optional calibration, and returns JSON.
6. Backend stores run metadata and an artifact JSON for history/detail views.

Generated preview fields:

- `original_png_base64`
- `preprocessed_png_base64`
- `overlay_png_base64`
- `mask_png_base64`
- `labels_png_base64`

## Pipeline Settings

All runtime image-analysis parameters are centralized in:

```text
backend/config/grain.settings.json
```

Node reads this file through:

```text
backend/src/config/grain.defaults.js
```

Python reads the same file through:

```text
backend/python/grain_pipeline/config.py
```

`GRAIN_DEFAULT_PARAMS_JSON` can override defaults at runtime. `GRAIN_YOLO_MODEL` can override the YOLO model path.

## Model Placement

Put the trained YOLOv8 segmentation model here:

```text
backend/model/best.onnx
```

or:

```text
backend/model/best.pt
```

The worker resolves models in this order:

1. `GRAIN_YOLO_MODEL`, if set.
2. `backend/model/best.onnx`.
3. `backend/model/best.pt`.
4. `yolov8n-seg.pt` fallback for development.

`backend/model/best.onnx` is committed because source-based server/Azure deployments require the production inference asset. Training checkpoints such as `best.pt` remain local artifacts.

## API

```text
POST /api/grain/analyze
```

Multipart fields:

- `image`: JPG/PNG file.
- `referencePixels`, `referenceMm`, `referencePixelSpace`: optional calibration.

Health endpoint:

```text
GET /api/grain/health
```

## Local Setup

Requirements:

- Node.js >= 18
- npm >= 9
- MongoDB
- Python 3.10+
- Flutter SDK for mobile

Install Node dependencies:

```bash
npm install
```

Create local env:

```powershell
Copy-Item .env.example .env
```

Install Python worker dependencies:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r python\requirements.txt
cd ..
```

Run backend and web:

```bash
npm run dev
```

Run separately:

```bash
npm run dev:backend
npm run dev:web
```

Build web:

```bash
npm run build:web
```

Run mobile:

```bash
cd mobile
flutter pub get
flutter run
```

Mobile analysis runs locally through ONNX Runtime using `mobile/assets/models/best.onnx`; it does not require login or network access. The app discovers the backend only for authentication, history synchronization, and authenticated storage access. It first uses an explicit `BASE_URL` when provided, then tries the Android emulator URL, then scans the current LAN for the backend health check on port `3000`.

Backend URLs for debugging:

```text
http://localhost:3000
http://10.0.2.2:3000/api
```

For a physical device, keep the phone and backend computer on the same Wi-Fi network and make sure the firewall allows inbound traffic on port `3000`. `BASE_URL` is still supported for overrides:

```bash
flutter run --dart-define=BASE_URL=http://192.168.1.x:3000/api
```

## Local Files Kept Out Of Git

The repo ignores local runtime artifacts such as `.env`, virtualenvs, `node_modules`, build outputs, logs, Python cache, training checkpoints, and backend storage artifacts. The two production ONNX files used by server and mobile packaging are explicitly tracked.
