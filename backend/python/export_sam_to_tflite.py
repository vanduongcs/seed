#!/usr/bin/env python3
"""
Export SAM/MobileSAM model sang TFLite format cho mobile.

Hỗ trợ:
- MobileSAM (TinyViT) -> TFLite
- SAM2 Tiny (Hiera) -> TFLite

Yêu cầu:
  pip install onnx onnxruntime onnx_tf tensorflow-cpu
  pip install segment-anything  # hoặc mobile-sam

Usage:
  python export_sam_to_tflite.py --checkpoint models/mobile_sam.pt --output models/seed_segmentation.tflite
  python export_sam_to_tflite.py --checkpoint models/sam2_tiny.pt --output models/seed_segmentation.tflite
  python export_sam_to_tflite.py --checkpoint models/mobile_sam.pt --quantize float16
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Optional

import numpy as np
import torch


# ── Constants ────────────────────────────────────────────────────
MOBILE_INPUT_SIZE = 256  # Mobile tối ưu với input nhỏ
DEFAULT_INPUT_SIZE = 512


def build_mobile_segmentation_model(checkpoint_path: str, input_size: int = MOBILE_INPUT_SIZE) -> torch.nn.Module:
    """Xây dựng mô hình segmentation đơn giản hóa từ SAM/MobileSAM checkpoint.

    Trả về một torch.nn.Module wrapper nhận input (1, 3, H, W) và output (1, 1, H, W).
    """
    checkpoint = Path(checkpoint_path)

    # ── Thử load MobileSAM ──────────────────────────────────────
    try:
        from mobile_sam import sam_model_registry

        model = sam_model_registry["vit_t"](checkpoint=str(checkpoint))
        model.eval()

        class MobileSAMWrapper(torch.nn.Module):
            def __init__(self, sam_model, img_size):
                super().__init__()
                self.sam = sam_model
                self.img_size = img_size

            def forward(self, x):
                # x: (B, 3, H, W) float32 [0..1] hoặc uint8
                # SAM cần uint8 [0..255]
                if x.dtype != torch.uint8:
                    x = (x * 255).clamp(0, 255).to(torch.uint8)

                B, C, H, W = x.shape
                # Dùng image_encoder lấy feature
                with torch.no_grad():
                    image_embedding = self.sam.image_encoder(x)
                    # image_embedding: (B, 256, 64, 64) với input 1024x1024
                    # Upsample về kích thước gốc
                    mask = torch.nn.functional.interpolate(
                        image_embedding.mean(dim=1, keepdim=True),
                        size=(H, W),
                        mode="bilinear",
                        align_corners=False,
                    )
                    mask = torch.sigmoid(mask)
                return mask

        return MobileSAMWrapper(model, input_size)

    except ImportError:
        pass

    # ── Thử load SAM2 ───────────────────────────────────────────
    try:
        from sam2.build_sam import build_sam2

        if "tiny" in checkpoint.stem.lower():
            config = "sam2.1_hiera_tiny.yaml"
        elif "small" in checkpoint.stem.lower():
            config = "sam2.1_hiera_small.yaml"
        else:
            config = "sam2.1_hiera_tiny.yaml"

        model = build_sam2(config, str(checkpoint), device="cpu")
        model.eval()

        class SAM2Wrapper(torch.nn.Module):
            def __init__(self, sam2_model, img_size):
                super().__init__()
                self.sam2 = sam2_model
                self.img_size = img_size

            def forward(self, x):
                if x.dtype != torch.uint8:
                    x = (x * 255).clamp(0, 255).to(torch.uint8)

                B, C, H, W = x.shape
                with torch.no_grad():
                    backbone_out = self.sam2.image_encoder(x)
                    if hasattr(backbone_out, 'features'):
                        features = backbone_out.features[-1]
                    elif isinstance(backbone_out, dict):
                        features = list(backbone_out.values())[-1]
                    else:
                        features = backbone_out

                    mask = torch.nn.functional.interpolate(
                        features.mean(dim=1, keepdim=True) if features.dim() == 4 else features,
                        size=(H, W),
                        mode="bilinear",
                        align_corners=False,
                    )
                    mask = torch.sigmoid(mask)
                return mask

        return SAM2Wrapper(model, input_size)

    except ImportError:
        pass

    # ── Fallback: Dùng segment-anything ─────────────────────────
    try:
        from segment_anything import sam_model_registry

        model = sam_model_registry["vit_t"](checkpoint=str(checkpoint))
        model.eval()

        class SAMFallbackWrapper(torch.nn.Module):
            def __init__(self, sam_model, img_size):
                super().__init__()
                self.sam = sam_model
                self.img_size = img_size

            def forward(self, x):
                if x.dtype != torch.uint8:
                    x = (x * 255).clamp(0, 255).to(torch.uint8)

                B, C, H, W = x.shape
                with torch.no_grad():
                    image_embedding = self.sam.image_encoder(x)
                    mask = torch.nn.functional.interpolate(
                        image_embedding.mean(dim=1, keepdim=True),
                        size=(H, W),
                        mode="bilinear",
                        align_corners=False,
                    )
                    mask = torch.sigmoid(mask)
                return mask

        return SAMFallbackWrapper(model, input_size)

    except ImportError:
        raise ImportError(
            "Cần cài ít nhất một trong các thư viện:\n"
            "  pip install mobile-sam\n"
            "  pip install segment-anything\n"
            "  pip install segment-anything-2\n"
        )


def export_to_onnx(model: torch.nn.Module, input_size: int, output_path: Path) -> Path:
    """Export model sang ONNX format."""
    model.eval()
    dummy_input = torch.randn(1, 3, input_size, input_size).clamp(0, 1)

    onnx_path = output_path.with_suffix(".onnx")
    torch.onnx.export(
        model,
        dummy_input,
        str(onnx_path),
        input_names=["input"],
        output_names=["output"],
        dynamic_axes={
            "input": {2: "height", 3: "width"},
            "output": {2: "height", 3: "width"},
        },
        opset_version=17,
    )
    print(f"✅ ONNX exported: {onnx_path}")
    return onnx_path


def onnx_to_tflite(onnx_path: Path, output_path: Path, quantize: Optional[str] = None) -> Path:
    """Convert ONNX sang TFLite."""
    try:
        import onnx
        from onnx_tf.backend import prepare
    except ImportError:
        raise ImportError("Cần cài: pip install onnx onnx_tf tensorflow-cpu")

    onnx_model = onnx.load(str(onnx_path))
    tf_rep = prepare(onnx_model)

    import tensorflow as tf

    # Convert TF model to TFLite
    converter = tf.lite.TFLiteConverter.from_saved_model(tf_rep.path)

    if quantize == "float16":
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.target_spec.supported_types = [tf.float16]
    elif quantize == "int8":
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    else:
        converter.optimizations = [tf.lite.Optimize.DEFAULT]

    tflite_model = converter.convert()

    with open(output_path, "wb") as f:
        f.write(tflite_model)

    print(f"✅ TFLite exported: {output_path} ({len(tflite_model) / 1024:.0f}KB)")
    return output_path


def direct_tflite_export(model: torch.nn.Module, input_size: int, output_path: Path, quantize: Optional[str] = None) -> Path:
    """Export model trực tiếp sang TFLite qua ONNX pipeline."""
    onnx_path = output_path.with_suffix(".onnx")
    try:
        export_to_onnx(model, input_size, onnx_path)
        tflite_path = onnx_to_tflite(onnx_path, output_path, quantize)
    finally:
        # Dọn dẹp ONNX temp
        if onnx_path.exists():
            onnx_path.unlink()
    return tflite_path


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Export SAM model sang TFLite cho mobile",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Ví dụ:
  python export_sam_to_tflite.py --checkpoint models/mobile_sam.pt
  python export_sam_to_tflite.py --checkpoint models/sam2_tiny.pt --quantize float16
  python export_sam_to_tflite.py --checkpoint models/mobile_sam.pt --input-size 256 --output mobile/assets/models/seed_segmentation.tflite
        """,
    )
    parser.add_argument("--checkpoint", required=True, help="Đường dẫn model .pt")
    parser.add_argument("--output", default="models/seed_segmentation.tflite", help="Output TFLite path")
    parser.add_argument("--input-size", type=int, default=MOBILE_INPUT_SIZE, help=f"Input size (default: {MOBILE_INPUT_SIZE})")
    parser.add_argument("--quantize", choices=["float16", "int8"], default=None, help="Loại quantization")

    args = parser.parse_args()

    print(f"📦 Loading model từ: {args.checkpoint}")
    model = build_mobile_segmentation_model(args.checkpoint, args.input_size)
    print(f"   Model type: {type(model).__name__}")
    print(f"   Input size: {args.input_size}x{args.input_size}")

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    direct_tflite_export(model, args.input_size, output_path, args.quantize)

    print(f"\n💡 Copy file này vào mobile/assets/models/seed_segmentation.tflite")
    print(f"   Sau đó chạy: cd mobile && flutter pub get && flutter run")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
