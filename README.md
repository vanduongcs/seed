# SeedVision

SeedVision là hệ thống phân tích ảnh hạt giống từ ảnh chụp thực tế. Dự án dùng mô hình YOLO segmentation dạng ONNX để nhận diện từng hạt, đo kích thước theo mask, tính thống kê, đánh dấu hạt nghi ngờ và lưu lịch sử phân tích.

Repository này là monorepo gồm backend, web và mobile. Web phân tích ảnh qua backend. Mobile là Flutter app theo hướng local-first: có thể phân tích trực tiếp trên thiết bị bằng ONNX Runtime, kể cả khi người dùng chưa đăng nhập hoặc không có mạng.

## Trạng Thái Hiện Tại

- Backend production chạy bằng Express, Python worker và ONNX Runtime.
- Web production là React/Vite được build vào container backend.
- Mobile hiện có Android runner trong `mobile/android`.
- Chưa có iOS runner được commit trong repo. Người build iOS cần tạo runner iOS trên macOS từ Flutter project hiện có trong `mobile/`.
- Runtime model hiện tại:
  - Server: `backend/model/main_model/best.onnx`
  - Mobile safe 640: `mobile/assets/models/best_mobile_yolo26_640.onnx`
  - Mobile high-quality 1024 int8: `mobile/assets/models/best_1024_int8_static.onnx`

## Sơ Đồ Thư Mục

```text
backend/
  src/                         Express API, auth, MongoDB models, controllers
  src/routes/                  Danh sách route HTTP
  src/controllers/             Logic xử lý request
  python/analyze_grains.py     Entry point worker phân tích ảnh
  python/grain_pipeline/       YOLO segmentation, đo mask, QC, render preview
  model/main_model/best.onnx   ONNX model server production

web/
  src/App.jsx                  React Router root
  src/api/axios.js             Axios clients và refresh-token interceptor
  src/pages/                   Login, Register, Dashboard, Storage, Account
  src/components/grain/        Preview, bảng kết quả, chart, format
  src/store/auth.store.js      Auth/guest state bằng Zustand
  src/i18n.jsx                 Song ngữ Việt/Anh

mobile/
  lib/main.dart                Flutter app root
  lib/core/router/             GoRouter routes
  lib/core/network/            Dio client, base URL resolver, token refresh
  lib/core/i18n/               Song ngữ Việt/Anh
  lib/features/dashboard/      Màn phân tích ảnh chính
  lib/features/storage/        Lịch sử local/server
  lib/features/account/        Tài khoản, guest mode, ngôn ngữ
  lib/features/grain/services/ Offline analyzer, API mapper, local run store
  android/                     Android runner hiện có
  assets/models/               ONNX model mobile

shared/                        Hằng số và validator dùng chung cho JS
scripts/                       Script local/export release
test_images/                   Ảnh mẫu kiểm thử pipeline
Dockerfile                     Build web, backend và Python worker cho Azure
```

## Các Luồng Tương Tác Chính

### Web phân tích qua backend

```text
Browser
-> web/src/pages/DashboardPage.jsx
-> POST /api/grain/analyze-public hoặc /api/grain/analyze
-> backend/src/controllers/grain.controller.js
-> backend/python/analyze_grains.py
-> backend/python/grain_pipeline/
-> backend/model/main_model/best.onnx
-> JSON kết quả + preview PNG + CSV
-> MongoDB nếu người dùng đã đăng nhập
```

Web không chạy ONNX trong browser. Mọi phân tích web đi qua backend/Python worker.

### Mobile phân tích local-first

```text
Camera hoặc gallery
-> mobile/lib/features/dashboard/screens/dashboard_screen.dart
-> OfflineGrainAnalyzer
-> flutter_onnxruntime
-> mobile/assets/models/*.onnx
-> đo mask, QC, preview, CSV
-> LocalGrainRunStore lưu lịch sử local
-> POST /api/grain/runs/import nếu người dùng đăng nhập và có mạng
```

Mobile guest vẫn phân tích được mà không cần backend, MongoDB hoặc đăng nhập. Backend chỉ cần cho đăng nhập, đồng bộ lịch sử và xem lại các run đã lưu trên server.

### Đăng nhập và đồng bộ

```text
Web/mobile auth screen
-> /api/auth/login hoặc /api/auth/register
-> accessToken + refreshToken
-> request riêng tư gắn Authorization Bearer
-> /api/auth/refresh khi access token gần hết hạn
-> mobile import pending local runs qua /api/grain/runs/import
```

