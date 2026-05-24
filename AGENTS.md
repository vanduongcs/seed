# Seed Project Operating Guide For AI Agents

Read this file before changing, reviewing, building, or deploying this repository. It records the active architecture and the deployment process verified on 2026-05-25 (Asia/Bangkok). Do not replace verified facts here with assumptions from old docs, old commits, or similarly named folders.

## Owner Intent

The user expects an agent to work end to end:

1. Inspect the relevant current code and existing uncommitted changes first.
2. Fix issues rather than only describing them, unless the user explicitly requests analysis only.
3. Preserve consistency between web and mobile behavior and result terminology.
4. Run appropriate validation/build steps.
5. When asked to publish/deploy, commit and push to `deploy-prototype`, follow the GitHub Actions deployment, then verify Azure production with real API requests.

Communicate in Vietnamese unless the user asks otherwise. Be direct about incomplete deployment, failed tests, credentials/tooling unavailable, and any behavioral mismatch.

## Repository And Git Rules

- Workspace root: `D:\seed`
- GitHub repository: `https://github.com/vanduongcs/seed.git`
- Active deployment branch: `deploy-prototype`
- Do not push feature work to `main` unless the user explicitly changes the target branch.
- The Azure deployment workflow exists at `.github/workflows/deploy-prototype_seed-vanb2207577.yml`.
- A push to `deploy-prototype` now triggers a container build and Azure deployment. Do not push harmless exploratory or unfinished changes because it causes a production deployment.
- The worktree may contain user edits. Never discard or reset unrelated changes. Review and preserve them; include them only when they are part of the requested release.
- `seed.apk` is a local release artifact and is ignored by git; do not attempt to publish it through the repository unless the user explicitly requests a release artifact workflow.
- `seed_deploy/` and `seed-backend/` are separate/legacy deployment-oriented directories, not the active full-app Azure deployment path. Do not edit or commit inside them unless the task explicitly targets them.

Standard publication sequence when the user asks to deploy:

```powershell
git status --short --branch
git diff --check
git add <reviewed intended files>
git diff --cached --check
git commit -m "<accurate message>"
git push origin deploy-prototype
```

Never commit secrets, `.env` contents, Azure credentials, registry passwords, MongoDB connection strings, or GitHub Action secret values.

## Active Project Structure

```text
backend/     Express API, MongoDB persistence, JWT authentication, Python image worker
web/         React + Vite + Material UI web client
mobile/      Flutter Android/mobile client
shared/      Shared JavaScript constants and validators
Dockerfile   Production full-app container: builds web, serves it from backend, runs Python worker
```

The root `Dockerfile` is the production Azure image build path. It:

1. Builds `web/`.
2. Copies the built web assets to `backend/public`.
3. Installs production Node dependencies and Python requirements.
4. Starts `npm start --workspace=backend` on port `3000`.

## Current Inference Architecture

Web and mobile use the same exported production YOLO ONNX model, but execution occurs in different places.

### Web / Backend

```text
web browser
-> backend API
-> backend/python/analyze_grains.py
-> backend/python/grain_pipeline/
-> backend/model/best.onnx using Python ONNX Runtime
-> response/history storage
```

Important files:

- `backend/config/grain.settings.json`: shared backend runtime settings and CSV columns.
- `backend/python/grain_pipeline/pipeline.py`: response assembly and `segmentation.execution = "server_onnxruntime"`.
- `backend/python/grain_pipeline/measure.py`: measurement summaries and QC/outlier rules.
- `backend/src/routes/grain.routes.js`: analysis/history routes.
- `backend/src/controllers/grain.controller.js`: public/authenticated analysis and imported mobile runs.

### Mobile

```text
camera/gallery image
-> Flutter local preprocessing and ONNX Runtime inference
-> mobile/assets/models/best.onnx
-> local measurements/previews/history
-> optional background sync when signed in and online
```

Important files:

- `mobile/lib/features/grain/services/offline_grain_analyzer.dart`: local ONNX inference, decoding, render, measurement, QC.
- `mobile/lib/features/grain/services/grain_analysis_api.dart`: local-first analysis and pending sync behavior.
- `mobile/lib/features/grain/services/local_grain_run_store.dart`: local history/pending synchronization state.
- `mobile/lib/features/dashboard/screens/dashboard_screen.dart`: mobile analysis, preview and reference-marker UX.
- `mobile/lib/features/storage/screens/storage_screen.dart`: stored-result display.
- `mobile/lib/core/constants/app_constants.dart`: backend production URL.

