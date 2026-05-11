"""Integrate SAM model into analyze_grains.py pipeline.

Provides build_sam_mask() that can replace or complement the existing
KMeans+seedness mask. Call from analyze() when params['maskSource'] == 'sam'.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Optional

import numpy as np

logger = logging.getLogger(__name__)

SAM_CHECKPOINT = None  # Set by analyze() or via env


def resolve_sam_checkpoint(params: dict) -> Optional[Path]:
    """Resolve SAM checkpoint path from params or default locations."""
    # Explicit path from params
    if params.get("samCheckpoint"):
        p = Path(params["samCheckpoint"])
        if p.exists():
            return p

    model_type = str(params.get("samModelType") or "auto").lower()

    # Default paths
    models_dir = Path(__file__).resolve().parent / "models"
    if model_type == "fast_sam":
        candidates = [
            models_dir / "FastSAM-x.pt",
            models_dir / "FastSAM-s.pt",
            models_dir / "FastSAM-x.onnx",
        ]
    elif model_type == "sam2":
        candidates = [
            models_dir / "sam2_tiny.pt",
            models_dir / "sam2_small.pt",
        ]
    elif model_type == "mobile_sam":
        candidates = [
            models_dir / "mobile_sam.pt",
        ]
    else:
        candidates = [
            models_dir / "FastSAM-x.pt",
            models_dir / "mobile_sam.pt",
            models_dir / "sam2_tiny.pt",
            models_dir / "sam2_small.pt",
        ]
    for cand in candidates:
        if cand.exists():
            return cand

    return None


def build_sam_mask(
    image: np.ndarray,
    params: dict,
    checkpoint: Optional[Path] = None,
) -> np.ndarray:
    """Generate SAM foreground mask for the given RGB image.

    Args:
        image: RGB uint8 image (H, W, 3)
        params: processing parameters (samModelType, samCheckpoint, etc.)
        checkpoint: Optional explicit checkpoint path

    Returns:
        Binary mask (H, W) dtype bool
    """
    from sam_helper import run_sam_pipeline

    if checkpoint is None:
        checkpoint = resolve_sam_checkpoint(params)

    if checkpoint is None:
        logger.warning(
            "SAM checkpoint not found. Download with: "
            "python download_sam_model.py --model mobile_sam"
        )
        # Fallback: return empty mask (all background)
        return np.zeros(image.shape[:2], dtype=bool)

    model_type = params.get("samModelType", "auto")

    logger.info("Running SAM pipeline: checkpoint=%s type=%s", checkpoint, model_type)
    result = run_sam_pipeline(image, str(checkpoint), model_type)

    logger.info(
        "SAM completed: %d foreground pixels (%.1f%%), %.0fms on %s",
        result.mask.sum(),
        100.0 * result.mask.mean(),
        result.elapsed_ms,
        result.device,
    )

    return result.mask


def build_sam_labels(
    image: np.ndarray,
    params: dict,
    checkpoint: Optional[Path] = None,
) -> tuple[np.ndarray, dict]:
    """Generate labeled instance masks from SAM/FastSAM.

    Returns:
        labels: int32 array (H, W), 0 = background, 1..N = instances
        summary: details for response/debugging
    """
    from sam_helper import run_sam_instance_pipeline

    if checkpoint is None:
        checkpoint = resolve_sam_checkpoint(params)

    if checkpoint is None:
        logger.warning(
            "SAM checkpoint not found. Download with: "
            "python download_sam_model.py --model fast_sam"
        )
        return np.zeros(image.shape[:2], dtype=np.int32), {
            "enabled": True,
            "error": "SAM checkpoint not found",
            "instance_count": 0,
        }

    model_type = params.get("samModelType", "auto")
    result = run_sam_instance_pipeline(image, str(checkpoint), model_type, params)
    labels, stats = sam_masks_to_labels(result.masks, params, image.shape[:2])
    stats.update({
        "enabled": True,
        "model": result.model_name,
        "device": result.device,
        "elapsed_ms": round(float(result.elapsed_ms), 3),
    })
    return labels, stats


def sam_masks_to_labels(
    masks: list[np.ndarray],
    params: dict,
    shape: tuple[int, int],
) -> tuple[np.ndarray, dict]:
    total_pixels = max(1, int(shape[0] * shape[1]))
    min_ratio = _clamp_float(params.get("samMinAreaRatio"), 0.0, 0.20, 0.00003)
    max_ratio = _clamp_float(params.get("samMaxAreaRatio"), 0.001, 1.0, 0.12)
    max_overlap = _clamp_float(params.get("samMaxOverlapRatio"), 0.0, 1.0, 0.55)
    min_new_ratio = _clamp_float(params.get("samMinNewAreaRatio"), 0.0, 1.0, 0.35)
    min_area = max(1, int(total_pixels * min_ratio))
    max_area = max(min_area, int(total_pixels * max_ratio))

    labels = np.zeros(shape, dtype=np.int32)
    occupied = np.zeros(shape, dtype=bool)
    accepted = 0
    rejected = {
        "small": 0,
        "large": 0,
        "overlap": 0,
        "empty": 0,
    }

    sorted_masks = sorted((m.astype(bool) for m in masks), key=lambda m: int(m.sum()))
    for mask in sorted_masks:
        if mask.shape != shape:
            rejected["empty"] += 1
            continue
        area = int(mask.sum())
        if area <= 0:
            rejected["empty"] += 1
            continue
        if area < min_area:
            rejected["small"] += 1
            continue
        if area > max_area:
            rejected["large"] += 1
            continue

        overlap = int((mask & occupied).sum())
        overlap_ratio = overlap / max(1, area)
        new_mask = mask & ~occupied
        new_area = int(new_mask.sum())
        if overlap_ratio > max_overlap or new_area < int(area * min_new_ratio):
            rejected["overlap"] += 1
            continue

        accepted += 1
        labels[new_mask] = accepted
        occupied |= new_mask

    return labels, {
        "instance_count": accepted,
        "candidate_count": len(masks),
        "pixels": int(occupied.sum()),
        "ratio": round(float(occupied.mean()), 6),
        "min_area": int(min_area),
        "max_area": int(max_area),
        "rejected": rejected,
    }


def _clamp_float(value, low: float, high: float, default: float) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        parsed = default
    return max(low, min(high, parsed))


def is_sam_available(params: dict) -> bool:
    """Check if SAM can be used with current params and environment."""
    checkpoint = resolve_sam_checkpoint(params)
    if checkpoint is None:
        return False

    model_type = params.get("samModelType", "auto")
    stem = checkpoint.stem.lower()

    if model_type == "auto":
        if "fast" in stem or "yolo" in stem:
            model_type = "fast_sam"
        elif "sam2" in stem or "hiera" in stem:
            model_type = "sam2"
        else:
            model_type = "mobile_sam"

    try:
        if model_type == "mobile_sam":
            import segment_anything  # noqa
        elif model_type == "sam2":
            import sam2  # noqa
        elif model_type == "fast_sam":
            import ultralytics  # noqa
        return True
    except ImportError:
        return False