## API Backend App Đang Dùng

Base URL local:

```text
http://localhost:3000/api
```

Base URL production:

```text
https://seed-vanb2207577-aybrd9fwhnf3hqeq.eastasia-01.azurewebsites.net/api
```

README này chỉ ghi các API phục vụ web/mobile SeedVision hiện tại. Không liệt kê các route thử nghiệm hoặc module phụ không nằm trong luồng sản phẩm chính.

### Auth và tài khoản

Web và mobile dùng nhóm này để đăng nhập, refresh token, lấy profile và đồng bộ dữ liệu người dùng.

| Method | Path | Auth | Mục đích |
| --- | --- | --- | --- |
| `POST` | `/api/auth/register` | No | Tạo tài khoản |
| `POST` | `/api/auth/login` | No | Đăng nhập |
| `POST` | `/api/auth/refresh` | No | Lấy access token mới từ refresh token |
| `POST` | `/api/auth/logout` | Yes | Đăng xuất |
| `GET` | `/api/auth/me` | Yes | Kiểm tra phiên đăng nhập hiện tại |
| `GET` | `/api/users/me` | Yes | Lấy profile |
| `PATCH` | `/api/users/me` | Yes | Cập nhật profile |

File liên quan:

```text
backend/src/routes/auth.routes.js
backend/src/routes/user.routes.js
backend/src/controllers/auth.controller.js
backend/src/config/env.js
backend/src/utils/jwt.util.js
web/src/api/axios.js
web/src/store/auth.store.js
mobile/lib/core/network/api_client.dart
mobile/lib/features/auth/providers/auth_provider.dart
```

### Phân tích hạt và lịch sử

| Method | Path | Auth | Mục đích |
| --- | --- | --- | --- |
| `GET` | `/api/grain/health` | No | Kiểm tra worker và default params |
| `POST` | `/api/grain/analyze-public` | No | Web guest gửi ảnh lên server để phân tích, không lưu MongoDB |
| `POST` | `/api/grain/analyze` | Yes | Web user đã đăng nhập gửi ảnh lên server để phân tích và lưu run |
| `GET` | `/api/grain/runs` | Yes | Danh sách run của user |
| `POST` | `/api/grain/runs/import` | Yes | Mobile đồng bộ các run đã phân tích local lên server |
| `GET` | `/api/grain/runs/:id` | Yes | Chi tiết một run |
| `PUT` | `/api/grain/runs/:id/result` | Yes | Cập nhật kết quả sau chỉnh QC |
| `DELETE` | `/api/grain/runs/:id` | Yes | Xóa run |

Hai endpoint `analyze-public` và `analyze` chỉ dùng cho web/server inference. Mobile mặc định không gọi hai endpoint này để phân tích ảnh; mobile chạy ONNX local trong `OfflineGrainAnalyzer`, sau đó chỉ import kết quả đã có qua `/api/grain/runs/import`.

Web gửi request phân tích bằng `multipart/form-data` từ `web/src/pages/DashboardPage.jsx`:

```text
image=<file>
```

Nếu người dùng đã vẽ vật mốc trên web, `DashboardPage.jsx` gửi thêm các field sau. Backend nhận chúng qua `req.body`, chuẩn hóa bằng `normalizeGrainParams()` rồi chuyển cho Python worker:

```text
referencePixels       Độ dài đoạn mốc theo pixel trên ảnh gốc
referenceMm           Độ dài thật của đoạn mốc, đơn vị mm
referencePixelSpace   Thường là original
referenceX1/Y1        Điểm đầu đoạn mốc trên ảnh gốc
referenceX2/Y2        Điểm cuối đoạn mốc trên ảnh gốc
```

Nếu không có `referenceMm`, hệ thống vẫn đếm/đo theo pixel nhưng các field mm có thể để trống. Nếu có `referenceMm`, backend tính `mm_per_pixel` và điền `length_mm`, `width_mm`, `area_mm2`.

File liên quan:

```text
backend/src/routes/grain.routes.js
backend/src/controllers/grain.controller.js
backend/src/services/grainProcessing.service.js
backend/config/grain.settings.json
backend/python/analyze_grains.py
backend/python/grain_pipeline/pipeline.py
web/src/pages/DashboardPage.jsx
mobile/lib/features/grain/services/offline_grain_analyzer.dart
mobile/lib/features/grain/services/grain_analysis_api.dart
mobile/lib/features/grain/services/local_grain_run_store.dart
```

## Response Phân Tích Hạt

