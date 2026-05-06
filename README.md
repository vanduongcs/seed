# Seed

Seed là monorepo cho ứng dụng đa nền tảng:

- `backend`: Express API, MongoDB, JWT auth và chat service.
- `web`: React + Vite web app.
- `mobile`: Flutter mobile app.
- `shared`: constants và validators dùng chung.

## Tech Stack

- Backend: Node.js, Express, Mongoose, Socket.IO, JWT, Zod
- Web: React, Vite, Material UI, Zustand, Axios
- Mobile: Flutter, Riverpod, GoRouter, Dio
- Database: MongoDB

## Cài đặt

Yêu cầu:

- Node.js >= 18
- npm >= 9
- MongoDB
- Flutter SDK nếu chạy mobile

Cài dependencies:

```bash
npm install
```

Tạo file môi trường:

```bash
cp .env.example .env
```

Trên Windows PowerShell:

```powershell
Copy-Item .env.example .env
```

Cập nhật `.env` theo môi trường local của bạn. Các biến thường cần đổi:

```env
PORT=3000
MONGODB_URI=mongodb://localhost:27017/seed_db
JWT_ACCESS_SECRET=your_access_secret_here
JWT_REFRESH_SECRET=your_refresh_secret_here
ALLOWED_ORIGINS=http://localhost:5173
```

## Chạy project

Trên Windows, có thể mở menu chạy nhanh bằng file:

```powershell
.\run.bat
```

Menu này có các lựa chọn:

- Run web
- Run mobile app
- Run all

Chạy backend và web cùng lúc:

```bash
npm run dev
```

Hoặc chạy riêng:

```bash
npm run dev:backend
npm run dev:web
```

URL mặc định:

- Backend: `http://localhost:3000`
- Health check: `http://localhost:3000/health`
- Web: `http://localhost:5173`

## Chạy mobile

```bash
cd mobile
flutter pub get
flutter run
```

Mặc định mobile dùng API:

```text
http://10.0.2.2:3000/api
```

Nếu chạy trên thiết bị thật, truyền IP máy đang chạy backend:

```bash
flutter run --dart-define=BASE_URL=http://192.168.1.x:3000/api
```

## Scripts

```bash
npm run dev              # chạy backend + web
npm run dev:backend      # chạy backend
npm run dev:web          # chạy web
npm run build:web        # build web
```

## Lưu ý

- Không commit `.env`.
- Commit `.env.example`.
- Đổi JWT secrets trước khi deploy.