Current mobile rules:

- Mobile analysis is local. Do not reintroduce text such as "Dang xu ly tren server nhu web" or upload-first processing.
- Guest users must be able to analyze locally without login, network access, MongoDB, or Python worker.
- Signed-in mobile users may sync completed local runs through `POST /api/grain/runs/import`.
- Local execution metadata must remain `mobile_onnxruntime`.
- Mobile uses `flutter_onnxruntime`, not the removed TFLite model path.

### Model Consistency Invariant

The production model files must remain byte-identical unless a deliberate model update is being released:

```text
backend/model/best.onnx
mobile/assets/models/best.onnx
```

Verify after model-related edits:

```powershell
Get-FileHash backend\model\best.onnx,mobile\assets\models\best.onnx -Algorithm SHA256
```

`best.pt` is a training/source checkpoint and is not the runtime model to ship in the APK or Azure container unless the architecture is intentionally changed.

## API Contract And URLs

Production base URL:

```text
https://seed-vanb2207577-aybrd9fwhnf3hqeq.eastasia-01.azurewebsites.net
```

Production API base URL used by mobile:

```text
https://seed-vanb2207577-aybrd9fwhnf3hqeq.eastasia-01.azurewebsites.net/api
```

Key routes:

```text
GET  /api/grain/health
POST /api/grain/analyze-public    guest/server web analysis, no database history
POST /api/grain/analyze           authenticated server web analysis
POST /api/grain/runs/import       authenticated import of pending mobile local runs
GET  /api/grain/runs              authenticated stored history
GET  /api/grain/runs/:id          authenticated run detail
```

Results are expected to support consistent preview modes on web and mobile:

```text
overlay / Danh dau
mask    / Hinh dang
labels  / Danh so
```

UI strings in the code are Vietnamese with Unicode. Do not replace them with mojibake or remove diacritics simply because a terminal displays encoding incorrectly.

## Statistics And QC Rule

The project is no longer centered on mean values alone. Standard deviation is a primary reported statistic, but segmentation errors can distort it.

Current rule implemented in both backend and mobile:

- Compute raw standard deviation.
- Identify suspect size outliers with the MAD-based QC method.
- Compute robust standard deviation after excluding suspect regions.
- Use robust post-QC SD for reported values only when suspect regions are at most `5%` of detections.
- When suspect ratio exceeds `5%`, report raw SD and mark the result for segmentation review.

Important response metadata:

```text
summary.qc.suspect_count
summary.qc.inlier_count
summary.qc.suspect_ids
summary.qc.suspect_ratio
summary.qc.robust_used_for_reporting
summary.qc.status
```

The UI must not claim that a robust/QC-filtered SD is trustworthy when `robust_used_for_reporting` is `false`.

## UX And Web/Mobile Consistency

Preserve these current decisions unless the user explicitly requests a redesign:

- Preview defaults and naming should remain aligned between web and mobile: `Danh dau`, `Hinh dang`, `Danh so`.
- Broken optional preview images should fall back to a usable overlay rather than showing an empty frame.
- Mobile calibration/reference-marker interaction is touch-oriented and includes draggable endpoints and a magnified view while positioning points.
- Web uses mouse interaction and includes an always-visible `?` guide button next to the `Hinh anh hien thi` heading in `web/src/components/grain/DashboardPreviewPanel.jsx`.
- Mobile app branding is `Seed` with the seed/leaf-style launcher icon.

When changing a result field, display label, preview key, calibration behavior, or QC rule, inspect both web and mobile surfaces before considering the change complete.

## Validation Checklist

Choose checks according to modified scope. For a cross-platform release, run all applicable checks below before committing.

### Python Worker / Backend Pipeline

```powershell
.\backend\.venv\Scripts\python.exe -m py_compile backend\python\grain_pipeline\measure.py backend\python\grain_pipeline\pipeline.py
```

Run real-image analysis when inference/statistics/output-contract behavior changes. Available local fixtures include:

```text
test_images/sample.jpg
test_images/Cac-loai-hat-giong-co-xuat-xu-da-dang.jpg
```

For QC changes, verify at least:

- a low-suspect image where `robust_used_for_reporting = true`;
- a high-suspect image where `robust_used_for_reporting = false` and `status = "review_required"`.

The backend `npm run lint --workspace=backend` command was found not runnable on 2026-05-24 because `eslint` is not available in the installed backend dependencies. Do not falsely report that lint passed; either fix the tooling as part of an explicit task or state the limitation.

### Web

```powershell
cd D:\seed\web
npm run build
```