Các nhóm field quan trọng:

```text
image                  Kích thước ảnh xử lý, scale
summary.count          Số hạt
summary.area_px        Thống kê diện tích pixel
summary.length_px      Thống kê chiều dài pixel
summary.width_px       Thống kê chiều rộng pixel
summary.qc             Thống kê hạt nghi ngờ
segmentation           Thông tin model, runtime, số candidate, filter
calibration            Trạng thái quy đổi pixel -> mm
measurements[]         Dòng đo từng hạt
csv                    CSV xuất dữ liệu
*_png_base64           Preview ảnh
label_map_png_base64   Label map để edit đúng mask
```

Mỗi measurement thường có:

```text
id
area_px
length_px
width_px
area_mm2
length_mm
width_mm
centroid_x
centroid_y
bbox_x
bbox_y
bbox_w
bbox_h
angle_deg
solidity
extent
aspect_ratio
measurement_method
confidence
quality_flags
qc_outlier
qc_reason
```

`measurement_method` hiện là:

```text
smartgrain_feret_chord
```

Nghĩa là:

- `length_px`: đường Feret dài nhất trên biên mask.
- `width_px`: đoạn cross-section lớn nhất vuông góc với trục dài, đo trong chính mask.
- Không dùng width/height của hộp bao quanh axis-aligned.
- Không dùng `minAreaRect` làm kích thước báo cáo chính.

## QC Và Thống Kê

Hệ thống không tin tuyệt đối mọi mask. Sau khi đo, pipeline chạy QC:

- Tính raw mean và raw standard deviation.
- Dùng MAD đa chỉ số để tìm hạt nghi ngờ.
- Một hạt chỉ bị nghi ngờ khi ít nhất hai trong ba chỉ số `area_px`, `length_px`, `width_px` vượt ngưỡng robust-z.
- Tính robust SD sau khi loại hạt nghi ngờ.
- Chỉ dùng robust SD để báo cáo khi tỷ lệ nghi ngờ không quá 5%.
- Nếu tỷ lệ nghi ngờ cao hơn, kết quả giữ raw SD và yêu cầu người dùng xem lại.

Các field QC chính:

```text
summary.qc.suspect_count
summary.qc.inlier_count
summary.qc.suspect_ids
summary.qc.suspect_ratio
summary.qc.robust_used_for_reporting
summary.qc.status
```

Web và mobile đều có luồng chỉnh hạt nghi ngờ thủ công. Người dùng click/tap vào mask để đổi trạng thái `qc_outlier`, sau đó app tính lại summary và CSV.

## Bản Đồ Chỉnh Sửa Nhanh

Phần này dùng khi người mới vào repo cần biết muốn sửa một hành vi thì mở file nào trước.

### Backend và Python worker

| Muốn chỉnh | Mở file |
| --- | --- |
| Thêm/sửa endpoint grain | `backend/src/routes/grain.routes.js`, `backend/src/controllers/grain.controller.js` |
| Đổi default tham số inference, cột CSV | `backend/config/grain.settings.json` |
| Đổi cách gọi Python worker | `backend/src/services/grainProcessing.service.js` |
| Đổi pipeline phân tích tổng thể | `backend/python/grain_pipeline/pipeline.py` |
| Đổi decode YOLO ONNX, mask threshold, tiled/full pass | `backend/python/grain_pipeline/yolo_segment.py` |
| Đổi cách đo length/width/area, calibration, QC, split/merge | `backend/python/grain_pipeline/measure.py` |
| Đổi overlay/mask/labels/label map preview | `backend/python/grain_pipeline/render.py` |
| Đổi fallback khi YOLO phát hiện thiếu hạt | `backend/python/grain_pipeline/classical_fallback.py` |

### Web

| Muốn chỉnh | Mở file |
| --- | --- |
| Route login/register/app shell | `web/src/App.jsx`, `web/src/components/Layout.jsx` |
| Chọn ảnh, vẽ vật mốc, gửi FormData phân tích | `web/src/pages/DashboardPage.jsx` |
| Preview overlay/mask/labels và click mask chỉnh QC | `web/src/components/grain/DashboardPreviewPanel.jsx` |
| Summary kết quả, bảng/charts | `web/src/components/grain/DashboardResultPanel.jsx`, `web/src/components/grain/GrainStatsCharts.jsx` |
| Lịch sử phân tích | `web/src/pages/StoragePage.jsx` |
| Tài khoản, guest mode, ngôn ngữ | `web/src/pages/AccountPage.jsx` |
| Base API, refresh token, public/private client | `web/src/api/axios.js` |
| Auth state web | `web/src/store/auth.store.js` |
| Text song ngữ | `web/src/i18n.jsx` |

