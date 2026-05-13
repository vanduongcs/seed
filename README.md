# Seed

Seed là hệ thống đa nền tảng phục vụ phân tích hình thái hạt giống từ ảnh. Ứng dụng cho phép người dùng import ảnh hoặc lấy ảnh từ camera, tự động tách vùng hạt, đo kích thước từng hạt và xuất kết quả dạng CSV/PNG để phục vụ kiểm tra mẫu trong phòng thí nghiệm.

Project được tổ chức theo mô hình monorepo, gồm backend API, web dashboard, mobile app và package shared dùng chung.

## Mục Tiêu

Seed tập trung vào ba nhu cầu chính:

- Nhận dạng và segment hạt giống từ ảnh RGB.
- Đo các chỉ số hình thái cơ bản như số lượng, diện tích, chiều dài và chiều rộng.
- Cung cấp giao diện web/mobile để thao tác, xem overlay và xuất dữ liệu.

Pipeline xử lý ảnh được cấu hình tập trung ở backend để web/mobile luôn chạy cùng một bộ tham số khi deploy.

## Kiến Trúc

```text
seed/
├─ backend/   Express API, MongoDB, JWT auth, Python image worker
├─ web/       React + Vite + Material UI dashboard
├─ mobile/    Flutter app
└─ shared/    Constants và validators dùng chung
```

Luồng xử lý chính:

1. Web hoặc mobile gửi ảnh đến backend qua `POST /api/grain/analyze`.
2. Backend lưu ảnh vào thư mục tạm và gọi Python worker.
3. Python worker chạy pipeline segment/measurement và trả JSON.
4. Backend trả kết quả gồm thống kê, measurements, CSV, overlay PNG và các ảnh debug mask/cluster.
5. Web hiển thị overlay, mask, labels, bảng thống kê và cho phép export.

## Thành Phần

### Backend

Backend dùng Node.js, Express và MongoDB. Các nhóm API chính gồm:

- Auth: đăng ký, đăng nhập, refresh token.
- AI chat: hội thoại với provider được cấu hình.
- Grain analysis: nhận ảnh, chạy Python worker và trả kết quả đo hạt.

Python worker nằm tại:

```text
backend/python/analyze_grains.py
```

Worker xử lý ảnh độc lập với server Node, giúp phần computer vision dễ phát triển và kiểm thử riêng.

### Web

Web dashboard nằm trong `web/`, dùng React, Vite, Material UI, Zustand và Axios.

Dashboard phân tích hạt hỗ trợ:

- Import ảnh JPG/PNG hoặc lấy frame từ camera.
- Chạy phân tích ảnh qua backend.
- Xem overlay, clusters, mask, seed mask, KMeans mask và labels.
- Sử dụng cấu hình xử lý tập trung từ backend; tham số nâng cao được đặt bằng file/env khi deploy.
- Export CSV measurements và PNG overlay.

### Mobile

Mobile app nằm trong `mobile/`, dùng Flutter. Ứng dụng cung cấp auth flow, dashboard phân tích ảnh, storage và account screen. Mobile dùng chung backend API với web để đảm bảo cùng một pipeline segmentation/measurement trên cả hai nền tảng.

Luồng mobile chính: chọn ảnh hoặc camera trong Dashboard mobile, gửi ảnh đến `POST /api/grain/analyze`, nhận lại overlay/mask/labels/clusters, thống kê count/area/length/width, và export CSV/PNG qua share sheet của hệ điều hành. Storage mobile cũng mở được chi tiết run đã lưu và export lại artifact giống web.

Pipeline nặng như SAM/FastSAM, PCA/KMeans, dynamic threshold và watershed chạy trên backend để dễ deploy, dễ cập nhật model và tránh lệch kết quả giữa web/mobile. Nếu cần offline thật trong tương lai, model TFLite nên được huấn luyện/export riêng nhưng phải giữ schema output tương thích với API hiện tại.

### Shared

Package `shared/` chứa constants và validators có thể tái sử dụng giữa các app.

## Pipeline Xử Lý Ảnh

Pipeline hiện tại mô phỏng hướng xử lý kiểu GridFree nhưng được điều chỉnh cho codebase này:

1. Đọc ảnh RGB, xoay theo EXIF và resize theo `maxSide`.
2. Tạo color feature bank gồm RGB, PAT, DIF, ROO, GLD, chroma và intensity.
3. Chạy PCA theo correlation cho RGB PCA và index PCA.
4. Blend RGB/index PCA bằng `rgbIndexWeight`.
5. Chạy KMeans để tách cluster foreground/background.
6. Tạo seedness mask dựa trên hue, saturation, LAB yellow score, texture và khoảng cách nền lấy từ viền ảnh.
7. Kết hợp seed mask với KMeans mask ở chế độ `auto`/`hybrid`.
8. Lọc foreground components trước watershed bằng area, border, solidity, extent, aspect ratio, seedness và local contrast.
9. Ước lượng threshold động từ connected components hợp lệ.
10. Chạy watershed để tách hạt dính nhau.
11. Lọc segment sau watershed bằng area, length, width, aspect ratio, solidity, extent và mean seedness.
12. Đo contour và xuất CSV/overlay.

Các output đo chính:

- `count`
- `area_px`, `area_mm2`
- `length_px`, `length_mm`
- `width_px`, `width_mm`
- centroid, bounding box, angle, solidity, extent, aspect ratio

