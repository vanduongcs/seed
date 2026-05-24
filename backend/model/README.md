# YOLO Grain Model

Place one trained YOLOv8 segmentation model in this folder:

- `best.onnx`
- `best.pt`

The backend worker auto-loads `best.onnx` first, then `best.pt`. If neither file exists, development falls back to `yolov8n-seg.pt`.

`best.onnx` is tracked for reproducible server deployments. Training checkpoints such as `best.pt` and optional experimental refiners remain local artifacts.