### Mobile

| Muốn chỉnh | Mở file |
| --- | --- |
| Route `/login`, `/register`, `/dashboard`, `/storage`, `/account` | `mobile/lib/core/router/app_router.dart` |
| Bottom navigation | `mobile/lib/features/main/screens/main_shell.dart` |
| Màn phân tích, chọn ảnh, vẽ vật mốc, edit QC | `mobile/lib/features/dashboard/screens/dashboard_screen.dart` |
| Local ONNX inference, preprocess, decode mask, đo mask, QC, preview | `mobile/lib/features/grain/services/offline_grain_analyzer.dart` |
| Result model, áp calibration sau phân tích, export CSV, sync/import | `mobile/lib/features/grain/services/grain_analysis_api.dart` |
| Lưu lịch sử local và pending sync | `mobile/lib/features/grain/services/local_grain_run_store.dart` |
| Màn lịch sử local/server | `mobile/lib/features/storage/screens/storage_screen.dart` |
| Base API, Dio, refresh token | `mobile/lib/core/network/api_client.dart`, `mobile/lib/core/constants/app_constants.dart` |
| Text song ngữ mobile | `mobile/lib/core/i18n/app_language.dart` |
| Android MethodChannel cho update và memory info | `mobile/android/app/src/main/kotlin/.../MainActivity.kt` |

Khi sửa thuật toán đo hoặc QC, cần sửa đồng bộ cả backend và mobile:

```text
backend/python/grain_pipeline/measure.py
mobile/lib/features/grain/services/offline_grain_analyzer.dart
mobile/lib/features/grain/services/grain_analysis_api.dart
```

## Cài Đặt Local

Yêu cầu:

- Node.js 18+
- npm 9+
- Python 3.10+ hoặc 3.11+
- MongoDB nếu chạy backend local đầy đủ
- Flutter SDK
- Android SDK nếu build Android
- macOS + Xcode nếu build iOS

Cài Node dependencies:

```powershell
npm install
```

Tạo `.env`:

```powershell
Copy-Item .env.example .env
```

Không dùng secret mẫu cho production. Các biến quan trọng:

```text
PORT=3000
MONGODB_URI=mongodb://localhost:27017/seed_db
JWT_ACCESS_SECRET=...
JWT_REFRESH_SECRET=...
JWT_LEGACY_ACCESS_SECRETS=
JWT_LEGACY_REFRESH_SECRETS=
ALLOWED_ORIGINS=http://localhost:5173,http://localhost:3000
GRAIN_PROCESS_PROFILE=surface_quality
GRAIN_DEFAULT_PARAMS_JSON=
```

Cài Python worker:

```powershell
Push-Location backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r python\requirements.txt
Pop-Location
```

Chạy backend và web:

```powershell
npm run dev
```

Chạy riêng:

```powershell
npm run dev:backend
npm run dev:web
```

Địa chỉ local:

```text
Web:     http://localhost:5173
Backend: http://localhost:3000
API:     http://localhost:3000/api
```

## Build Web

```powershell
npm run build:web
```

Vite có thể cảnh báo chunk lớn hơn 500 kB. Đây là cảnh báo đã biết, không đồng nghĩa build fail.

## Chạy Và Build Android

```powershell
Push-Location mobile
flutter pub get
flutter run
Pop-Location
```

Build APK release:

```powershell
Push-Location mobile
flutter build apk --release
Pop-Location
```

APK output:

```text
mobile/build/app/outputs/flutter-apk/app-release.apk
```

Script export release local:

```powershell
scripts\export_mobile_release.bat
```

Output release local:

```text
artifacts/releases/
```

## Ghi Chú Build iOS

Repo hiện chưa commit thư mục `mobile/ios`. Người build iOS cần dùng máy macOS có Xcode và Flutter, sau đó tạo iOS runner từ Flutter project hiện tại:

```bash
cd mobile
flutter create --platforms=ios .
flutter pub get
open ios/Runner.xcworkspace
```

Các việc cần cấu hình trong Xcode:

- Bundle identifier, ví dụ `vn.mekonglab.seedvision`.
- Signing team và provisioning profile.
- Deployment target phù hợp với plugin đang dùng.
- App icon, display name và launch screen nếu cần.
- Quyền camera/photo library trong `Info.plist`.
- Network access nếu dùng backend local hoặc production API.

