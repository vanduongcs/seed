# YOLO Grain Model

Place one trained YOLOv8 segmentation model in this folder:

- `best.onnx`
- `best.pt`

The backend worker auto-loads `best.onnx` first, then `best.pt`. If neither file exists, development falls back to `yolov8n-seg.pt`.

Model binaries are ignored by git.
