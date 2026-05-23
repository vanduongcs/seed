# Seed Segmentation Deployment Architecture

The project should be deployed as two independent inference targets.

## Target A: Web / Public Demo

The web target runs inference on a server.

```text
browser
-> upload image
-> server API
-> YOLO ONNX model on server
-> overlay/result returned to browser
```

Implementation:

```text
seed_deploy/
├── app.py
├── Dockerfile
├── model/best.onnx
└── grain_pipeline/
```

Use this for:

- public demo
- web upload page
- REST API
- Hugging Face Spaces / Render / VPS deployment

Do not include mobile-only assets or Flutter code in this server Docker image.

## Target B: Android APK / Offline Mobile

The Android target must run inference on-device.

```text
Android camera/gallery
-> local preprocessing
-> TFLite model inside APK
-> local YOLO segmentation decode
-> local overlay/result
```

Current model asset:

```text
mobile/assets/models/best_float16.tflite
```

Normal mobile analysis should not require internet. If internet is available, the app may optionally sync history or compare/debug results with the server, but the primary path should remain local.

## Current Status

Server/web:

- YOLO ONNX server inference works in Docker.
- `/segment` returns overlay PNG.
- `/analyze` returns JSON with measurements and overlay base64.

Mobile:

- TFLite model asset exists.
- Flutter dependencies include `tflite_flutter` and `image`.
- Full local YOLO-seg decode/postprocess is not implemented yet.
- Current mobile UI still uses backend API for analysis.

## Correct Next Mobile Work

Implement mobile offline inference in this order:

1. Load `assets/models/best_float16.tflite` with `tflite_flutter`.
2. Inspect and document input/output tensor shapes.
3. Match server preprocessing:
   - EXIF-safe image load if possible
   - RGB
   - pad to square
   - resize to model input size
   - normalize to `[0, 1]`
4. Decode YOLO-seg outputs:
   - boxes
   - class scores
   - mask coefficients
   - prototype masks
5. Run local NMS.
6. Generate instance masks.
7. Render overlay locally.
8. Port morphology measurements:
   - area
   - bbox
   - centroid
   - length/width approximation
   - count
9. Make the mobile dashboard use offline analyzer first.
10. Keep backend API as an optional debug/sync fallback, not the default path.

## Model Format Rule

Use different model formats for different targets:

```text
Server/web:  ONNX  -> seed_deploy/model/best.onnx
Mobile APK:  TFLite -> mobile/assets/models/best_float16.tflite
```

Do not ship ONNX/Python/OpenCV server code inside the Flutter APK.