Các asset/model cần giữ trong `mobile/pubspec.yaml`:

```text
assets/models/best_1024_int8_static.onnx
assets/models/best_mobile_yolo26_640.onnx
```

Lưu ý iOS:

- `OfflineGrainAnalyzer` đã bỏ qua profile 1024 dựa trên `device_memory` khi không phải Android, nên iOS mặc định dùng safe profile 640.
- Android có MethodChannel `vn.mekonglab.seedvision/device_memory`; iOS không bắt buộc phải implement channel này.
- Android có MethodChannel `vn.mekonglab.seedvision/app_update` để mở Play Store. Nếu bật update gate trên iOS, cần thêm iOS handler mở App Store hoặc điều chỉnh flow update cho iOS.
- Không thể build iOS trực tiếp trên Windows. Cần macOS/Xcode.

Build thử iOS:

```bash
cd mobile
flutter run -d ios
flutter build ipa --release
```

## Base URL Mobile

Production mặc định nằm trong:

```text
mobile/lib/core/constants/app_constants.dart
```

Mặc định:

```text
https://seed-vanb2207577-aybrd9fwhnf3hqeq.eastasia-01.azurewebsites.net/api
```

Override khi chạy local:

```powershell
flutter run --dart-define=BASE_URL=http://192.168.1.x:3000/api
```

Android emulator gọi backend máy host bằng:

```text
http://10.0.2.2:3000/api
```

Điện thoại thật cần cùng mạng Wi-Fi với máy chạy backend và firewall mở cổng `3000`.

## Kiểm Thử

Backend Python:

```powershell
.\backend\.venv\Scripts\python.exe -m py_compile backend\python\grain_pipeline\measure.py backend\python\grain_pipeline\pipeline.py backend\python\grain_pipeline\yolo_segment.py backend\python\grain_pipeline\render.py backend\python\grain_pipeline\mask_refine.py backend\python\grain_pipeline\classical_fallback.py
```

Web:

```powershell
npm run build:web
```

Mobile:

```powershell
Push-Location mobile
flutter analyze
flutter test
flutter build apk --release
Pop-Location
```

Smoke test backend local:

```powershell
$env:PYTHONPATH='backend\python'
@'
from pathlib import Path
from grain_pipeline.pipeline import analyze_image
result = analyze_image(Path(r'test_images\sample.jpg'), {})
print(result['summary']['count'])
print(result['segmentation']['execution'])
print(result['measurements'][0]['measurement_method'])
'@ | backend\.venv\Scripts\python.exe -
```

Smoke test production:

```powershell
$base = 'https://seed-vanb2207577-aybrd9fwhnf3hqeq.eastasia-01.azurewebsites.net/api'
Invoke-RestMethod -Uri "$base/grain/health"

curl.exe --silent --show-error --max-time 300 `
  -F "image=@test_images\sample.jpg;type=image/jpeg" `
  "$base/grain/analyze-public"
```

## Deploy Production

Production chạy trên Azure Web App:

```text
https://seed-vanb2207577-aybrd9fwhnf3hqeq.eastasia-01.azurewebsites.net
```

Luồng deploy:

```text
push main
-> GitHub Actions
-> Docker build từ root Dockerfile
-> push image lên Azure Container Registry
-> Azure Web App deploy image mới
-> kiểm /api/grain/health và analyze-public
```

Workflow hiện dùng:

```text
.github/workflows/deploy-main_seed-vanb2207577.yml
```

## Các File Không Nên Commit

Không commit:

- `.env`
- secret thật
- file báo cáo `.docx`, `.xml`
- dataset local như `GS_IT/`, `SeedPheno/`
- `outputs/`
- checkpoint huấn luyện `.pt`
- artifact release ngoài `artifacts/releases/`
- file test/validation tạm nếu không cần cho runtime

Chỉ commit README khi tài liệu public cần cập nhật.

## Checklist Cho Người Mới Vào Repo

1. Đọc `README.md` này để hiểu cấu trúc.
2. Chạy `npm install`.
3. Tạo `.env` từ `.env.example`.
4. Cài Python worker trong `backend/.venv`.
5. Chạy `npm run dev` để mở web/backend local.
6. Vào `mobile/`, chạy `flutter pub get`.
7. Build Android bằng `flutter build apk --release`.
8. Nếu cần iOS, tạo `mobile/ios` trên macOS bằng `flutter create --platforms=ios .`, cấu hình signing và test lại ONNX runtime.