The current Vite build may warn that a minified JavaScript chunk exceeds 500 kB. This is a known non-blocking warning, not a successful reason to skip functional verification.

### Mobile

```powershell
cd D:\seed\mobile
dart format <changed .dart files>
flutter analyze
flutter test
flutter build apk --release
Copy-Item -Force build\app\outputs\flutter-apk\app-release.apk ..\seed.apk
```

The Android release build may emit a non-blocking CupertinoIcons/font warning while still succeeding.

### Deployment-Sensitive Checks

Before publishing model-related work:

```powershell
Get-FileHash D:\seed\backend\model\best.onnx,D:\seed\mobile\assets\models\best.onnx -Algorithm SHA256
```

Before committing:

```powershell
git diff --check
git status --short --branch
```

## Azure Deployment Facts

Azure deployment is now automated from GitHub Actions; it is not a manual restart workflow.

Verified infrastructure:

```text
Azure Web App:             seed-vanb2207577
Production slot:           Production
Production hostname:       seed-vanb2207577-aybrd9fwhnf3hqeq.eastasia-01.azurewebsites.net
Azure subscription label:  Azure for Students
Azure Container Registry:  seedregistryvanb
Container image name:      seed-fullapp
GitHub organization:       vanduongcs
GitHub repository:         seed
Deployment branch:         deploy-prototype
Workflow file:             .github/workflows/deploy-prototype_seed-vanb2207577.yml
```

Current deployment flow:

```text
push to deploy-prototype
-> GitHub Actions checks out repository
-> Docker builds from root Dockerfile with context .
-> image is pushed to seedregistryvanb.azurecr.io with a commit-SHA tag
-> Azure Web App Production slot is updated to that image
-> verify production API
```

Do not tell the user to merely restart Azure after a code push. Restart only reloads the currently configured image; it does not build GitHub changes. GitHub Actions must succeed for new code to reach the Azure container.

The workflow uses GitHub/Azure secret references for registry and federated Azure authentication. Their values must remain secret. An agent may inspect workflow status and public production endpoints, but must not attempt to print or commit credential values.

## Post-Deployment Verification

After any push intended for production:

1. Check the GitHub Actions run for the pushed commit and wait for `conclusion = success`.
2. Request the Azure health endpoint.
3. For backend/result-contract changes, call `POST /api/grain/analyze-public` with a local fixture and inspect response fields.
4. For web UI changes, request `/`, identify the deployed `/assets/index-*.js` bundle, and verify the expected new string/behavior is in that production bundle when practical.
5. For mobile-only changes, report the APK location and build verification; Azure does not distribute the APK automatically.

Example API verification:

```powershell
$base = 'https://seed-vanb2207577-aybrd9fwhnf3hqeq.eastasia-01.azurewebsites.net/api'
Invoke-RestMethod -Uri "$base/grain/health"

curl.exe --silent --show-error --max-time 240 `
  -F "image=@D:\seed\test_images\sample.jpg;type=image/jpeg" `
  "$base/grain/analyze-public"
```

For the current release, a production analysis response should include:

```text
segmentation.execution = "server_onnxruntime"
summary.qc.robust_used_for_reporting
summary.qc.status
```

## Known Recent Release State

As of 2026-05-25 (Asia/Bangkok), production deployment has been verified after these commits on `deploy-prototype`:

```text
4e0e2b3  feat: run mobile ONNX locally and report QC deviation
53da1de  Add or update the Azure App Service build and deployment workflow config
52fb287  fix: show calibration guide action before image selection
```

Verified production observations after `52fb287`:

- Azure served a web bundle containing `Xem hướng dẫn căn mốc` and `Hướng dẫn căn vật mốc`.
- Public server analysis returned `segmentation.execution = "server_onnxruntime"`.
- Public server analysis returned the new `summary.qc` metadata.
- A dense test image produced `robust_used_for_reporting = false` with `status = "review_required"`, as intended.

## How To Approach Future Requests

When the user asks for a fix or feature:

1. Read this file and `git status` first.
2. Inspect only the relevant modules, plus the matching web/mobile surface if behavior should be consistent.
3. Identify whether the request affects local mobile inference, server inference, stored result compatibility, calibration UX, or deployment.
4. Implement narrowly without reverting user work.
5. Run validation appropriate to risk.
6. If the user requested publication/deployment, commit and push only reviewed changes to `deploy-prototype`, monitor GitHub Actions, and verify production.
7. State clearly what is fixed, what was validated, what was deployed, and any remaining limitation.