Nếu có `referencePixels` và `referenceMm`, worker sẽ tính thêm đơn vị mm. Mặc định `referencePixels` được hiểu là số pixel trên ảnh gốc; nếu client gửi số pixel theo ảnh đã resize trong worker thì dùng `referencePixelSpace=processed`.

## API Phân Tích Hạt

```text
POST /api/grain/analyze
```

Route yêu cầu bearer token giống các API có xác thực khác.

Multipart form:

- `image`: file JPG/PNG.
- Các field tùy chọn từ client: calibration (`referencePixels`, `referenceMm`, `referencePixelSpace`, `referenceX1`, `referenceY1`, `referenceX2`, `referenceY2`).

Các tham số xử lý hiện được cấu hình tập trung, không gửi từ web/mobile:

```text
maxSide
pcIndex
k
rgbIndexWeight
pcaMethod
minArea
maxArea
minLength
maxLength
splitSensitivity
openingRadius
closingRadius
noiseSize
holeSize
seednessThreshold
maskSource
dynamicThresholds
markerShrinkFactor
maskMinArea
maxSegmentAspectRatio
minSegmentSolidity
minSegmentExtent
referencePixels
referenceMm
referencePixelSpace
```

Web/mobile không expose và backend không nhận override các tham số xử lý từ request public. Cấu hình mặc định nằm ở:

```text
backend/src/config/grain.defaults.js
```

Khi deploy có thể override bằng biến môi trường `GRAIN_DEFAULT_PARAMS_JSON`, ví dụ:

```env
GRAIN_DEFAULT_PARAMS_JSON={"maskSource":"hybrid","maxSide":1800,"splitSensitivity":7}
```

Response trả về:

- `summary`: thống kê tổng quan.
- `measurements`: danh sách từng hạt.
- `csv`: nội dung CSV.
- `overlay_png_base64`: ảnh overlay kết quả.
- `cluster_png_base64`, `mask_png_base64`, `seed_mask_png_base64`, `kmeans_mask_png_base64`, `labels_png_base64`: ảnh debug.
- `segmentation`: thông tin marker, mask pixels, thresholds và số segment trước lọc.

Health endpoint:

```text
GET /api/grain/health
```

## Công Nghệ

- Backend: Node.js, Express, Mongoose, Socket.IO, JWT, Zod, Multer
- Image processing: Python, OpenCV, NumPy, SciPy, scikit-image, scikit-learn, Pillow
- Web: React, Vite, Material UI, Zustand, Axios
- Mobile: Flutter, Riverpod, GoRouter, Dio
- Database: MongoDB

## Cấu Hình Môi Trường

Các biến môi trường mẫu nằm trong `.env.example`.

Các biến quan trọng:

```env
PORT=3000
MONGODB_URI=mongodb://localhost:27017/seed_db
JWT_ACCESS_SECRET=your_access_secret_here
JWT_REFRESH_SECRET=your_refresh_secret_here
ALLOWED_ORIGINS=http://localhost:5173
GRAIN_PROCESS_TIMEOUT_MS=180000
GRAIN_PYTHON_BIN=
GRAIN_DEFAULT_PARAMS_JSON=
```

Nếu `GRAIN_PYTHON_BIN` không được đặt, backend sẽ ưu tiên Python trong `backend/.venv`, sau đó fallback sang `python` hoặc `python3`.

## Chạy Local

Yêu cầu:

- Node.js >= 18
- npm >= 9
- MongoDB
- Python 3.10+ cho image worker
- Flutter SDK nếu chạy mobile

Cài dependencies Node:

```bash
npm install
```

Tạo file môi trường:

```powershell
Copy-Item .env.example .env
```

Tạo Python virtual environment thủ công nếu không dùng `run.bat`:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r python\requirements.txt
cd ..
```

Chạy backend và web:

```bash
npm run dev
```

Chạy riêng:

```bash
npm run dev:backend
npm run dev:web
```

URL mặc định:

- Web: `http://localhost:5173`
- Backend: `http://localhost:3000`
- Backend health: `http://localhost:3000/health`
- Grain worker health: `http://localhost:3000/api/grain/health`

Trên Windows có thể dùng launcher:

```powershell
.\run.bat
```

Launcher sẽ tự tạo `backend/.venv` và cài Python dependencies nếu virtual environment chưa tồn tại.

## Chạy Mobile

```bash
cd mobile
flutter pub get
flutter run
```

Android emulator dùng backend mặc định:

```text
http://10.0.2.2:3000/api
```

Khi chạy trên thiết bị thật, truyền IP của máy đang chạy backend:

```bash
flutter run --dart-define=BASE_URL=http://192.168.1.x:3000/api
```

## Scripts

```bash
npm run dev              # chạy backend + web
npm run dev:backend      # chạy backend
npm run dev:web          # chạy web
npm run build:web        # build web
npm run install:all      # cài dependencies workspace
```

## Vận Hành Và Bảo Mật

- `.env` và các file môi trường local không được commit.
- `.env.example` là contract cấu hình cho môi trường mới.
- JWT secrets mặc định chỉ phù hợp cho development.
- API phân tích ảnh giới hạn upload JPG/PNG và file size 25 MB.
- Python worker chạy trong thư mục tạm và backend xóa file tạm sau khi xử lý.
- Kết quả đo phụ thuộc chất lượng ảnh, ánh sáng, nền và tham số lọc; với nền phức tạp nên kiểm tra thêm preview `Mask`, `Clusters` và `Labels`.
