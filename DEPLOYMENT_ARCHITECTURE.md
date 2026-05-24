# Seed Deployment Architecture

The project has two inference targets that use the same exported YOLO segmentation model.

## Web And Server

```text
browser
-> backend API
-> Python worker
-> backend/model/best.onnx with ONNX Runtime
-> result JSON, previews, CSV, and stored history
```

The production server model is tracked at `backend/model/best.onnx` so a clean Docker or Azure source deployment contains the required model asset.

## Android Mobile

```text
camera/gallery
-> Flutter preprocessing
-> mobile/assets/models/best.onnx with ONNX Runtime
-> local segmentation, measurements, previews, and pending history
-> optional backend sync when signed in and online
```

Normal analysis is local-first and works for guests without internet. The backend is used for login, history import, and synchronization; mobile analysis does not upload the source image for server inference.

The mobile model is the same production ONNX export as the server model. This preserves model output consistency while avoiding Python/PyTorch runtime packaging on Android.

## Shared Result Contract

Both paths return the same preview modes: overlay, mask, and labels. Both calculate standard deviation and QC metadata. MAD-based outlier screening is informational; the robust post-QC deviation is used as the reported value only when suspect regions are at most 5 percent of detections. Above that threshold, the reported value stays as raw standard deviation and the UI requires segmentation review.

## Deploy Checklist

1. Keep `backend/model/best.onnx` and `mobile/assets/models/best.onnx` byte-identical.
2. Run Python pipeline checks, Flutter analyze/tests/release APK build, and web production build.
3. Push the deployment branch used by Azure.
4. Confirm the deployed API responds and exposes the updated result contract before accepting production output.
