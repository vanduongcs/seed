"""SAM model helper for grain analysis.

Supports: MobileSAM, SAM2, FastSAM.
Usage: provides binary foreground mask for analyze_grains.py integration.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import numpy as np
import torch

logger = logging.getLogger(__name__)

_MODEL_CACHE = {}
_DEVICE = None


def get_device():
    """Get optimal torch device."""
    global _DEVICE
    if _DEVICE is None:
        if torch.cuda.is_available():
            _DEVICE = torch.device("cuda")
        elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            _DEVICE = torch.device("mps")
        else:
            _DEVICE = torch.device("cpu")
    return _DEVICE


@dataclass
class SAMResult:
    mask: object
    score: object
    elapsed_ms: float
    model_name: str
    device: str


@dataclass
class SAMInstanceResult:
    masks: list
    elapsed_ms: float
    model_name: str
    device: str


def _load_mobile_sam(checkpoint, device):
    """Load MobileSAM model."""
    cp = str(checkpoint)

    # Try mobile_sam package first
    try:
        from mobile_sam import sam_model_registry as reg
        from mobile_sam import SamAutomaticMaskGenerator as Gen

        m = reg["vit_t"](checkpoint=cp)
        m.to(device)
        m.eval()
        g = Gen(model=m, points_per_side=32, pred_iou_thresh=0.88,
                stability_score_thresh=0.92, min_mask_region_area=100)
        return g, "mobile_sam_lib"
    except ImportError:
        pass

    # Try segment-anything with vit_t
    try:
        from segment_anything import sam_model_registry as reg, SamAutomaticMaskGenerator as Gen

        m = reg["vit_t"](checkpoint=cp)
        m.to(device)
        m.eval()
        g = Gen(model=m, points_per_side=32, pred_iou_thresh=0.88,
                stability_score_thresh=0.92, min_mask_region_area=100)
        return g, "sam_vit_t"
    except Exception:
        pass

    # Fallback: vit_b
    from segment_anything import sam_model_registry as reg, SamAutomaticMaskGenerator as Gen

    m = reg["vit_b"](checkpoint=cp)
    m.to(device)
    m.eval()
    g = Gen(model=m, points_per_side=32, pred_iou_thresh=0.88,
            stability_score_thresh=0.92, min_mask_region_area=100)
    return g, "sam_vit_b_fallback"


def _load_sam2(checkpoint, device):
    """Load SAM2 model."""
    try:
        from sam2.build_sam import build_sam2
        from sam2.automatic_mask_generator import SAM2AutomaticMaskGenerator
    except ImportError:
        raise ImportError("Need SAM2: pip install segment-anything-2")

    cp = str(checkpoint)
    s = checkpoint.stem.lower()

    if "tiny" in s:
        cfg = "sam2.1_hiera_tiny.yaml"
    elif "small" in s:
        cfg = "sam2.1_hiera_small.yaml"
    elif "base" in s:
        cfg = "sam2.1_hiera_base_plus.yaml"
    elif "large" in s:
        cfg = "sam2.1_hiera_large.yaml"
    else:
        cfg = "sam2.1_hiera_tiny.yaml"

    m = build_sam2(cfg, cp, device=device)
    m.eval()

    g = SAM2AutomaticMaskGenerator(
        model=m, points_per_side=32, pred_iou_thresh=0.8,
        stability_score_thresh=0.88, min_mask_region_area=100)
    return g, "sam2"


def _load_fast_sam(checkpoint, device):
    """Load FastSAM model."""
    try:
        from ultralytics import FastSAM
    except ImportError:
        raise ImportError("Need ultralytics: pip install ultralytics")
    return FastSAM(str(checkpoint)), "fast_sam"


def load_sam_model(checkpoint_path, model_type="auto", device=None):
    """Load SAM model and return (model_object, resolved_type_string)."""
    cp = Path(checkpoint_path)
    if not cp.exists():
        raise FileNotFoundError(f"Checkpoint not found: {checkpoint_path}")

    if device is None:
        device = get_device()

    ck = f"{model_type}:{cp}"
    if ck in _MODEL_CACHE:
        return _MODEL_CACHE[ck]

    resolved = model_type
    if model_type == "auto":
        s = cp.stem.lower()
        if "fast" in s or "yolo" in s:
            resolved = "fast_sam"
        elif "sam2" in s or "hiera" in s:
            resolved = "sam2"
        elif "mobile" in s:
            resolved = "mobile_sam"
        else:
            resolved = "mobile_sam"

    logger.info("Loading %s from %s on %s", resolved, cp, device)

    if resolved == "mobile_sam":
        model, st = _load_mobile_sam(cp, device)
    elif resolved == "sam2":
        model, st = _load_sam2(cp, device)
    elif resolved == "fast_sam":
        model, st = _load_fast_sam(cp, device)
    else:
        raise ValueError(f"Unknown model_type: {model_type}")

    _MODEL_CACHE[ck] = (model, st)
    return model, st


def _resize_mask(mask: np.ndarray, shape: tuple[int, int]) -> np.ndarray:
    if mask.shape == shape:
        return mask.astype(bool)
    import cv2

    resized = cv2.resize(
        mask.astype(np.uint8),
        (shape[1], shape[0]),
        interpolation=cv2.INTER_NEAREST,
    )
    return resized.astype(bool)


def _clamp_int(value, low: int, high: int, default: int) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        parsed = default
    return max(low, min(high, parsed))


def _clamp_float(value, low: float, high: float, default: float) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        parsed = default
    return max(low, min(high, parsed))


def _coerce_bool(value, default: bool = False) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return default


def _fast_sam_predict(model, image, device, params: dict):
    conf = _clamp_float(params.get("samConf"), 0.01, 0.95, 0.16)
    iou = _clamp_float(params.get("samIou"), 0.1, 0.95, 0.62)
    max_det = _clamp_int(params.get("samMaxDet"), 300, 3000, 1200)
    return model(
        image,
        device=str(device),
        retina_masks=True,
        conf=conf,
        iou=iou,
        max_det=max_det,
    )


def _fast_sam_masks_for_image(model, image, device, params: dict) -> list[np.ndarray]:
    h, w = image.shape[:2]
    results = _fast_sam_predict(model, image, device, params)
    if not results:
        return []
    result = results[0]
    if result.masks is None or len(result.masks.data) == 0:
        return []
    return [
        _resize_mask(mask, (h, w))
        for mask in result.masks.data.cpu().numpy() > 0.5
    ]


def _generate_fast_sam_tiled_masks(model, image, device, params: dict) -> list[np.ndarray]:
    h, w = image.shape[:2]
    tile_size = _clamp_int(params.get("samTileSize"), 320, 1600, 768)
    overlap = _clamp_int(params.get("samTileOverlap"), 0, tile_size // 2, 96)
    if h <= tile_size and w <= tile_size:
        return _fast_sam_masks_for_image(model, image, device, params)

    stride = max(1, tile_size - overlap)
    y_starts = list(range(0, max(1, h - tile_size + 1), stride))
    x_starts = list(range(0, max(1, w - tile_size + 1), stride))
    if not y_starts or y_starts[-1] != max(0, h - tile_size):
        y_starts.append(max(0, h - tile_size))
    if not x_starts or x_starts[-1] != max(0, w - tile_size):
        x_starts.append(max(0, w - tile_size))

    masks: list[np.ndarray] = []
    for y0 in y_starts:
        for x0 in x_starts:
            y1 = min(h, y0 + tile_size)
            x1 = min(w, x0 + tile_size)
            tile = image[y0:y1, x0:x1]
            tile_masks = _fast_sam_masks_for_image(model, tile, device, params)
            for tile_mask in tile_masks:
                full_mask = np.zeros((h, w), dtype=bool)
                full_mask[y0:y1, x0:x1] = tile_mask[: y1 - y0, : x1 - x0]
                masks.append(full_mask)
    return masks


def generate_instance_masks(model, model_type, image, device=None, params: dict | None = None) -> list[np.ndarray]:
    """Generate separate instance masks from SAM/FastSAM."""
    import time

    if device is None:
        device = get_device()
    params = params or {}

    t0 = time.perf_counter()

    if model_type == "fast_sam":
        if _coerce_bool(params.get("samUseTiling"), True):
            masks = _generate_fast_sam_tiled_masks(model, image, device, params)
        else:
            masks = _fast_sam_masks_for_image(model, image, device, params)
        elapsed = (time.perf_counter() - t0) * 1000
        logger.info("FastSAM: %d instance masks in %.0fms", len(masks), elapsed)
        return masks

    if model_type in ("mobile_sam_lib", "sam_vit_t", "sam_vit_b_fallback", "sam2"):
        generated = model.generate(image)
        if not generated:
            logger.warning("SAM: no masks")
            return []
        masks = [_resize_mask(md["segmentation"], (h, w)) for md in generated]
        elapsed = (time.perf_counter() - t0) * 1000
        logger.info("SAM: %d instance masks in %.0fms", len(masks), elapsed)
        return masks

    raise ValueError(f"Unknown model_type: {model_type}")


def generate_mask(model, model_type, image, device=None, params: dict | None = None):
    """Generate binary foreground mask from RGB image.

    Args:
        model: loaded model object
        model_type: resolved type string
        image: RGB uint8 numpy array (H, W, 3)
        device: torch device

    Returns:
        bool numpy array (H, W), True = foreground
    """
    import time

    if device is None:
        device = get_device()
    params = params or {}

    t0 = time.perf_counter()
    h, w = image.shape[:2]

    if model_type == "fast_sam":
        masks = generate_instance_masks(model, model_type, image, device, params)
        if not masks:
            return np.zeros((h, w), dtype=bool)
        combined = np.stack(masks, axis=0).max(axis=0)
        elapsed = (time.perf_counter() - t0) * 1000
        logger.info("FastSAM: %d masks in %.0fms", len(masks), elapsed)
        return combined.astype(bool)

    elif model_type in ("mobile_sam_lib", "sam_vit_t", "sam_vit_b_fallback"):
        masks = model.generate(image)
        if not masks:
            logger.warning("SAM: no masks")
            return np.zeros((h, w), dtype=bool)
        combined = np.zeros((h, w), dtype=bool)
        for md in sorted(masks, key=lambda x: x.get("predicted_iou", 0), reverse=True):
            seg = md["segmentation"]
            overlap = combined & seg
            if overlap.sum() / max(seg.sum(), 1) < 0.7:
                combined |= seg
        elapsed = (time.perf_counter() - t0) * 1000
        logger.info("SAM: %d masks in %.0fms", len(masks), elapsed)
        return combined

    elif model_type == "sam2":
        masks = model.generate(image)
        if not masks:
            logger.warning("SAM2: no masks")
            return np.zeros((h, w), dtype=bool)
        combined = np.zeros((h, w), dtype=bool)
        for md in masks:
            combined |= md["segmentation"]
        elapsed = (time.perf_counter() - t0) * 1000
        logger.info("SAM2: %d masks in %.0fms", len(masks), elapsed)
        return combined

    raise ValueError(f"Unknown model_type: {model_type}")


def run_sam_pipeline(image, checkpoint_path, model_type="auto"):
    """Run full SAM pipeline and return SAMResult."""
    import time

    t0 = time.perf_counter()
    device = get_device()
    model, resolved = load_sam_model(checkpoint_path, model_type, device)
    mask = generate_mask(model, resolved, image, device)
    elapsed = (time.perf_counter() - t0) * 1000

    return SAMResult(
        mask=mask,
        score=mask.astype(np.float32),
        elapsed_ms=elapsed,
        model_name=resolved,
        device=str(device),
    )


def run_sam_instance_pipeline(image, checkpoint_path, model_type="auto", params: dict | None = None):
    """Run SAM and return separate instance masks."""
    import time

    t0 = time.perf_counter()
    device = get_device()
    model, resolved = load_sam_model(checkpoint_path, model_type, device)
    masks = generate_instance_masks(model, resolved, image, device, params)
    elapsed = (time.perf_counter() - t0) * 1000

    return SAMInstanceResult(
        masks=masks,
        elapsed_ms=elapsed,
        model_name=resolved,
        device=str(device),
    )


def clear_cache():
    """Clear model cache."""
    _MODEL_CACHE.clear()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()
    logger.info("SAM cache cleared")
