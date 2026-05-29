"""Export MobileSAM encoder + decoder to ONNX.

Run once with the system Python (which has mobile_sam, torch, timm):
    python scripts/export_mobile_sam_onnx.py

Outputs:
    backend/model/mobile_sam_encoder.onnx  (~27 MB)
    backend/model/mobile_sam_decoder.onnx  (~16 MB)

These two files together replace both FastSAM-s.onnx (45 MB) and the
GrabCut/edge-snap post-processor. At inference time:
  1. Run encoder once per image -> image_embedding [1, 256, 64, 64]
  2. For each grain bbox: run decoder -> mask + iou_predictions
Total extra time for N grains ~= encoder_time + N * decoder_time
                               ~= 0.5s        + N * 0.05s
"""

from __future__ import annotations

import sys
import pathlib
import warnings
import numpy as np

warnings.filterwarnings("ignore")

ROOT      = pathlib.Path(__file__).resolve().parents[1]
MODEL_DIR = ROOT / "backend" / "model"
MODEL_DIR.mkdir(parents=True, exist_ok=True)

CHECKPOINT  = ROOT / "artifacts" / "models" / "mobile_sam.pt"
ENC_OUT     = MODEL_DIR / "mobile_sam_encoder.onnx"
DEC_OUT     = MODEL_DIR / "mobile_sam_decoder.onnx"
OPSET       = 12
IMAGE_SIZE  = 1024  # MobileSAM always uses 1024x1024

print(f"\n=== MobileSAM ONNX Export ===")
print(f"Checkpoint : {CHECKPOINT}")
print(f"Encoder    : {ENC_OUT}")
print(f"Decoder    : {DEC_OUT}")
print()

if not CHECKPOINT.exists():
    sys.exit(f"ERROR: {CHECKPOINT} not found. Place mobile_sam.pt under artifacts/models.")

import torch
from mobile_sam import sam_model_registry

sam = sam_model_registry["vit_t"](checkpoint=str(CHECKPOINT))
sam.eval()

# 1. Export image encoder.

print("[1/2] Exporting image encoder...")

class EncoderWrapper(torch.nn.Module):
    def __init__(self, encoder):
        super().__init__()
        self.encoder = encoder

    def forward(self, image: torch.Tensor):
        return self.encoder(image)

encoder_wrapper = EncoderWrapper(sam.image_encoder).eval()
dummy_image = torch.zeros(1, 3, IMAGE_SIZE, IMAGE_SIZE, dtype=torch.float32)

with torch.no_grad():
    torch.onnx.export(
        encoder_wrapper,
        dummy_image,
        str(ENC_OUT),
        opset_version=OPSET,
        input_names=["image"],
        output_names=["image_embedding"],
        dynamic_axes={
            "image":           {0: "batch"},
            "image_embedding": {0: "batch"},
        },
        verbose=False,
    )

size_mb = ENC_OUT.stat().st_size / 1024 / 1024
print(f"   Saved: {ENC_OUT}  ({size_mb:.1f} MB)")


# 2. Export mask decoder.

print("[2/2] Exporting mask decoder...")

class DecoderWrapper(torch.nn.Module):
    """Wraps SAM's prompt encoder + mask decoder for bbox-prompted inference."""
    def __init__(self, sam_model):
        super().__init__()
        self.sam = sam_model

    def forward(
        self,
        image_embedding: torch.Tensor,   # [1, 256, 64, 64]
        boxes: torch.Tensor,             # [1, 4]  xyxy in 1024-space
    ):
        sparse_embeddings, dense_embeddings = self.sam.prompt_encoder(
            points=None,
            boxes=boxes,
            masks=None,
        )
        low_res_masks, iou_predictions = self.sam.mask_decoder(
            image_embeddings=image_embedding,
            image_pe=self.sam.prompt_encoder.get_dense_pe(),
            sparse_prompt_embeddings=sparse_embeddings,
            dense_prompt_embeddings=dense_embeddings,
            multimask_output=True,
        )
        return low_res_masks, iou_predictions

decoder_wrapper = DecoderWrapper(sam).eval()

embed_size = IMAGE_SIZE // 16  # = 64
dummy_embedding = torch.zeros(1, 256, embed_size, embed_size, dtype=torch.float32)
dummy_boxes     = torch.zeros(1, 4, dtype=torch.float32)

with torch.no_grad():
    torch.onnx.export(
        decoder_wrapper,
        (dummy_embedding, dummy_boxes),
        str(DEC_OUT),
        opset_version=OPSET,
        input_names=["image_embedding", "boxes"],
        output_names=["low_res_masks", "iou_predictions"],
        verbose=False,
    )

size_mb = DEC_OUT.stat().st_size / 1024 / 1024
print(f"   Saved: {DEC_OUT}  ({size_mb:.1f} MB)")

print()
print("=== Export complete ===")
print(f"Encoder : {ENC_OUT.stat().st_size//1024} KB")
print(f"Decoder : {DEC_OUT.stat().st_size//1024} KB")
print(f"Total   : {(ENC_OUT.stat().st_size+DEC_OUT.stat().st_size)//1024} KB")
print()
print("You can now use mobile_sam_encoder.onnx + mobile_sam_decoder.onnx")
print("in the backend pipeline for fast, high-quality grain segmentation.")
