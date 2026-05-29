# SeedVision

SeedVision là hệ thống phân tích ảnh hạt giống từ ảnh chụp thực tế. Ứng dụng dùng mô hình YOLO segmentation dạng ONNX để nhận diện từng hạt, đo kích thước, tính thống kê và đánh dấu các vùng nghi ngờ do lỗi tách mask hoặc ngoại lệ hình học.

Repository này là monorepo gồm backend, web, mobile và các module dùng chung. Web phân tích ảnh qua server. Mobile có thể phân tích trực tiếp trên thiết bị bằng ONNX Runtime, không bắt buộc đăng nhập hay có mạng.

## Tính năng chính

- Tải ảnh hoặc chụp ảnh có hạt và vật mốc kích thước thật.
- Vẽ đoạn tham chiếu trên vật mốc để quy đổi từ pixel sang milimet.
- Tách từng hạt bằng YOLO segmentation ONNX.
- Tính số lượng hạt, chiều dài, chiều rộng, diện tích, trung bình và độ lệch chuẩn.
- Có QC tự động để đánh dấu hạt nghi ngờ bằng mask đỏ.
- Cho phép chỉnh QC thủ công: nhấn vào hạt để chuyển giữa nghi ngờ và hợp lệ.
- Xuất CSV số liệu và PNG preview.
- Web có lịch sử phân tích khi đăng nhập.
- Mobile lưu kết quả cục bộ và có thể đồng bộ về backend khi người dùng đăng nhập.
- APK dùng thử và AAB Play Console được export bằng script local.

## Cấu trúc thư mục

```text
backend/      Express API, MongoDB, JWT, Python image worker
web/          React + Vite + Material UI web client
mobile/       Flutter Android/mobile client
shared/       Hằng số và validator dùng chung cho JavaScript
scripts/      Script chạy local, export model và export mobile release
test_images/  Ảnh mẫu dùng để kiểm thử pipeline
Dockerfile    Docker image production: build web, serve từ backend, chạy Python worker
```

Các thư mục build, artifact release, cache, virtualenv, checkpoint huấn luyện và file môi trường local đều được giữ ngoài Git.

## Kiến trúc xử lý ảnh

### Web và backend

```text
Trình duyệt web
-> Backend API
-> backend/python/analyze_grains.py
-> backend/python/grain_pipeline/
-> backend/model/best.onnx qua Python ONNX Runtime
-> JSON kết quả, ảnh preview, CSV, lịch sử lưu trữ
```

Các route chính:

```text
GET  /api/grain/health
POST /api/grain/analyze-public
POST /api/grain/analyze
POST /api/grain/runs/import
GET  /api/grain/runs
GET  /api/grain/runs/:id
```

### Mobile

```text
Camera hoặc ảnh thư viện
-> Flutter tiền xử lý ảnh
-> mobile/assets/models/best.onnx qua flutter_onnxruntime
-> Đo mask, render preview, lưu lịch sử local
-> Tùy chọn đồng bộ backend khi đăng nhập và có mạng
```

Mobile không upload ảnh để phân tích mặc định. Người dùng guest vẫn phân tích được khi không có mạng, không đăng nhập và không có MongoDB/backend.

## Mô hình ONNX

Hai file runtime production phải luôn giống nhau về nội dung:

```text
backend/model/best.onnx
mobile/assets/models/best.onnx
```

Kiểm tra hash:

```powershell
Get-FileHash backend\model\best.onnx,mobile\assets\models\best.onnx -Algorithm SHA256
```

`best.pt` chỉ là checkpoint nguồn để export lại ONNX. File này không phải runtime chính để đóng gói APK hoặc deploy Azure.

## Quy tắc QC và thống kê

Pipeline không chỉ báo trung bình. Độ lệch chuẩn là thống kê chính, nhưng lỗi segmentation có thể làm lệch kết quả. Vì vậy hệ thống áp dụng QC:

- Tính độ lệch chuẩn thô.
- Dùng phương pháp MAD đa chỉ số để tìm hạt nghi ngờ.
- Một vùng chỉ bị đánh dấu nghi ngờ khi ít nhất hai trong ba chỉ số `area_px`, `length_px`, `width_px` vượt ngưỡng robust-z.
- Tính độ lệch chuẩn robust sau khi loại vùng nghi ngờ.
- Chỉ dùng robust SD để báo cáo khi tỷ lệ nghi ngờ không quá 5%.
- Nếu tỷ lệ nghi ngờ vượt 5%, kết quả vẫn báo raw SD và trạng thái cần xem lại segmentation.

Các trường QC quan trọng trong response:

```text
summary.qc.suspect_count
summary.qc.inlier_count
summary.qc.suspect_ids
summary.qc.suspect_ratio
summary.qc.robust_used_for_reporting
summary.qc.status
```

Preview kết quả gồm:

```text
original_png_base64
preprocessed_png_base64
overlay_png_base64
mask_png_base64
labels_png_base64
label_map_png_base64
```

`label_map_png_base64` dùng để chỉnh QC trên đúng mask thật, không vẽ mask ảo đè lên ảnh.

## Yêu cầu môi trường

- Node.js 18 trở lên.
- npm 9 trở lên.
- MongoDB cho backend local.
- Python 3.10 trở lên.
- Flutter SDK cho mobile.
- Android SDK và release keystore nếu muốn build APK/AAB release.

## Cài đặt local

Cài dependency Node:

```powershell
npm install
```

Tạo file môi trường:

```powershell
Copy-Item .env.example .env
```

Các biến quan trọng:

```text
PORT=3000
MONGODB_URI=mongodb://localhost:27017/seed_db
JWT_ACCESS_SECRET=...
JWT_REFRESH_SECRET=...
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

Chạy backend và web cùng lúc:

```powershell
npm run dev
```

Chạy riêng backend:

```powershell
npm run dev:backend
```

Chạy riêng web:

```powershell
npm run dev:web
```

Địa chỉ local thường dùng:

```text
Web:     http://localhost:5173
Backend: http://localhost:3000
API:     http://localhost:3000/api
```

## Chạy mobile

```powershell
Push-Location mobile
flutter pub get
flutter run
Pop-Location
```

Mobile tự phân tích bằng `mobile/assets/models/best.onnx`. Backend chỉ cần cho đăng nhập, đồng bộ lịch sử và xem kết quả đã lưu.

Khi chạy trên Android emulator, app có thể dùng:

```text
http://10.0.2.2:3000/api
```

Khi chạy trên điện thoại thật, máy tính chạy backend và điện thoại cần cùng mạng Wi-Fi, firewall cho phép cổng `3000`. Có thể override URL:

```powershell
flutter run --dart-define=BASE_URL=http://192.168.1.x:3000/api
```

## Export APK và AAB

Script release:

```powershell
scripts\export_mobile_release.bat
```

Output nằm trong:

```text
artifacts/releases/
```

File thường dùng:

```text
seedvision-release.apk  - cài thử trực tiếp
seedvision-release.aab  - upload Google Play Console
```

Nếu Play Console báo version code đã dùng, tăng version trong `mobile/pubspec.yaml` theo dạng:

```text
version: 1.0.1+2
```

Trong đó `1.0.1` là version hiển thị, `2` là version code Android và phải luôn tăng.

## Kiểm thử và build

Backend Python:

```powershell
.\backend\.venv\Scripts\python.exe -m py_compile backend\python\grain_pipeline\measure.py backend\python\grain_pipeline\pipeline.py backend\python\grain_pipeline\render.py
```

Web:

```powershell
Push-Location web
npm run build
Pop-Location
```

Mobile:

```powershell
Push-Location mobile
flutter analyze
flutter test
Pop-Location
```

Kiểm tra model server/mobile:

```powershell
Get-FileHash backend\model\best.onnx,mobile\assets\models\best.onnx -Algorithm SHA256
```

## Deploy production

Production Azure hiện được triển khai bằng GitHub Actions từ nhánh `main`.

Luồng deploy:

```text
push lên main
-> GitHub Actions build Docker image từ Dockerfile
-> push image lên Azure Container Registry
-> cập nhật Azure Web App Production slot
-> backend serve web build và API trên port 3000
```

Workflow nằm tại:

```text
.github/workflows/deploy-main_seed-vanb2207577.yml
```

Azure Web App production:

```text
https://seed-vanb2207577-aybrd9fwhnf3hqeq.eastasia-01.azurewebsites.net
```

API production:

```text
https://seed-vanb2207577-aybrd9fwhnf3hqeq.eastasia-01.azurewebsites.net/api
```

Kiểm tra health sau deploy:

```powershell
$base = 'https://seed-vanb2207577-aybrd9fwhnf3hqeq.eastasia-01.azurewebsites.net/api'
Invoke-RestMethod -Uri "$base/grain/health"
```

Azure App Service không cần chọn branch nếu đang dùng container image do GitHub Actions cập nhật. Điều cần đúng là workflow GitHub Actions phải trigger trên `main` và action deploy thành công.

## Quy tắc Git

- Nhánh production chính: `main`.
- Không commit secret, `.env`, keystore, mật khẩu registry, MongoDB URI production hoặc GitHub/Azure secret.
- Không commit APK/AAB, build output, cache, virtualenv hoặc artifact local.
- Chỉ giữ tài liệu Markdown chính trong `README.md`.
- Trước khi push production nên chạy kiểm thử phù hợp và kiểm tra:

```powershell
git diff --check
git status --short --branch
```
