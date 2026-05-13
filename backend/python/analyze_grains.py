from __future__ import annotations

import argparse
import base64
import csv
import json
import logging
import math
import sys
from dataclasses import dataclass
from io import BytesIO, StringIO
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageOps
from scipy import ndimage as ndi
from skimage import measure, morphology
from skimage.feature import peak_local_max
from skimage.segmentation import relabel_sequential, watershed
from sklearn.cluster import KMeans
from sklearn.decomposition import PCA

from sam_integration import build_sam_labels, build_sam_mask, is_sam_available, resolve_sam_checkpoint


logger = logging.getLogger(__name__)


CSV_COLUMNS = [
    "id",
    "area_px",
    "length_px",
    "width_px",
    "area_mm2",
    "length_mm",
    "width_mm",
    "centroid_x",
    "centroid_y",
    "bbox_x",
    "bbox_y",
    "bbox_w",
    "bbox_h",
    "angle_deg",
    "solidity",
    "extent",
    "aspect_ratio",
    "mean_seedness",
    "seed_color_distance",
]


PALETTE = np.array(
    [
        [45, 108, 191],
        [219, 87, 86],
        [73, 160, 120],
        [235, 174, 73],
        [132, 98, 174],
        [77, 176, 196],
        [201, 112, 165],
        [122, 126, 135],
    ],
    dtype=np.uint8,
)


@dataclass(frozen=True)
class PreparedImage:
    rgb: np.ndarray
    original_width: int
    original_height: int
    scale: float


def clamp_int(value, low: int, high: int, default: int) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        parsed = default
    return max(low, min(high, parsed))


def clamp_float(value, low: float, high: float, default: float) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        parsed = default
    return max(low, min(high, parsed))


def coerce_bool(value, default: bool = False) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def read_image(path: Path, max_side: int) -> PreparedImage:
    image = Image.open(path)
    image = ImageOps.exif_transpose(image).convert("RGB")
    rgb = np.asarray(image, dtype=np.uint8)
    original_height, original_width = rgb.shape[:2]
    longest = max(original_height, original_width)
    if longest <= max_side:
        return PreparedImage(rgb.copy(), original_width, original_height, 1.0)

    scale = max_side / float(longest)
    new_size = (
        max(1, int(round(original_width * scale))),
        max(1, int(round(original_height * scale))),
    )
    resized = cv2.resize(rgb, new_size, interpolation=cv2.INTER_AREA)
    return PreparedImage(resized, original_width, original_height, scale)


def build_color_features(rgb: np.ndarray) -> tuple[np.ndarray, list[str]]:
    image = rgb.astype(np.float32) / 255.0
    r = image[..., 0]
    g = image[..., 1]
    b = image[..., 2]
    eps = np.float32(1e-6)
    total = r + g + b + eps
    intensity = total / 3.0
    max_channel = np.maximum(np.maximum(r, g), b)
    min_channel = np.minimum(np.minimum(r, g), b)
    chroma = max_channel - min_channel

    planes = [
        r,
        g,
        b,
        r / total,
        g / total,
        b / total,
        (2.0 * r) - g - b,
        (2.0 * g) - r - b,
        (2.0 * b) - r - g,
        r / (g + b + eps),
        g / (r + b + eps),
        b / (r + g + eps),
        r - intensity,
        g - intensity,
        b - intensity,
        r - g,
        g - b,
        r - b,
        chroma,
        intensity,
    ]
    names = [
        "R",
        "G",
        "B",
        "PAT_R",
        "PAT_G",
        "PAT_B",
        "DIF_R",
        "DIF_G",
        "DIF_B",
        "ROO_R",
        "ROO_G",
        "ROO_B",
        "GLD_R",
        "GLD_G",
        "GLD_B",
        "R-G",
        "G-B",
        "R-B",
        "Chroma",
        "Intensity",
    ]
    features = np.stack(planes, axis=-1).astype(np.float32)
    features = np.nan_to_num(features, nan=0.0, posinf=0.0, neginf=0.0)
    return features, names


def normalize_plane(values: np.ndarray) -> np.ndarray:
    low, high = np.percentile(values, (1.0, 99.0))
    if not np.isfinite(low) or not np.isfinite(high) or high <= low:
        low = float(values.min())
        high = float(values.max())
    if high <= low:
        return np.zeros_like(values, dtype=np.float32)
    return np.clip((values - low) / (high - low), 0.0, 1.0).astype(np.float32)


def normalize01(values: np.ndarray) -> np.ndarray:
    values = values.astype(np.float32, copy=False)
    low = float(np.min(values))
    high = float(np.max(values))
    if high <= low:
        return np.zeros_like(values, dtype=np.float32)
    return ((values - low) / (high - low)).astype(np.float32)


def fill_probable_outline_regions(mask: np.ndarray, params: dict) -> np.ndarray:
    if not coerce_bool(params.get("fillContourMasks"), True):
        return mask.astype(bool)

    binary = mask.astype(bool)
    if not binary.any():
        return binary

    pixel_count = max(1, int(binary.size))
    min_area = clamp_int(params.get("minArea"), 0, 10_000_000, max(16, int(pixel_count * 0.000035)))
    max_area = clamp_int(params.get("maxArea"), 0, 10_000_000, max(min_area + 1, int(pixel_count * 0.008)))
    min_fill_area = clamp_int(params.get("contourFillMinArea"), 1, 250_000, max(8, int(min_area * 0.35)))
    max_fill_area = clamp_int(params.get("contourFillMaxArea"), 1, 1_000_000, max(max_area, int(pixel_count * 0.018)))
    close_radius = clamp_int(params.get("contourFillClosingRadius"), 0, 6, 2)

    source = binary
    if close_radius > 0:
        source = morphology.closing(source, footprint=morphology.disk(close_radius))

    contours, _ = cv2.findContours(source.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    filled = binary.copy()
    fill_plane = np.zeros(binary.shape, dtype=np.uint8)
    for contour in contours:
        area = float(cv2.contourArea(contour))
        if area < min_fill_area or area > max_fill_area:
            continue
        fill_plane.fill(0)
        cv2.drawContours(fill_plane, [contour], -1, 1, thickness=cv2.FILLED)
        filled |= fill_plane.astype(bool)

    return filled.astype(bool)


def compute_pca_images(
    feature_stack: np.ndarray,
    n_components: int = 3,
    method: str = "correlation",
    sample_size: int = 150_000,
    chunk_size: int = 500_000,
) -> tuple[np.ndarray, list[float]]:
    height, width, channels = feature_stack.shape
    pixels = feature_stack.reshape(-1, channels).astype(np.float32, copy=False)
    pixel_count = pixels.shape[0]

    rng = np.random.default_rng(42)
    if pixel_count > sample_size:
        sample = pixels[rng.choice(pixel_count, size=sample_size, replace=False)]
    else:
        sample = pixels

    mean = sample.mean(axis=0)
    if method == "covariance":
        std = np.ones(sample.shape[1], dtype=np.float32)
    else:
        std = sample.std(axis=0)
        std[std < 1e-6] = 1.0

    components = min(n_components, channels)
    pca = PCA(n_components=components, svd_solver="randomized", random_state=42)
    pca.fit((sample - mean) / std)

    transformed = np.empty((pixel_count, components), dtype=np.float32)
    for start in range(0, pixel_count, chunk_size):
        end = min(start + chunk_size, pixel_count)
        transformed[start:end] = pca.transform((pixels[start:end] - mean) / std)

    pcs_raw = transformed.reshape(height, width, components)
    pcs = np.zeros((height, width, n_components), dtype=np.float32)
    for idx in range(components):
        pcs[..., idx] = normalize_plane(pcs_raw[..., idx])

    explained = [0.0] * n_components
    for idx, value in enumerate(pca.explained_variance_ratio_[:n_components]):
        explained[idx] = float(value)
    return pcs, explained


def blend_pca_images(rgb_pcs: np.ndarray, index_pcs: np.ndarray, weight: float) -> np.ndarray:
    weight = float(np.clip(weight, 0.0, 1.0))
    components = min(rgb_pcs.shape[-1], index_pcs.shape[-1])
    blended = np.zeros((*rgb_pcs.shape[:2], components), dtype=np.float32)
    for idx in range(components):
        blended[..., idx] = normalize_plane(((1.0 - weight) * rgb_pcs[..., idx]) + (weight * index_pcs[..., idx]))
    return blended


def run_kmeans(feature_image: np.ndarray, k: int, sample_size: int = 200_000) -> tuple[np.ndarray, list, list[int]]:
    values = np.nan_to_num(feature_image.astype(np.float32), nan=0.0, posinf=1.0, neginf=0.0)
    if values.ndim == 2:
        height, width = values.shape
        pixels = values.reshape(-1, 1)
    else:
        height, width, channels = values.shape
        pixels = values.reshape(-1, channels)
    pixel_count = pixels.shape[0]

    rng = np.random.default_rng(42)
    if pixel_count > sample_size:
        sample = pixels[rng.choice(pixel_count, size=sample_size, replace=False)]
    else:
        sample = pixels

    model = KMeans(n_clusters=k, n_init="auto", random_state=42)
    model.fit(sample)

    labels_flat = model.predict(pixels)
    centers = model.cluster_centers_
    order = np.argsort(centers[:, 0])
    remap = np.zeros(k, dtype=np.int32)
    for new_idx, old_idx in enumerate(order):
        remap[old_idx] = new_idx

    labels = remap[labels_flat].reshape(height, width)
    sorted_centers = centers[order]
    counts = np.bincount(labels.reshape(-1), minlength=k)
    if sorted_centers.shape[1] == 1:
        center_payload = [float(v) for v in sorted_centers.reshape(-1)]
    else:
        center_payload = [[float(x) for x in row] for row in sorted_centers]
    return labels.astype(np.int32), center_payload, [int(v) for v in counts]


def cluster_stats(labels: np.ndarray, rgb: np.ndarray, k: int) -> list[dict]:
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV).astype(np.float32)
    stats = []
    total_pixels = labels.size
    for idx in range(k):
        mask = labels == idx
        count = int(mask.sum())
        if count == 0:
            stats.append({
                "cluster": idx,
                "count": 0,
                "area_ratio": 0.0,
                "mean_rgb": [0, 0, 0],
                "mean_hue_deg": 0.0,
                "mean_saturation": 0.0,
                "mean_value": 0.0,
            })
            continue

        mean_rgb = rgb[mask].mean(axis=0)
        mean_hsv = hsv[mask].mean(axis=0)
        stats.append({
            "cluster": idx,
            "count": count,
            "area_ratio": round(count / max(1, total_pixels), 6),
            "mean_rgb": [round(float(v), 3) for v in mean_rgb],
            "mean_hue_deg": round(float(mean_hsv[0] * 2.0), 3),
            "mean_saturation": round(float(mean_hsv[1] / 255.0), 6),
            "mean_value": round(float(mean_hsv[2] / 255.0), 6),
        })
    return stats


def suggest_foreground_clusters(labels: np.ndarray, k: int, stats: list[dict] | None = None) -> list[int]:
    if k <= 1:
        return [0]
    counts = np.bincount(labels.reshape(-1), minlength=k)
    height, width = labels.shape
    border = np.concatenate([labels[0, :], labels[-1, :], labels[:, 0], labels[:, -1]])
    border_counts = np.bincount(border, minlength=k)
    total_pixels = labels.size
    border_pixels = max(1, border.size)

    seed_color_selected = []
    max_seed_cluster_value = 0.97
    if stats:
        for item in stats:
            idx = int(item["cluster"])
            hue = float(item["mean_hue_deg"])
            saturation = float(item["mean_saturation"])
            value = float(item["mean_value"])
            area_ratio = float(item["area_ratio"])
            border_ratio = border_counts[idx] / border_pixels

            earthy_hue = 12 <= hue <= 95
            useful_saturation = saturation >= 0.11
            not_too_bright = value <= max_seed_cluster_value
            not_global_background = not (area_ratio > 0.35 and border_ratio > 0.18)
            if earthy_hue and useful_saturation and not_too_bright and not_global_background:
                seed_color_selected.append(idx)

    if seed_color_selected:
        return seed_color_selected

    selected = []
    for idx in range(k):
        area_ratio = counts[idx] / max(1, total_pixels)
        border_ratio = border_counts[idx] / border_pixels
        if area_ratio > 0.42 and border_ratio > 0.22:
            continue
        if area_ratio < 0.0005:
            continue
        selected.append(idx)

    if not selected:
        background = int(np.argmax(counts))
        selected = [idx for idx in range(k) if idx != background]
    return selected or [background]


def parse_selected_clusters(value, labels: np.ndarray, k: int) -> list[int]:
    if value is None or value == "":
        return suggest_foreground_clusters(labels, k)
    if isinstance(value, list):
        raw = value
    else:
        raw = str(value).replace("[", "").replace("]", "").split(",")
    parsed = []
    for item in raw:
        try:
            cluster = int(item)
        except (TypeError, ValueError):
            continue
        if 0 <= cluster < k and cluster not in parsed:
            parsed.append(cluster)
    return parsed or suggest_foreground_clusters(labels, k)


def build_binary_mask(labels: np.ndarray, selected_clusters: list[int], params: dict) -> np.ndarray:
    opening_radius = clamp_int(params.get("openingRadius"), 0, 8, 1)
    closing_radius = clamp_int(params.get("closingRadius"), 0, 10, 2)
    noise_size = clamp_int(params.get("noiseSize"), 1, 50_000, 25)
    default_hole_size = max(64, int(labels.size * 0.0025))
    hole_size = clamp_int(params.get("holeSize"), 1, 50_000, default_hole_size)

    mask = np.isin(labels, np.asarray(selected_clusters, dtype=np.int32))
    if opening_radius > 0:
        mask = morphology.opening(mask, footprint=morphology.disk(opening_radius))
    if closing_radius > 0:
        mask = morphology.closing(mask, footprint=morphology.disk(closing_radius))
    if noise_size > 1:
        mask = morphology.remove_small_objects(mask, min_size=noise_size)
    if hole_size > 1:
        mask = morphology.remove_small_holes(mask, max_size=hole_size)
    mask = fill_probable_outline_regions(mask, params)
    return mask.astype(bool)


def build_seed_color_mask(rgb: np.ndarray, params: dict) -> tuple[np.ndarray, np.ndarray]:
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV).astype(np.float32)
    lab = cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB).astype(np.float32)

    hue = hsv[..., 0] * 2.0
    saturation = hsv[..., 1] / 255.0
    value = hsv[..., 2] / 255.0
    lab_a = (lab[..., 1] - 128.0) / 127.0
    lab_b = (lab[..., 2] - 128.0) / 127.0

    hue_center = clamp_float(params.get("seedHueCenter"), 10.0, 95.0, 42.0)
    hue_width = clamp_float(params.get("seedHueWidth"), 15.0, 95.0, 58.0)
    min_saturation = clamp_float(params.get("minSeedSaturation"), 0.0, 0.65, 0.075)
    max_seed_value = clamp_float(params.get("seedMaxValue"), 0.45, 1.0, 0.90)
    bright_softness = clamp_float(params.get("seedBrightSoftness"), 0.02, 0.45, 0.16)
    hue_distance = np.minimum(np.abs(hue - hue_center), 360.0 - np.abs(hue - hue_center))
    hue_score = np.clip(1.0 - (hue_distance / hue_width), 0.0, 1.0)

    yellow_score = np.clip((lab_b - 0.02) / 0.38, 0.0, 1.0)
    red_penalty = np.clip((lab_a - 0.16) / 0.42, 0.0, 1.0)
    sat_score = np.clip((saturation - min_saturation) / 0.28, 0.0, 1.0)
    value_score = np.clip((value - 0.18) / 0.42, 0.0, 1.0)
    chroma_gate = np.clip((saturation - min_saturation) / 0.20, 0.0, 1.0)
    bright_gate = 1.0 - np.clip((value - max_seed_value) / bright_softness, 0.0, 1.0)

    border_width = clamp_int(params.get("backgroundBorderWidth"), 1, 80, 10)
    border_width = min(border_width, max(1, rgb.shape[0] // 4), max(1, rgb.shape[1] // 4))
    border_lab = np.concatenate(
        [
            lab[:border_width, :, :].reshape(-1, 3),
            lab[-border_width:, :, :].reshape(-1, 3),
            lab[:, :border_width, :].reshape(-1, 3),
            lab[:, -border_width:, :].reshape(-1, 3),
        ],
        axis=0,
    )
    background_lab = np.median(border_lab, axis=0)
    background_distance = np.linalg.norm(lab - background_lab, axis=2)
    background_distance_min = clamp_float(params.get("backgroundDistanceMin"), 0.0, 80.0, 6.0)
    background_distance_softness = clamp_float(params.get("backgroundDistanceSoftness"), 1.0, 120.0, 24.0)
    background_gate_strength = clamp_float(params.get("backgroundGateStrength"), 0.0, 1.0, 0.65)
    background_gate = np.clip(
        (background_distance - background_distance_min) / background_distance_softness,
        0.0,
        1.0,
    )

    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY).astype(np.float32) / 255.0
    grad_x = cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3)
    grad_y = cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3)
    texture_score = normalize01(np.sqrt((grad_x * grad_x) + (grad_y * grad_y)))

    seedness = (
        0.38 * hue_score
        + 0.32 * yellow_score
        + 0.18 * sat_score
        + 0.12 * texture_score
        - 0.22 * red_penalty
    ) * value_score
    seedness *= 0.48 + (0.52 * chroma_gate)
    seedness *= 0.50 + (0.50 * bright_gate)
    seedness *= (1.0 - background_gate_strength) + (background_gate_strength * background_gate)
    seedness = cv2.GaussianBlur(np.clip(seedness, 0.0, 1.0).astype(np.float32), (0, 0), 0.9)

    threshold = clamp_float(params.get("seednessThreshold"), 0.05, 0.95, 0.30)
    mask = seedness >= threshold

    opening_radius = clamp_int(params.get("openingRadius"), 0, 8, 1)
    closing_radius = clamp_int(params.get("closingRadius"), 0, 10, 1)
    noise_size = clamp_int(params.get("noiseSize"), 1, 50_000, 25)
    default_hole_size = max(64, int(mask.size * 0.0025))
    hole_size = clamp_int(params.get("holeSize"), 1, 50_000, default_hole_size)

    if opening_radius > 0:
        mask = morphology.opening(mask, footprint=morphology.disk(opening_radius))
    if closing_radius > 0:
        mask = morphology.closing(mask, footprint=morphology.disk(closing_radius))
    if noise_size > 1:
        mask = morphology.remove_small_objects(mask, min_size=noise_size)
    if hole_size > 1:
        mask = morphology.remove_small_holes(mask, max_size=hole_size)
    mask = fill_probable_outline_regions(mask, params)

    return mask.astype(bool), seedness.astype(np.float32)


def fill_label_holes(labels: np.ndarray, params: dict) -> tuple[np.ndarray, dict]:
    stats = {
        "enabled": coerce_bool(params.get("fillSegmentHoles"), True),
        "filled_pixels": 0,
        "segment_hole_size": 0,
    }
    if not stats["enabled"] or labels.max() == 0:
        return labels.astype(np.int32), stats

    default_hole_size = max(
        clamp_int(params.get("holeSize"), 1, 50_000, max(64, int(labels.size * 0.0025))),
        int(labels.size * 0.012),
    )
    hole_size = clamp_int(params.get("segmentHoleSize"), 1, 250_000, min(250_000, default_hole_size))
    closing_radius = clamp_int(params.get("segmentClosingRadius"), 0, 4, 1)
    output = labels.astype(np.int32).copy()
    occupied = output > 0
    filled_pixels = 0

    for source_id in [int(v) for v in np.unique(labels) if v > 0]:
        component = labels == source_id
        if not component.any():
            continue

        rows, cols = np.where(component)
        pad = max(2, closing_radius + 2)
        row0 = max(0, int(rows.min()) - pad)
        row1 = min(labels.shape[0], int(rows.max()) + pad + 1)
        col0 = max(0, int(cols.min()) - pad)
        col1 = min(labels.shape[1], int(cols.max()) + pad + 1)

        local_component = component[row0:row1, col0:col1]
        local_occupied = occupied[row0:row1, col0:col1]
        refined = local_component
        if closing_radius > 0:
            refined = morphology.closing(refined, footprint=morphology.disk(closing_radius))
        refined = morphology.remove_small_holes(refined.astype(bool), max_size=hole_size)
        refined &= ~local_occupied | local_component

        target = output[row0:row1, col0:col1]
        added = refined & (target == 0)
        if added.any():
            target[added] = source_id
            occupied[row0:row1, col0:col1] |= refined
            filled_pixels += int(added.sum())

    stats["filled_pixels"] = int(filled_pixels)
    stats["segment_hole_size"] = int(hole_size)
    output, _, _ = relabel_sequential(output.astype(np.int32))
    return output.astype(np.int32), stats


def combine_masks(seed_mask: np.ndarray, kmeans_mask: np.ndarray, params: dict) -> np.ndarray:
    mask_source = str(params.get("maskSource") or "auto")
    if mask_source == "kmeans":
        return kmeans_mask.astype(bool)
    if mask_source in {"hybrid", "auto"}:
        seed_pixels = int(seed_mask.sum())
        total_pixels = max(1, int(seed_mask.size))
        seed_ratio = seed_pixels / total_pixels
        max_seed_mask_ratio = clamp_float(params.get("maxSeedMaskRatio"), 0.05, 0.95, 0.58)
        expanded = morphology.dilation(kmeans_mask.astype(bool), footprint=morphology.disk(2))
        combined = seed_mask & expanded
        combined_pixels = int(combined.sum())
        if combined_pixels > max(100, seed_pixels * 0.08):
            return combined.astype(bool)
        if mask_source == "auto" and seed_ratio > max_seed_mask_ratio:
            kmeans_pixels = int(kmeans_mask.sum())
            if combined_pixels > max(20, seed_pixels * 0.002):
                return combined.astype(bool)
            if 0 < kmeans_pixels < int(total_pixels * max_seed_mask_ratio):
                return kmeans_mask.astype(bool)
    return seed_mask.astype(bool)


def touches_border(bbox: tuple[int, int, int, int], shape: tuple[int, int], margin: int) -> bool:
    min_row, min_col, max_row, max_col = bbox
    height, width = shape
    return (
        min_row <= margin
        or min_col <= margin
        or max_row >= height - margin
        or max_col >= width - margin
    )


def component_local_contrast(
    labels: np.ndarray,
    binary: np.ndarray,
    rgb_lab: np.ndarray,
    seedness: np.ndarray,
    prop,
    ring_radius: int,
) -> tuple[float | None, float | None]:
    if ring_radius <= 0:
        return None, None

    min_row, min_col, max_row, max_col = prop.bbox
    pad = ring_radius + 2
    row0 = max(0, min_row - pad)
    col0 = max(0, min_col - pad)
    row1 = min(labels.shape[0], max_row + pad)
    col1 = min(labels.shape[1], max_col + pad)

    local_labels = labels[row0:row1, col0:col1]
    local_binary = binary[row0:row1, col0:col1]
    component = local_labels == prop.label
    if not component.any():
        return None, None

    dilated = morphology.dilation(component, footprint=morphology.disk(ring_radius))
    ring = dilated & ~local_binary
    if int(ring.sum()) < 12:
        return None, None

    lab_local = rgb_lab[row0:row1, col0:col1]
    seed_local = seedness[row0:row1, col0:col1]
    lab_delta = float(np.linalg.norm(lab_local[component].mean(axis=0) - lab_local[ring].mean(axis=0)))
    seed_delta = float(seed_local[component].mean() - seed_local[ring].mean())
    return lab_delta, seed_delta


def filter_foreground_mask(
    mask: np.ndarray,
    seedness: np.ndarray,
    rgb: np.ndarray,
    params: dict,
) -> tuple[np.ndarray, dict]:
    binary = mask.astype(bool)
    labels = measure.label(binary, connectivity=2).astype(np.int32)
    component_count = int(labels.max())
    stats = {
        "component_count_before": component_count,
        "component_count_after": 0,
        "pixels_before": int(binary.sum()),
        "pixels_after": 0,
        "rejected_reasons": {},
    }

    if component_count == 0:
        return binary, stats

    height, width = binary.shape
    pixel_count = max(1, int(binary.size))
    min_area = clamp_int(params.get("minArea"), 0, 10_000_000, 0)
    max_area = clamp_int(params.get("maxArea"), 0, 10_000_000, 0)
    seed_threshold = clamp_float(params.get("seednessThreshold"), 0.05, 0.95, 0.30)

    default_min_component_area = max(18, int(pixel_count * 0.00002), int(min_area * 0.75))
    min_component_area = clamp_int(params.get("maskMinArea"), 1, 10_000_000, default_min_component_area)
    max_foreground_area_ratio = clamp_float(params.get("maxForegroundAreaRatio"), 0.04, 0.85, 0.34)
    border_margin = clamp_int(params.get("borderMargin"), 0, 60, 2)
    reject_border = coerce_bool(params.get("rejectBorderComponents"), False)
    reject_suspicious_border = coerce_bool(params.get("rejectSuspiciousBorderComponents"), True)

    max_aspect_ratio = clamp_float(params.get("maxAspectRatio"), 1.5, 50.0, 9.5)
    min_solidity = clamp_float(params.get("minSolidity"), 0.05, 0.98, 0.48)
    min_extent = clamp_float(params.get("minExtent"), 0.02, 0.95, 0.16)
    max_cluster_extent = clamp_float(params.get("maxClusterExtent"), 0.2, 1.0, 0.74)
    max_cluster_solidity = clamp_float(params.get("maxClusterSolidity"), 0.2, 1.0, 0.94)
    cluster_block_area_multiplier = clamp_float(params.get("clusterBlockAreaMultiplier"), 1.0, 20.0, 2.0)
    min_seed_mean = clamp_float(
        params.get("minComponentSeednessMean"),
        0.0,
        1.0,
        min(0.95, seed_threshold + 0.018),
    )
    min_seed_p80 = clamp_float(
        params.get("minComponentSeednessP80"),
        0.0,
        1.0,
        min(0.98, seed_threshold + 0.055),
    )
    ring_radius = clamp_int(params.get("contrastRingRadius"), 0, 20, 4)
    min_lab_contrast = clamp_float(params.get("minLabContrast"), 0.0, 80.0, 2.8)
    min_seedness_contrast = clamp_float(params.get("minSeednessContrast"), -1.0, 1.0, 0.012)

    lab = cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB).astype(np.float32)
    filtered = np.zeros(binary.shape, dtype=bool)
    reasons = stats["rejected_reasons"]

    def reject(reason: str) -> None:
        reasons[reason] = int(reasons.get(reason, 0)) + 1

    for prop in measure.regionprops(labels):
        area = int(prop.area)
        min_row, min_col, max_row, max_col = prop.bbox
        bbox_h = max(1, max_row - min_row)
        bbox_w = max(1, max_col - min_col)
        aspect_ratio = max(bbox_h, bbox_w) / max(1, min(bbox_h, bbox_w))
        area_ratio = area / pixel_count
        border_hit = touches_border(prop.bbox, binary.shape, border_margin)
        possible_cluster = bool(max_area and area > max_area * 1.15)
        solidity_floor = min_solidity * (0.58 if possible_cluster else 1.0)
        extent_floor = min_extent * (0.50 if possible_cluster else 1.0)
        seed_values = seedness[labels == prop.label]
        seed_mean = float(seed_values.mean()) if seed_values.size else 0.0
        seed_p80 = float(np.percentile(seed_values, 80)) if seed_values.size else 0.0

        if area < min_component_area:
            reject("small_area")
            continue
        if border_hit and area_ratio > max_foreground_area_ratio:
            reject("huge_border_component")
            continue
        if reject_border and border_hit:
            reject("border_component")
            continue
        if (
            reject_suspicious_border
            and border_hit
            and (area > max(min_component_area * 8, int(max_area * 1.2) if max_area else 0) or aspect_ratio > 5.5)
        ):
            reject("suspicious_border_component")
            continue
        if (
            possible_cluster
            and max_area
            and area > max_area * cluster_block_area_multiplier
            and float(prop.extent) > max_cluster_extent
            and float(prop.solidity) > max_cluster_solidity
        ):
            reject("large_solid_component")
            continue
        if aspect_ratio > max_aspect_ratio and not possible_cluster:
            reject("aspect_ratio")
            continue
        if float(prop.solidity) < solidity_floor:
            reject("low_solidity")
            continue
        if float(prop.extent) < extent_floor and not possible_cluster:
            reject("low_extent")
            continue
        if not possible_cluster and (seed_mean < min_seed_mean or seed_p80 < min_seed_p80):
            reject("low_seedness")
            continue

        lab_delta, seed_delta = component_local_contrast(
            labels,
            binary,
            lab,
            seedness,
            prop,
            ring_radius,
        )
        if (
            not possible_cluster
            and lab_delta is not None
            and seed_delta is not None
            and lab_delta < min_lab_contrast
            and seed_delta < min_seedness_contrast
        ):
            reject("low_local_contrast")
            continue

        filtered[labels == prop.label] = True

    stats["component_count_after"] = int(measure.label(filtered, connectivity=2).max()) if filtered.any() else 0
    stats["pixels_after"] = int(filtered.sum())
    return filtered.astype(bool), stats


def estimate_dynamic_thresholds(mask: np.ndarray, params: dict) -> dict:
    binary = mask.astype(bool)
    labels = measure.label(binary, connectivity=2).astype(np.int32)
    stats = {
        "enabled": coerce_bool(params.get("dynamicThresholds"), False),
        "component_count": int(labels.max()),
        "candidate_count": 0,
        "mean_area": 0.0,
        "median_area": 0.0,
        "suggested_min_area": None,
        "suggested_max_area": None,
        "suggested_min_length": None,
        "suggested_max_length": None,
        "suggested_marker_min_distance": None,
    }
    if labels.max() == 0:
        return stats

    min_area = clamp_int(params.get("minArea"), 0, 10_000_000, 0)
    max_area = clamp_int(params.get("maxArea"), 0, 10_000_000, 0)
    border_margin = clamp_int(params.get("borderMargin"), 0, 60, 2)

    candidates = []
    fallback = []
    for prop in measure.regionprops(labels):
        area = float(prop.area)
        min_row, min_col, max_row, max_col = prop.bbox
        bbox_h = max(1, max_row - min_row)
        bbox_w = max(1, max_col - min_col)
        diagonal = float(math.hypot(bbox_w, bbox_h))
        aspect_ratio = max(bbox_h, bbox_w) / max(1, min(bbox_h, bbox_w))
        border_hit = touches_border(prop.bbox, binary.shape, border_margin)
        item = {
            "area": area,
            "diagonal": diagonal,
            "solidity": float(prop.solidity),
            "extent": float(prop.extent),
            "aspect_ratio": float(aspect_ratio),
            "border_hit": border_hit,
        }

        if area >= max(8, min_area * 0.45):
            fallback.append(item)

        if area < max(8, min_area * 0.5):
            continue
        if max_area and area > max_area * 1.6:
            continue
        if border_hit and area > max(120, max_area * 0.8 if max_area else 120):
            continue
        if item["solidity"] < 0.50 or item["extent"] < 0.16 or aspect_ratio > 8.5:
            continue
        candidates.append(item)

    if len(candidates) < 3 and fallback:
        fallback_areas = np.asarray([item["area"] for item in fallback], dtype=np.float32)
        low, high = np.percentile(fallback_areas, (10, 85))
        candidates = [
            item for item in fallback
            if item["area"] >= low
            and item["area"] <= max(high, low + 1)
            and not (item["border_hit"] and item["area"] > high * 1.25)
        ]

    if not candidates:
        return stats

    areas = np.asarray([item["area"] for item in candidates], dtype=np.float32)
    diagonals = np.asarray([item["diagonal"] for item in candidates], dtype=np.float32)
    median_area = float(np.median(areas))
    mean_area = float(np.mean(areas))
    p10_area, p90_area = np.percentile(areas, (10, 90))
    p10_diag, p90_diag = np.percentile(diagonals, (10, 90))
    median_diag = float(np.median(diagonals))
    shrink_factor = clamp_float(params.get("markerShrinkFactor"), 0.15, 1.0, 0.5)

    suggested_min_area = int(max(8, min_area, round(p10_area * 0.25), round(median_area * 0.12)))
    suggested_max_area = int(max(suggested_min_area + 1, round(p90_area * 1.85), round(median_area * 2.8)))
    suggested_min_length = int(max(1, round(p10_diag * 0.28)))
    suggested_max_length = int(max(suggested_min_length + 1, round(p90_diag * 1.75), round(median_diag * 2.45)))
    area_marker = math.sqrt(max(1.0, median_area)) * shrink_factor
    diagonal_marker = median_diag * (0.14 + (0.10 * shrink_factor))
    suggested_marker = int(np.clip(round(min(area_marker, diagonal_marker)), 3, 40))

    stats.update({
        "candidate_count": len(candidates),
        "mean_area": round(mean_area, 3),
        "median_area": round(median_area, 3),
        "suggested_min_area": suggested_min_area,
        "suggested_max_area": suggested_max_area,
        "suggested_min_length": suggested_min_length,
        "suggested_max_length": suggested_max_length,
        "suggested_marker_min_distance": suggested_marker,
    })
    return stats


def apply_dynamic_thresholds(params: dict, threshold_stats: dict) -> dict:
    effective = dict(params)
    if not coerce_bool(params.get("dynamicThresholds"), False):
        return effective

    if coerce_bool(params.get("dynamicAreaThresholds"), True):
        suggested_min = threshold_stats.get("suggested_min_area")
        suggested_max = threshold_stats.get("suggested_max_area")
        if suggested_min:
            current_min = clamp_int(effective.get("minArea"), 0, 10_000_000, int(suggested_min))
            effective["minArea"] = max(current_min, int(suggested_min))
        if suggested_max:
            current_max = clamp_int(effective.get("maxArea"), 0, 10_000_000, int(suggested_max))
            min_area = clamp_int(effective.get("minArea"), 0, 10_000_000, 0)
            if current_max > 0:
                effective["maxArea"] = max(min_area + 1, min(current_max, int(suggested_max)))
            else:
                effective["maxArea"] = int(suggested_max)

    if coerce_bool(params.get("dynamicDiagonalThresholds"), False):
        suggested_min = threshold_stats.get("suggested_min_length")
        suggested_max = threshold_stats.get("suggested_max_length")
        if suggested_min:
            current_min = clamp_int(effective.get("minLength"), 0, 100_000, int(suggested_min))
            effective["minLength"] = max(current_min, int(suggested_min))
        if suggested_max:
            current_max = clamp_int(effective.get("maxLength"), 0, 100_000, int(suggested_max))
            min_length = clamp_int(effective.get("minLength"), 0, 100_000, 0)
            if current_max > 0:
                effective["maxLength"] = max(min_length + 1, min(current_max, int(suggested_max)))
            else:
                effective["maxLength"] = int(suggested_max)

    return effective


def watershed_split(
    mask: np.ndarray,
    split_sensitivity: int,
    marker_min_distance: int | None = None,
    peak_threshold_rel: float | None = None,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, int, float]:
    binary = mask.astype(bool)
    if not binary.any():
        empty_i = np.zeros(binary.shape, dtype=np.int32)
        empty_f = np.zeros(binary.shape, dtype=np.float32)
        return empty_i, empty_f, empty_i, 0, 0.0

    marker_distance = marker_min_distance
    if marker_distance is None:
        marker_distance = int(np.clip(34 - (split_sensitivity * 3), 3, 40))
    else:
        sensitivity_distance = int(np.clip(34 - (split_sensitivity * 3), 3, 40))
        marker_distance = min(int(np.clip(marker_distance, 3, 60)), sensitivity_distance)

    threshold_rel = peak_threshold_rel
    if threshold_rel is None:
        threshold_rel = float(np.clip(0.36 - (split_sensitivity * 0.032), 0.045, 0.34))

    distance = cv2.distanceTransform(binary.astype(np.uint8), cv2.DIST_L2, 5)
    coords = peak_local_max(
        distance,
        labels=binary,
        min_distance=max(1, marker_distance),
        threshold_rel=threshold_rel,
        exclude_border=False,
    )

    markers = np.zeros(binary.shape, dtype=np.int32)
    if len(coords) == 0:
        markers, _ = ndi.label(binary)
    else:
        for idx, (row, col) in enumerate(coords, start=1):
            markers[row, col] = idx

    labels = watershed(-distance, markers=markers, mask=binary)
    labels, _, _ = relabel_sequential(labels.astype(np.int32))
    return labels.astype(np.int32), distance.astype(np.float32), markers, marker_distance, threshold_rel


def dense_seed_watershed(
    mask: np.ndarray,
    rgb: np.ndarray,
    seedness: np.ndarray,
    split_sensitivity: int,
    marker_min_distance: int | None = None,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, int, float]:
    binary = mask.astype(bool)
    if not binary.any():
        empty_i = np.zeros(binary.shape, dtype=np.int32)
        empty_f = np.zeros(binary.shape, dtype=np.float32)
        return empty_i, empty_f, empty_i, 0, 0.0

    sensitivity_distance = int(np.clip(19 - (split_sensitivity * 1.35), 5, 18))
    if marker_min_distance is None:
        marker_distance = sensitivity_distance
    else:
        marker_distance = min(int(np.clip(marker_min_distance, 3, 60)), sensitivity_distance)
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY).astype(np.float32) / 255.0
    gray_smooth = cv2.GaussianBlur(gray, (0, 0), 1.0)
    seed_smooth = cv2.GaussianBlur(seedness.astype(np.float32), (0, 0), 1.2)

    center_response = normalize01((0.68 * seed_smooth) + (0.32 * gray_smooth))
    inside = center_response[binary]
    if inside.size:
        percentile = float(np.clip(66 - (split_sensitivity * 3.2), 28, 62))
        threshold_abs = max(0.16, float(np.percentile(inside, percentile)))
    else:
        threshold_abs = 0.16

    coords = peak_local_max(
        center_response,
        labels=binary,
        min_distance=marker_distance,
        threshold_abs=threshold_abs,
        exclude_border=False,
    )

    if len(coords) < 2 and inside.size:
        coords = peak_local_max(
            center_response,
            labels=binary,
            min_distance=max(4, marker_distance - 2),
            threshold_abs=max(0.08, float(np.percentile(inside, 20))),
            exclude_border=False,
        )

    markers = np.zeros(binary.shape, dtype=np.int32)
    if len(coords) == 0:
        markers, _ = ndi.label(binary)
    else:
        for idx, (row, col) in enumerate(coords, start=1):
            markers[row, col] = idx

    grad_x = cv2.Sobel(gray_smooth, cv2.CV_32F, 1, 0, ksize=3)
    grad_y = cv2.Sobel(gray_smooth, cv2.CV_32F, 0, 1, ksize=3)
    gradient = normalize01(np.sqrt((grad_x * grad_x) + (grad_y * grad_y)))
    elevation = normalize01((0.70 * gradient) + (0.30 * (1.0 - seed_smooth)))

    labels = watershed(elevation, markers=markers, mask=binary)
    labels, _, _ = relabel_sequential(labels.astype(np.int32))
    return labels.astype(np.int32), elevation.astype(np.float32), markers, marker_distance, threshold_abs


def dense_pile_watershed(
    mask: np.ndarray,
    rgb: np.ndarray,
    seedness: np.ndarray,
    split_sensitivity: int,
    marker_min_distance: int | None = None,
    params: dict | None = None,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, int, float]:
    binary = mask.astype(bool)
    if not binary.any():
        empty_i = np.zeros(binary.shape, dtype=np.int32)
        empty_f = np.zeros(binary.shape, dtype=np.float32)
        return empty_i, empty_f, empty_i, 0, 0.0

    params = params or {}
    sensitivity_distance = int(np.clip(22 - split_sensitivity, 8, 18))
    requested_marker = clamp_int(
        params.get("denseMarkerMinDistance"),
        4,
        60,
        sensitivity_distance,
    )
    if marker_min_distance is not None:
        requested_marker = min(requested_marker, int(np.clip(marker_min_distance, 4, 60)))
    marker_distance = int(np.clip(min(requested_marker, sensitivity_distance), 4, 60))

    rgb_float = rgb.astype(np.float32) / 255.0
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY).astype(np.float32) / 255.0
    smooth_sigma = clamp_float(params.get("denseSmoothSigma"), 0.4, 4.0, 1.15)
    gray_smooth = cv2.GaussianBlur(gray, (0, 0), smooth_sigma)
    seed_smooth = cv2.GaussianBlur(seedness.astype(np.float32), (0, 0), max(0.8, smooth_sigma * 0.85))
    lab = cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB).astype(np.float32)
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV).astype(np.float32)
    lab_yellow = normalize01(lab[..., 2])
    saturation = hsv[..., 1]

    grad_x = cv2.Sobel(gray_smooth, cv2.CV_32F, 1, 0, ksize=3)
    grad_y = cv2.Sobel(gray_smooth, cv2.CV_32F, 0, 1, ksize=3)
    gradient = normalize01(np.sqrt((grad_x * grad_x) + (grad_y * grad_y)))
    local_mean = cv2.GaussianBlur(gray_smooth, (0, 0), 7.0)
    local_bright = normalize01(gray_smooth - local_mean)

    center_response = normalize01(
        (0.34 * gray_smooth)
        + (0.24 * seed_smooth)
        + (0.18 * lab_yellow)
        + (0.14 * local_bright)
        + (0.10 * normalize01(saturation))
        - (0.18 * gradient)
    )

    inside = center_response[binary]
    if inside.size:
        default_percentile = 72.0 - split_sensitivity * 1.25
        percentile = clamp_float(params.get("densePeakPercentile"), 35.0, 90.0, default_percentile)
        threshold_abs = max(0.08, float(np.percentile(inside, percentile)))
    else:
        threshold_abs = 0.12

    coords = peak_local_max(
        center_response,
        labels=binary,
        min_distance=max(1, marker_distance),
        threshold_abs=threshold_abs,
        exclude_border=False,
    )

    if len(coords) < 8 and inside.size:
        coords = peak_local_max(
            center_response,
            labels=binary,
            min_distance=max(4, int(marker_distance * 0.75)),
            threshold_abs=max(0.05, float(np.percentile(inside, 42))),
            exclude_border=False,
        )

    markers = np.zeros(binary.shape, dtype=np.int32)
    if len(coords) == 0:
        markers, _ = ndi.label(binary)
    else:
        for idx, (row, col) in enumerate(coords, start=1):
            markers[row, col] = idx

    dark_valley = normalize01(1.0 - gray_smooth)
    color_edge = normalize01(np.std(rgb_float, axis=2))
    gradient_weight = clamp_float(params.get("denseGradientWeight"), 0.0, 1.0, 0.48)
    valley_weight = clamp_float(params.get("denseValleyWeight"), 0.0, 1.0, 0.22)
    center_weight = clamp_float(params.get("denseCenterWeight"), 0.0, 1.0, 0.18)
    color_weight = clamp_float(params.get("denseColorEdgeWeight"), 0.0, 1.0, 0.12)
    elevation = normalize01(
        (gradient_weight * gradient)
        + (valley_weight * dark_valley)
        + (center_weight * (1.0 - center_response))
        + (color_weight * color_edge)
    )
    elevation_sigma = clamp_float(params.get("denseElevationSmoothSigma"), 0.0, 4.0, 0.0)
    if elevation_sigma > 0:
        elevation = cv2.GaussianBlur(elevation, (0, 0), elevation_sigma)

    labels = watershed(elevation, markers=markers, mask=binary)
    labels, _, _ = relabel_sequential(labels.astype(np.int32))
    return labels.astype(np.int32), elevation.astype(np.float32), markers, marker_distance, threshold_abs


def should_use_dense_pile_mode(raw_mask: np.ndarray, mask: np.ndarray, mask_stats: dict, params: dict) -> bool:
    mode = str(params.get("segmentationMode") or "auto").strip().lower()
    if mode in {"densepile", "dense_pile", "pile", "fullframe", "full_frame"}:
        return True
    if mode in {"foreground", "background", "normal"}:
        return False

    total_pixels = max(1, int(raw_mask.size))
    raw_ratio = int(raw_mask.sum()) / total_pixels
    mask_ratio = int(mask.sum()) / total_pixels
    components_after = int(mask_stats.get("component_count_after") or 0)
    rejected_reasons = mask_stats.get("rejected_reasons") or {}
    rejected_huge_border = int(rejected_reasons.get("huge_border_component") or 0) > 0

    return (
        (raw_ratio >= 0.45 and components_after <= 2)
        or (raw_ratio >= 0.24 and mask_ratio <= 0.08)
        or mask_ratio >= 0.62
        or (rejected_huge_border and raw_ratio >= 0.28 and components_after == 0)
    )


def profile_image_context(
    rgb: np.ndarray,
    raw_mask: np.ndarray,
    filtered_mask: np.ndarray,
    seedness: np.ndarray,
    params: dict,
) -> tuple[str, dict, dict]:
    total_pixels = max(1, int(raw_mask.size))
    raw_ratio = int(raw_mask.sum()) / total_pixels
    filtered_ratio = int(filtered_mask.sum()) / total_pixels
    labels = measure.label(filtered_mask.astype(bool), connectivity=2).astype(np.int32)
    component_count = int(labels.max())

    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY).astype(np.float32) / 255.0
    gray_blur = cv2.GaussianBlur(gray, (0, 0), 1.2)
    grad_x = cv2.Sobel(gray_blur, cv2.CV_32F, 1, 0, ksize=3)
    grad_y = cv2.Sobel(gray_blur, cv2.CV_32F, 0, 1, ksize=3)
    gradient = normalize01(np.sqrt((grad_x * grad_x) + (grad_y * grad_y)))
    foreground = filtered_mask.astype(bool)
    if not foreground.any():
        foreground = raw_mask.astype(bool)
    foreground_edge_mean = float(gradient[foreground].mean()) if foreground.any() else 0.0
    background = ~raw_mask.astype(bool)
    if not background.any():
        border = max(4, int(round(min(rgb.shape[:2]) * 0.035)))
        background = np.zeros(raw_mask.shape, dtype=bool)
        background[:border, :] = True
        background[-border:, :] = True
        background[:, :border] = True
        background[:, -border:] = True
    background_edge_mean = float(gradient[background].mean()) if background.any() else 0.0
    seed_mean = float(seedness[raw_mask.astype(bool)].mean()) if raw_mask.any() else 0.0

    areas = []
    aspect_ratios = []
    for prop in measure.regionprops(labels):
        areas.append(float(prop.area))
        min_row, min_col, max_row, max_col = prop.bbox
        bbox_h = max(1, max_row - min_row)
        bbox_w = max(1, max_col - min_col)
        aspect_ratios.append(max(bbox_h, bbox_w) / max(1, min(bbox_h, bbox_w)))
    median_area = float(np.median(np.asarray(areas, dtype=np.float32))) if areas else 0.0
    median_aspect = float(np.median(np.asarray(aspect_ratios, dtype=np.float32))) if aspect_ratios else 0.0

    if raw_ratio >= 0.42 or (filtered_ratio >= 0.28 and component_count <= 12):
        image_type = "dense_pile"
        tuned = {
            "segmentationMode": "dense_pile",
            "denseAutoTargetCount": max(260, min(1200, int(total_pixels / max(1.0, median_area or 520.0) * 0.85))),
            "denseAutoMaxCount": max(600, min(2400, int(total_pixels / max(1.0, median_area or 520.0) * 1.55))),
        }
    elif component_count >= 18 and raw_ratio < 0.35:
        image_type = "single_layer"
        tuned = {
            "segmentationMode": "auto",
            "watershedMode": "dense",
            "dynamicThresholds": True,
            "autoSurfaceTune": False,
        }
    else:
        image_type = "foreground_objects"
        tuned = {
            "segmentationMode": "auto",
            "autoSurfaceTune": False,
        }

    if seed_mean < 0.22 or (foreground_edge_mean < 0.08 and raw_ratio < 0.82):
        tuned.update({
            "seednessThreshold": min(clamp_float(params.get("seednessThreshold"), 0.05, 0.95, 0.24), 0.20),
            "denseMaskPercentile": min(clamp_float(params.get("denseMaskPercentile"), 5.0, 45.0, 28.0), 24.0),
        })
        image_type = f"{image_type}_low_contrast"

    if background_edge_mean > foreground_edge_mean * 0.65 and background_edge_mean > 0.12:
        tuned.update({
            "rejectSuspiciousBorderComponents": True,
            "maxForegroundAreaRatio": min(clamp_float(params.get("maxForegroundAreaRatio"), 0.02, 1.0, 0.65), 0.55),
        })
        image_type = f"{image_type}_cluttered_background"

    stats = {
        "type": image_type,
        "raw_foreground_ratio": round(float(raw_ratio), 6),
        "filtered_foreground_ratio": round(float(filtered_ratio), 6),
        "component_count": int(component_count),
        "median_component_area": round(float(median_area), 3),
        "median_component_aspect_ratio": round(float(median_aspect), 3),
        "foreground_edge_mean": round(float(foreground_edge_mean), 6),
        "background_edge_mean": round(float(background_edge_mean), 6),
        "seedness_mean": round(float(seed_mean), 6),
        "applied_params": tuned,
    }
    return image_type, tuned, stats


def dense_pile_params(params: dict, pixel_count: int) -> dict:
    effective = dict(params)
    current_min = clamp_int(effective.get("minArea"), 0, 10_000_000, max(20, int(pixel_count * 0.00008)))
    current_max = clamp_int(effective.get("maxArea"), 0, 10_000_000, max(400, int(pixel_count * 0.008)))
    effective["minArea"] = max(12, min(current_min, max(20, int(pixel_count * 0.00009))))
    effective["maxArea"] = max(current_max, int(pixel_count * 0.014), effective["minArea"] + 1)
    current_max_length = clamp_int(effective.get("maxLength"), 0, 100_000, int(math.sqrt(pixel_count) * 0.28))
    effective["maxLength"] = max(current_max_length, int(math.sqrt(pixel_count) * 0.42), 1)
    effective["minSegmentSolidity"] = min(
        clamp_float(effective.get("minSegmentSolidity"), 0.0, 0.99, 0.35),
        0.35,
    )
    effective["minSegmentExtent"] = min(
        clamp_float(effective.get("minSegmentExtent"), 0.0, 0.99, 0.10),
        0.10,
    )
    effective["maxSegmentAspectRatio"] = max(
        clamp_float(effective.get("maxSegmentAspectRatio"), 1.2, 50.0, 14.0),
        14.0,
    )
    effective["minSegmentSeednessMean"] = min(
        clamp_float(effective.get("minSegmentSeednessMean"), 0.0, 1.0, 0.0),
        0.08,
    )
    return effective


def build_dense_pile_mask(rgb: np.ndarray, seedness: np.ndarray, params: dict) -> tuple[np.ndarray, dict]:
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY).astype(np.float32) / 255.0
    gray_smooth = cv2.GaussianBlur(gray, (0, 0), 1.0)
    seed_smooth = cv2.GaussianBlur(seedness.astype(np.float32), (0, 0), 1.0)
    lab = cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB).astype(np.float32)
    lab_yellow = normalize01(lab[..., 2])
    saturation = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV).astype(np.float32)[..., 1] / 255.0

    grad_x = cv2.Sobel(gray_smooth, cv2.CV_32F, 1, 0, ksize=3)
    grad_y = cv2.Sobel(gray_smooth, cv2.CV_32F, 0, 1, ksize=3)
    gradient = normalize01(np.sqrt((grad_x * grad_x) + (grad_y * grad_y)))
    surface_score = normalize01(
        (0.40 * seed_smooth)
        + (0.34 * gray_smooth)
        + (0.16 * lab_yellow)
        + (0.10 * saturation)
        - (0.22 * gradient)
    )

    roi, roi_stats = build_pile_roi_mask(rgb, seedness, params)
    score_values = surface_score[roi] if roi.any() else surface_score.reshape(-1)
    percentile = clamp_float(params.get("denseMaskPercentile"), 5.0, 45.0, 28.0)
    threshold = max(0.05, float(np.percentile(score_values, percentile)))
    mask = (surface_score >= threshold) & roi

    closing_radius = clamp_int(params.get("denseMaskClosingRadius"), 0, 5, 1)
    min_area = clamp_int(params.get("denseMaskMinArea"), 1, 50_000, 12)
    if closing_radius > 0:
        mask = morphology.closing(mask, footprint=morphology.disk(closing_radius))
    if min_area > 1:
        mask = morphology.remove_small_objects(mask.astype(bool), min_size=min_area)

    stats = {
        "dense_mask_percentile": round(float(percentile), 3),
        "dense_mask_threshold": round(float(threshold), 6),
        "dense_mask_pixels": int(mask.sum()),
        "dense_mask_ratio": round(float(mask.mean()), 6),
    }
    stats.update(roi_stats)
    return mask.astype(bool), stats


def build_pile_roi_mask(rgb: np.ndarray, seedness: np.ndarray, params: dict) -> tuple[np.ndarray, dict]:
    height, width = rgb.shape[:2]
    pixel_count = max(1, height * width)
    lab = cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB).astype(np.float32)
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV).astype(np.float32)
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY).astype(np.float32) / 255.0
    border_width = clamp_int(params.get("backgroundBorderWidth"), 1, 120, max(8, int(round(min(height, width) * 0.035))))
    border_width = min(border_width, max(1, height // 4), max(1, width // 4))
    border_mask = np.zeros((height, width), dtype=bool)
    border_mask[:border_width, :] = True
    border_mask[-border_width:, :] = True
    border_mask[:, :border_width] = True
    border_mask[:, -border_width:] = True

    saturation = hsv[..., 1] / 255.0
    grad_x = cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3)
    grad_y = cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3)
    edge = normalize01(np.sqrt((grad_x * grad_x) + (grad_y * grad_y)))
    border_lab = lab[border_mask]
    border_saturation = saturation[border_mask]
    border_edge = edge[border_mask]
    quiet_border = (border_saturation <= np.percentile(border_saturation, 45)) & (border_edge <= np.percentile(border_edge, 55))
    if int(quiet_border.sum()) >= max(32, int(border_lab.shape[0] * 0.08)):
        background_lab = np.median(border_lab[quiet_border], axis=0)
    else:
        background_lab = np.median(border_lab, axis=0)

    lab_distance = np.linalg.norm(lab - background_lab, axis=2)
    border_distance = lab_distance[border_mask]
    quiet_distance = border_distance[quiet_border] if int(quiet_border.sum()) else border_distance
    distance_floor = max(
        clamp_float(params.get("denseRoiBackgroundDistance"), 2.0, 80.0, 8.0),
        float(np.percentile(quiet_distance, 98)) + 4.0 if quiet_distance.size else 8.0,
    )
    foreground = (
        (lab_distance >= distance_floor)
        | (
            (seedness >= max(0.16, clamp_float(params.get("seednessThreshold"), 0.05, 0.95, 0.24) * 0.70))
            & (lab_distance >= distance_floor * 0.45)
        )
        | ((saturation >= 0.11) & (edge >= 0.08))
    )

    foreground = morphology.closing(foreground.astype(bool), footprint=morphology.disk(5))
    foreground = morphology.remove_small_holes(foreground, max_size=max(256, int(pixel_count * 0.025)))
    foreground = morphology.remove_small_objects(foreground, min_size=max(64, int(pixel_count * 0.002)))

    labels = measure.label(foreground, connectivity=2).astype(np.int32)
    if labels.max() > 0:
        props = measure.regionprops(labels)
        largest = max(props, key=lambda item: item.area)
        keep = labels == largest.label
        if largest.area >= max(64, int(pixel_count * 0.04)):
            foreground = morphology.dilation(keep, footprint=morphology.disk(2))

    stats = {
        "dense_roi_pixels": int(foreground.sum()),
        "dense_roi_ratio": round(float(foreground.mean()), 6),
        "dense_roi_background_distance": round(float(distance_floor), 6),
    }
    return foreground.astype(bool), stats


def refine_oversized_segments(
    labels: np.ndarray,
    max_area: int | None,
    max_length: int | None,
    split_sensitivity: int,
    marker_min_distance: int,
    peak_threshold_rel: float,
) -> np.ndarray:
    if labels.max() == 0:
        return labels.astype(np.int32)

    output = np.zeros(labels.shape, dtype=np.int32)
    next_label = 1
    local_distance = max(2, int(round(marker_min_distance * 0.55)))
    local_threshold = max(0.02, peak_threshold_rel * 0.65)
    local_sensitivity = min(10, split_sensitivity + 2)

    for prop in measure.regionprops(labels):
        component = labels == prop.label
        major_axis = prop.axis_major_length if hasattr(prop, "axis_major_length") else prop.major_axis_length
        too_large = bool(max_area and prop.area > max_area)
        too_long = bool(max_length and major_axis > max_length)

        if not (too_large or too_long):
            output[component] = next_label
            next_label += 1
            continue

        min_row, min_col, max_row, max_col = prop.bbox
        submask = component[min_row:max_row, min_col:max_col]
        split, _, _, _, _ = watershed_split(
            submask,
            split_sensitivity=local_sensitivity,
            marker_min_distance=local_distance,
            peak_threshold_rel=local_threshold,
        )

        if split.max() <= 1:
            output[component] = next_label
            next_label += 1
            continue

        for sub_label in range(1, int(split.max()) + 1):
            sub_component = split == sub_label
            if not sub_component.any():
                continue
            target = output[min_row:max_row, min_col:max_col]
            target[sub_component] = next_label
            next_label += 1

    output, _, _ = relabel_sequential(output)
    return output.astype(np.int32)


def edge_snap_labels(
    labels: np.ndarray,
    rgb: np.ndarray,
    seedness: np.ndarray,
    params: dict,
) -> tuple[np.ndarray, dict]:
    stats = {
        "enabled": coerce_bool(params.get("edgeSnap"), False),
        "input_segments": int(labels.max()) if labels.size else 0,
        "output_segments": int(labels.max()) if labels.size else 0,
        "candidate_pixels": int((labels > 0).sum()) if labels.size else 0,
    }
    if not stats["enabled"] or labels.max() == 0:
        return labels.astype(np.int32), stats

    foreground = labels > 0
    snap_radius = clamp_int(params.get("edgeSnapRadius"), 0, 12, 4)
    marker_erode = clamp_int(params.get("edgeSnapMarkerErode"), 0, 10, 2)
    seed_threshold = clamp_float(params.get("seednessThreshold"), 0.05, 0.95, 0.30)
    seedness_scale = clamp_float(params.get("edgeSnapSeednessScale"), 0.15, 1.0, 0.55)
    max_extra_ratio = clamp_float(params.get("edgeSnapMaxExtraRatio"), 0.0, 0.80, 0.24)
    min_marker_fraction = clamp_float(params.get("edgeSnapMinMarkerFraction"), 0.01, 0.65, 0.18)

    candidate = foreground.copy()
    if snap_radius > 0:
        candidate = morphology.dilation(candidate, footprint=morphology.disk(snap_radius))
        relaxed_seed = seedness >= max(0.03, seed_threshold * seedness_scale)
        candidate = candidate & (relaxed_seed | foreground)

    max_candidate_pixels = int(foreground.sum() * (1.0 + max_extra_ratio))
    if max_candidate_pixels > 0 and int(candidate.sum()) > max_candidate_pixels:
        distance_to_foreground = cv2.distanceTransform((~foreground).astype(np.uint8), cv2.DIST_L2, 3)
        extra = candidate & ~foreground
        if extra.any():
            cutoff = float(np.percentile(distance_to_foreground[extra], max(1.0, 100.0 * max_extra_ratio)))
            candidate = foreground | (extra & (distance_to_foreground <= max(1.0, cutoff)))

    markers = np.zeros(labels.shape, dtype=np.int32)
    next_marker = 1
    for source_id in [int(v) for v in np.unique(labels) if v > 0]:
        component = labels == source_id
        marker = component
        if marker_erode > 0 and int(component.sum()) > marker_erode * marker_erode * 8:
            eroded = morphology.erosion(component, footprint=morphology.disk(marker_erode))
            if int(eroded.sum()) >= max(2, int(component.sum() * min_marker_fraction)):
                marker = eroded
            else:
                distance = cv2.distanceTransform(component.astype(np.uint8), cv2.DIST_L2, 5)
                if distance.max() > 0:
                    marker = distance >= max(1.0, float(distance.max()) * 0.46)

        if not marker.any():
            rows, cols = np.where(component)
            if rows.size == 0:
                continue
            markers[int(round(rows.mean())), int(round(cols.mean()))] = next_marker
        else:
            markers[marker] = next_marker
        next_marker += 1

    if markers.max() == 0:
        stats["output_segments"] = 0
        return labels.astype(np.int32), stats

    rgb_float = rgb.astype(np.float32) / 255.0
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY).astype(np.float32) / 255.0
    gray_smooth = cv2.GaussianBlur(gray, (0, 0), 0.85)
    lab = cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB).astype(np.float32)
    lab_l = normalize01(lab[..., 0])
    lab_b = normalize01(lab[..., 2])

    grad_x = cv2.Sobel(gray_smooth, cv2.CV_32F, 1, 0, ksize=3)
    grad_y = cv2.Sobel(gray_smooth, cv2.CV_32F, 0, 1, ksize=3)
    gray_gradient = normalize01(np.sqrt((grad_x * grad_x) + (grad_y * grad_y)))

    lab_l_blur = cv2.GaussianBlur(lab_l, (0, 0), 0.85)
    lab_b_blur = cv2.GaussianBlur(lab_b, (0, 0), 0.85)
    lab_grad_x = cv2.Sobel(lab_l_blur, cv2.CV_32F, 1, 0, ksize=3)
    lab_grad_y = cv2.Sobel(lab_l_blur, cv2.CV_32F, 0, 1, ksize=3)
    yellow_grad_x = cv2.Sobel(lab_b_blur, cv2.CV_32F, 1, 0, ksize=3)
    yellow_grad_y = cv2.Sobel(lab_b_blur, cv2.CV_32F, 0, 1, ksize=3)
    color_gradient = normalize01(
        np.sqrt((lab_grad_x * lab_grad_x) + (lab_grad_y * lab_grad_y))
        + np.sqrt((yellow_grad_x * yellow_grad_x) + (yellow_grad_y * yellow_grad_y))
    )

    local_mean = cv2.GaussianBlur(gray_smooth, (0, 0), 4.0)
    dark_valley = normalize01(local_mean - gray_smooth)
    channel_spread = normalize01(np.std(rgb_float, axis=2))
    seed_low = normalize01(1.0 - cv2.GaussianBlur(seedness.astype(np.float32), (0, 0), 0.9))

    gradient_weight = clamp_float(params.get("edgeSnapGradientWeight"), 0.0, 1.0, 0.42)
    valley_weight = clamp_float(params.get("edgeSnapValleyWeight"), 0.0, 1.0, 0.30)
    color_weight = clamp_float(params.get("edgeSnapColorWeight"), 0.0, 1.0, 0.18)
    seed_weight = clamp_float(params.get("edgeSnapSeednessWeight"), 0.0, 1.0, 0.10)
    elevation = normalize01(
        (gradient_weight * gray_gradient)
        + (valley_weight * dark_valley)
        + (color_weight * normalize01((0.65 * color_gradient) + (0.35 * channel_spread)))
        + (seed_weight * seed_low)
    )

    snapped = watershed(elevation, markers=markers, mask=candidate.astype(bool))
    snapped, _, _ = relabel_sequential(snapped.astype(np.int32))
    stats.update({
        "output_segments": int(snapped.max()),
        "candidate_pixels": int(candidate.sum()),
        "snap_radius": int(snap_radius),
        "marker_erode": int(marker_erode),
    })
    return snapped.astype(np.int32), stats


def parse_int_list(value, default: list[int], low: int, high: int) -> list[int]:
    if value is None:
        raw = default
    elif isinstance(value, (list, tuple)):
        raw = value
    else:
        raw = str(value).replace("[", "").replace("]", "").split(",")

    parsed = []
    for item in raw:
        try:
            number = int(float(str(item).strip()))
        except (TypeError, ValueError):
            continue
        number = max(low, min(high, number))
        if number not in parsed:
            parsed.append(number)
    return parsed or default


def score_dense_candidate(records: list[dict], marker_count: int, params: dict, pixel_count: int) -> tuple[float, dict]:
    count = len(records)
    min_area = clamp_float(params.get("minArea"), 0.0, 10_000_000.0, max(8.0, pixel_count * 0.00002))
    target_count = clamp_float(params.get("denseAutoTargetCount"), 20.0, 10_000.0, 320.0)
    max_count = clamp_float(params.get("denseAutoMaxCount"), 50.0, 20_000.0, max(target_count * 2.2, 850.0))
    if count == 0:
        return -1_000_000.0, {"count": 0, "marker_count": int(marker_count), "median_area": 0.0, "small_ratio": 1.0, "score": -1_000_000.0}

    areas = np.asarray([float(item.get("area_px") or 0.0) for item in records], dtype=np.float32)
    solidities = np.asarray([float(item.get("solidity") or 0.0) for item in records], dtype=np.float32)
    extents = np.asarray([float(item.get("extent") or 0.0) for item in records], dtype=np.float32)
    aspects = np.asarray([float(item.get("aspect_ratio") or 0.0) for item in records], dtype=np.float32)

    median_area = float(np.median(areas))
    small_floor = max(min_area * 1.8, median_area * 0.22)
    small_ratio = float(np.mean(areas < small_floor))
    huge_ratio = float(np.mean(areas > max(median_area * 5.0, min_area * 18.0)))
    long_ratio = float(np.mean(aspects > 4.8))
    median_solidity = float(np.median(solidities))
    median_extent = float(np.median(extents))

    count_score = min(count / max(1.0, target_count), 1.15)
    over_count_penalty = max(0.0, (count - max_count) / max(1.0, max_count))
    marker_over_penalty = max(0.0, (marker_count - max_count * 1.35) / max(1.0, max_count))
    marker_keep_ratio = count / max(1, marker_count)
    marker_loss_penalty = max(0.0, 0.35 - marker_keep_ratio)

    score = (
        120.0 * count_score
        + 55.0 * min(max(median_solidity, 0.0), 1.0)
        + 50.0 * min(max(median_extent, 0.0), 1.0)
        - 95.0 * small_ratio
        - 70.0 * huge_ratio
        - 50.0 * long_ratio
        - 170.0 * over_count_penalty
        - 95.0 * marker_over_penalty
        - 75.0 * marker_loss_penalty
    )

    stats = {
        "count": int(count),
        "marker_count": int(marker_count),
        "median_area": round(median_area, 3),
        "small_ratio": round(small_ratio, 6),
        "huge_ratio": round(huge_ratio, 6),
        "long_ratio": round(long_ratio, 6),
        "median_solidity": round(median_solidity, 6),
        "median_extent": round(median_extent, 6),
        "marker_keep_ratio": round(float(marker_keep_ratio), 6),
        "score": round(float(score), 6),
    }
    return float(score), stats


def auto_tune_dense_pile_watershed(
    mask: np.ndarray,
    rgb: np.ndarray,
    seedness: np.ndarray,
    split_sensitivity: int,
    marker_min_distance: int | None,
    params: dict,
    image_scale: float,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, int, float, dict, dict]:
    marker_candidates = parse_int_list(params.get("denseAutoMarkerDistances"), [8, 10, 12, 14], 4, 60)
    peak_candidates = parse_int_list(params.get("denseAutoPeakPercentiles"), [56, 62, 68], 35, 90)

    base_marker = clamp_int(params.get("denseMarkerMinDistance"), 4, 60, marker_candidates[0])
    base_peak = int(round(clamp_float(params.get("densePeakPercentile"), 35.0, 90.0, peak_candidates[0])))
    if base_marker not in marker_candidates:
        marker_candidates.insert(0, base_marker)
    if base_peak not in peak_candidates:
        peak_candidates.insert(0, base_peak)

    best = None
    candidate_stats = []
    pixel_count = max(1, int(mask.size))

    for marker_distance in marker_candidates[:6]:
        for peak_percentile in peak_candidates[:6]:
            candidate_params = dict(params)
            candidate_params["denseMarkerMinDistance"] = int(marker_distance)
            candidate_params["densePeakPercentile"] = float(peak_percentile)
            labels, distance, markers, used_marker_distance, peak_threshold = dense_pile_watershed(
                mask, rgb, seedness, split_sensitivity, marker_min_distance=marker_min_distance, params=candidate_params
            )
            refined = refine_oversized_segments(
                labels,
                max_area=clamp_int(candidate_params.get("maxArea"), 0, 10_000_000, 0) or None,
                max_length=clamp_int(candidate_params.get("maxLength"), 0, 100_000, 0) or None,
                split_sensitivity=split_sensitivity,
                marker_min_distance=used_marker_distance,
                peak_threshold_rel=peak_threshold,
            )
            snapped, _ = edge_snap_labels(refined, rgb, seedness, candidate_params)
            filled, _ = fill_label_holes(snapped, candidate_params)
            records, _ = measure_segments(filled, candidate_params, seedness=seedness, rgb=rgb, image_scale=image_scale)
            marker_count = int(markers.max()) if markers.size else 0
            score, stats = score_dense_candidate(records, marker_count, candidate_params, pixel_count)
            stats.update({
                "denseMarkerMinDistance": int(marker_distance),
                "densePeakPercentile": float(peak_percentile),
                "used_marker_distance": int(used_marker_distance),
                "peak_threshold": round(float(peak_threshold), 6),
            })
            candidate_stats.append(stats)
            if best is None or score > best["score"]:
                best = {
                    "score": score,
                    "labels": labels,
                    "distance": distance,
                    "markers": markers,
                    "marker_distance": used_marker_distance,
                    "peak_threshold": peak_threshold,
                    "params": candidate_params,
                    "stats": stats,
                }

    if best is None:
        labels, distance, markers, used_marker_distance, peak_threshold = dense_pile_watershed(
            mask, rgb, seedness, split_sensitivity, marker_min_distance=marker_min_distance, params=params
        )
        return labels, distance, markers, used_marker_distance, peak_threshold, params, {"enabled": True, "fallback": True, "candidates": []}

    tuning_stats = {
        "enabled": True,
        "selected": best["stats"],
        "candidates": sorted(candidate_stats, key=lambda item: item["score"], reverse=True)[:8],
    }
    return best["labels"], best["distance"], best["markers"], best["marker_distance"], best["peak_threshold"], best["params"], tuning_stats


def largest_contour(mask: np.ndarray):
    contours, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not contours:
        return None
    return max(contours, key=cv2.contourArea)


def contour_axes(contour: np.ndarray) -> tuple[float, float, float]:
    if len(contour) >= 5:
        (_, _), axes, angle = cv2.fitEllipse(contour)
        return max(float(axes[0]), float(axes[1])), min(float(axes[0]), float(axes[1])), float(angle)

    rect = cv2.minAreaRect(contour)
    box_w, box_h = rect[1]
    length = max(float(box_w), float(box_h))
    width = min(float(box_w), float(box_h))
    if length <= 0 or width <= 0:
        _, _, bbox_w, bbox_h = cv2.boundingRect(contour)
        length = float(max(bbox_w, bbox_h))
        width = float(min(bbox_w, bbox_h))
    return length, width, float(rect[2])


def contour_centroid(contour: np.ndarray, mask: np.ndarray) -> tuple[float, float]:
    moments = cv2.moments(contour)
    if moments["m00"] != 0:
        return moments["m10"] / moments["m00"], moments["m01"] / moments["m00"]
    rows, cols = np.where(mask)
    if len(rows) == 0:
        return 0.0, 0.0
    return float(cols.mean()), float(rows.mean())


def segment_axis_vectors(mask: np.ndarray) -> tuple[np.ndarray, np.ndarray] | None:
    rows, cols = np.where(mask)
    if rows.size < 2:
        return None

    points = np.column_stack((cols.astype(np.float32), rows.astype(np.float32)))
    centered = points - points.mean(axis=0, keepdims=True)
    covariance = np.cov(centered, rowvar=False)
    if not np.isfinite(covariance).all():
        return None

    values, vectors = np.linalg.eigh(covariance)
    order = np.argsort(values)[::-1]
    major = vectors[:, order[0]].astype(np.float32)
    minor = np.asarray([-major[1], major[0]], dtype=np.float32)
    major_norm = float(np.linalg.norm(major))
    minor_norm = float(np.linalg.norm(minor))
    if major_norm <= 0 or minor_norm <= 0:
        return None
    return major / major_norm, minor / minor_norm


def draw_axis_line(
    image: np.ndarray,
    center: tuple[float, float],
    vector: np.ndarray,
    length: float,
    color: tuple[int, int, int],
    thickness: int,
) -> None:
    half = max(1.0, float(length) * 0.38)
    cx, cy = center
    start = (int(round(cx - vector[0] * half)), int(round(cy - vector[1] * half)))
    end = (int(round(cx + vector[0] * half)), int(round(cy + vector[1] * half)))
    cv2.line(image, start, end, color, max(1, thickness), lineType=cv2.LINE_AA)


def build_reference_exclusion_mask(shape: tuple[int, int], params: dict, image_scale: float) -> tuple[np.ndarray | None, dict]:
    stats = {"enabled": False, "pixels": 0, "padding": 0}
    reference_px = clamp_float(params.get("referencePixels"), 0.0, 1_000_000.0, 0.0)
    reference_mm = clamp_float(params.get("referenceMm"), 0.0, 1_000_000.0, 0.0)
    if reference_px <= 0 or reference_mm <= 0:
        return None, stats

    def parse_coord(key: str) -> float:
        try:
            return float(params.get(key))
        except (TypeError, ValueError):
            return float("nan")

    coords = [parse_coord("referenceX1"), parse_coord("referenceY1"), parse_coord("referenceX2"), parse_coord("referenceY2")]
    if not all(np.isfinite(coords)):
        return None, stats

    pixel_space = str(params.get("referencePixelSpace") or "original")
    scale = float(image_scale) if pixel_space == "original" else 1.0
    x1, y1, x2, y2 = [float(v) * scale for v in coords]
    line_px = math.hypot(x2 - x1, y2 - y1)
    if line_px <= 1:
        return None, stats

    default_padding = max(6, int(round(line_px * 0.12)))
    padding = clamp_int(params.get("referenceExcludePadding"), 1, 500, default_padding)
    mask = np.zeros(shape, dtype=np.uint8)
    cv2.line(
        mask,
        (int(round(x1)), int(round(y1))),
        (int(round(x2)), int(round(y2))),
        1,
        thickness=max(1, padding * 2),
        lineType=cv2.LINE_AA,
    )

    stats.update({"enabled": bool(mask.any()), "pixels": int(mask.sum()), "padding": int(padding)})
    return mask.astype(bool), stats


def circular_hue_delta(a: float, b: float) -> float:
    delta = abs(float(a) - float(b))
    return min(delta, 360.0 - delta) / 180.0


def robust_seed_color_model(
    labels: np.ndarray,
    seedness: np.ndarray | None,
    hsv: np.ndarray,
    lab: np.ndarray,
    params: dict,
) -> dict | None:
    if seedness is None or labels.max() == 0:
        return None

    samples = []
    seed_floor = clamp_float(params.get("seedColorModelSeednessFloor"), 0.0, 1.0, 0.42)
    for source_id in [int(v) for v in np.unique(labels) if v > 0]:
        mask = labels == source_id
        area = int(mask.sum())
        if area <= 0:
            continue
        mean_seed = float(seedness[mask].mean())
        if mean_seed < seed_floor:
            continue
        hsv_values = hsv[mask]
        lab_values = lab[mask]
        hue = float(np.mean(hsv_values[:, 0]) * 2.0)
        saturation = float(np.mean(hsv_values[:, 1]) / 255.0)
        value = float(np.mean(hsv_values[:, 2]) / 255.0)
        lab_mean = lab_values.mean(axis=0)
        samples.append((area, mean_seed, hue, saturation, value, lab_mean))

    if len(samples) < 12:
        return None

    samples = sorted(samples, key=lambda item: item[1], reverse=True)
    keep = samples[: max(12, int(len(samples) * 0.55))]
    weights = np.asarray([max(1, item[0]) for item in keep], dtype=np.float32)
    hues = np.asarray([item[2] for item in keep], dtype=np.float32)
    hue_rad = np.deg2rad(hues)
    mean_sin = float(np.average(np.sin(hue_rad), weights=weights))
    mean_cos = float(np.average(np.cos(hue_rad), weights=weights))
    mean_hue = (math.degrees(math.atan2(mean_sin, mean_cos)) + 360.0) % 360.0

    sat = np.asarray([item[3] for item in keep], dtype=np.float32)
    val = np.asarray([item[4] for item in keep], dtype=np.float32)
    lab_stack = np.vstack([item[5] for item in keep]).astype(np.float32)
    seed_values = np.asarray([item[1] for item in keep], dtype=np.float32)
    return {
        "hue": mean_hue,
        "saturation": float(np.median(sat)),
        "value": float(np.median(val)),
        "lab": np.median(lab_stack, axis=0),
        "seedness_floor": max(0.10, float(np.percentile(seed_values, 18)) * 0.62),
        "area_median": float(np.median([item[0] for item in keep])),
    }


def seed_color_distance(
    hue: float,
    saturation: float,
    value: float,
    lab_mean: np.ndarray,
    model: dict | None,
) -> float:
    if model is None:
        return 0.0
    hue_delta = circular_hue_delta(hue, float(model["hue"]))
    sat_delta = abs(float(saturation) - float(model["saturation"]))
    val_delta = abs(float(value) - float(model["value"]))
    lab_delta = float(np.linalg.norm(lab_mean.astype(np.float32) - model["lab"].astype(np.float32)) / 140.0)
    return float((0.34 * hue_delta) + (0.22 * sat_delta) + (0.18 * val_delta) + (0.26 * lab_delta))


def build_skin_like_mask(rgb: np.ndarray) -> np.ndarray:
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV).astype(np.float32)
    ycrcb = cv2.cvtColor(rgb, cv2.COLOR_RGB2YCrCb).astype(np.float32)
    hue = hsv[..., 0] * 2.0
    saturation = hsv[..., 1] / 255.0
    value = hsv[..., 2] / 255.0
    y = ycrcb[..., 0]
    cr = ycrcb[..., 1]
    cb = ycrcb[..., 2]

    hsv_skin = (
        ((hue <= 38.0) | (hue >= 345.0))
        & (saturation >= 0.18)
        & (saturation <= 0.78)
        & (value >= 0.32)
    )
    ycrcb_skin = (y >= 45.0) & (cr >= 133.0) & (cr <= 185.0) & (cb >= 75.0) & (cb <= 145.0)
    skin = hsv_skin & ycrcb_skin
    skin = morphology.remove_small_objects(skin.astype(bool), min_size=32)
    skin = morphology.closing(skin.astype(bool), footprint=morphology.disk(2))
    return skin.astype(bool)


def measure_segments(
    labels: np.ndarray,
    params: dict,
    seedness: np.ndarray | None = None,
    rgb: np.ndarray | None = None,
    image_scale: float = 1.0,
) -> tuple[list[dict], np.ndarray]:
    min_area = clamp_int(params.get("minArea"), 0, 10_000_000, 0)
    max_area = clamp_int(params.get("maxArea"), 0, 10_000_000, 0) or None
    min_length = clamp_int(params.get("minLength"), 0, 100_000, 0)
    max_length = clamp_int(params.get("maxLength"), 0, 100_000, 0) or None
    min_width = clamp_float(params.get("minWidth"), 0.0, 100_000.0, 0.0)
    max_width = clamp_float(params.get("maxWidth"), 0.0, 100_000.0, 0.0) or None
    max_aspect_ratio = clamp_float(params.get("maxSegmentAspectRatio"), 1.2, 50.0, 10.5)
    min_solidity = clamp_float(params.get("minSegmentSolidity"), 0.0, 0.99, 0.52)
    min_extent = clamp_float(params.get("minSegmentExtent"), 0.0, 0.99, 0.18)
    seed_threshold = clamp_float(params.get("seednessThreshold"), 0.05, 0.95, 0.30)
    min_segment_seedness = clamp_float(
        params.get("minSegmentSeednessMean"),
        0.0,
        1.0,
        min(0.96, seed_threshold + 0.012),
    )
    reject_border_segments = coerce_bool(params.get("rejectBorderSegments"), False)
    border_margin = clamp_int(params.get("borderMargin"), 0, 60, 2)
    reference_px = clamp_float(params.get("referencePixels"), 0.0, 1_000_000.0, 0.0)
    reference_mm = clamp_float(params.get("referenceMm"), 0.0, 1_000_000.0, 0.0)
    reference_pixel_space = str(params.get("referencePixelSpace") or "original")
    if reference_pixel_space == "original":
        reference_px *= max(1e-9, float(image_scale))
    pixels_per_mm = reference_px / reference_mm if reference_px > 0 and reference_mm > 0 else None
    reference_exclusion, exclusion_stats = build_reference_exclusion_mask(labels.shape, params, image_scale)
    exclusion_overlap_ratio = clamp_float(params.get("referenceExcludeOverlapRatio"), 0.05, 1.0, 0.45)
    reject_non_seed = coerce_bool(params.get("rejectNonSeedObjects"), True)
    max_seed_color_distance = clamp_float(params.get("maxSeedColorDistance"), 0.05, 1.5, 0.34)
    min_non_seed_seedness = clamp_float(params.get("minNonSeedObjectSeedness"), 0.0, 1.0, 0.085)
    large_non_seed_area_multiplier = clamp_float(params.get("largeNonSeedAreaMultiplier"), 1.0, 80.0, 8.0)
    hard_max_area_ratio = clamp_float(params.get("hardMaxObjectAreaRatio"), 0.0001, 0.50, 0.12)
    hard_max_area = int(labels.size * hard_max_area_ratio)
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV).astype(np.float32) if rgb is not None else None
    lab = cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB).astype(np.float32) if rgb is not None else None
    skin_like_mask = build_skin_like_mask(rgb) if reject_non_seed and rgb is not None else None
    seed_color_model = (
        robust_seed_color_model(labels, seedness, hsv, lab, params)
        if reject_non_seed and hsv is not None and lab is not None
        else None
    )

    records = []
    filtered = np.zeros(labels.shape, dtype=np.int32)
    rejected_non_seed = 0

    for source_id in [int(v) for v in np.unique(labels) if v > 0]:
        mask = labels == source_id
        contour = largest_contour(mask)
        if contour is None:
            continue

        area = float(cv2.contourArea(contour))
        if area <= 0:
            area = float(mask.sum())
        mask_area = int(mask.sum())

        length, width, angle = contour_axes(contour)
        aspect_ratio = float(length / max(width, 1e-6))
        x, y, bbox_w, bbox_h = cv2.boundingRect(contour)
        bbox_area = max(1.0, float(bbox_w * bbox_h))
        extent = float(area / bbox_area)
        hull = cv2.convexHull(contour)
        hull_area = float(cv2.contourArea(hull))
        solidity = float(area / hull_area) if hull_area > 0 else 0.0
        centroid_x, centroid_y = contour_centroid(contour, mask)
        mean_seedness = None
        if seedness is not None:
            seed_values = seedness[mask]
            mean_seedness = float(seed_values.mean()) if seed_values.size else 0.0
        skin_overlap_ratio = 0.0
        if skin_like_mask is not None:
            skin_overlap_ratio = int((mask & skin_like_mask).sum()) / max(1, mask_area)
        color_distance = 0.0
        if seed_color_model is not None and hsv is not None and lab is not None:
            hsv_values = hsv[mask]
            lab_values = lab[mask]
            hue = float(np.mean(hsv_values[:, 0]) * 2.0)
            saturation = float(np.mean(hsv_values[:, 1]) / 255.0)
            value = float(np.mean(hsv_values[:, 2]) / 255.0)
            lab_mean = lab_values.mean(axis=0)
            color_distance = seed_color_distance(hue, saturation, value, lab_mean, seed_color_model)
            seedness_floor = float(seed_color_model["seedness_floor"])
            typical_area = max(1.0, float(seed_color_model.get("area_median") or 1.0))
            large_object = area > typical_area * large_non_seed_area_multiplier
            huge_object = hard_max_area > 0 and mask_area > hard_max_area
            very_low_seedness = mean_seedness is not None and mean_seedness < min_non_seed_seedness
            weak_seedness = mean_seedness is None or mean_seedness < seedness_floor
            large_low_seedness = large_object and mean_seedness is not None and mean_seedness < max(seedness_floor, 0.20)
            saturation_gap = abs(saturation - float(seed_color_model["saturation"]))
            value_gap = abs(value - float(seed_color_model["value"]))
            clearly_foreign_color = (
                color_distance > max_seed_color_distance
                or saturation_gap > 0.34
                or value_gap > 0.42
            )
            shape_not_seed_like = (
                aspect_ratio < 1.18
                or aspect_ratio > max(18.0, max_aspect_ratio * 1.7)
                or solidity < 0.18
                or extent < 0.06
            )
            skin_like_object = (
                skin_overlap_ratio >= 0.40
                and area > typical_area * 4.0
                and (large_object or weak_seedness or shape_not_seed_like or color_distance > max_seed_color_distance * 0.55)
            )
            if skin_like_object:
                rejected_non_seed += 1
                continue
            if huge_object and (weak_seedness or clearly_foreign_color or shape_not_seed_like):
                rejected_non_seed += 1
                continue
            if large_low_seedness and (clearly_foreign_color or shape_not_seed_like or area > typical_area * 14.0):
                rejected_non_seed += 1
                continue
            if very_low_seedness and (clearly_foreign_color or large_object):
                rejected_non_seed += 1
                continue
            if clearly_foreign_color and weak_seedness:
                rejected_non_seed += 1
                continue
            if large_object and shape_not_seed_like and color_distance > max_seed_color_distance * 0.78:
                rejected_non_seed += 1
                continue
        if reference_exclusion is not None:
            overlap = int((mask & reference_exclusion).sum())
            overlap_ratio = overlap / max(1, int(mask.sum()))
            center_x = int(round(centroid_x))
            center_y = int(round(centroid_y))
            center_inside_reference = (
                0 <= center_y < reference_exclusion.shape[0]
                and 0 <= center_x < reference_exclusion.shape[1]
                and bool(reference_exclusion[center_y, center_x])
            )
            if overlap_ratio >= exclusion_overlap_ratio or (center_inside_reference and overlap_ratio >= 0.18):
                exclusion_stats["removed_segments"] = int(exclusion_stats.get("removed_segments", 0)) + 1
                continue

        if area < min_area:
            continue
        if max_area and area > max_area:
            continue
        if length < min_length:
            continue
        if max_length and length > max_length:
            continue
        if width < min_width:
            continue
        if max_width and width > max_width:
            continue
        if aspect_ratio > max_aspect_ratio:
            continue
        if solidity < min_solidity:
            continue
        if extent < min_extent:
            continue
        if mean_seedness is not None and mean_seedness < min_segment_seedness:
            continue
        if reject_border_segments and touches_border((y, x, y + bbox_h, x + bbox_w), labels.shape, border_margin):
            continue

        grain_id = len(records) + 1
        filtered[mask] = grain_id

        record = {
            "id": grain_id,
            "area_px": round(area, 3),
            "length_px": round(float(length), 3),
            "width_px": round(float(width), 3),
            "area_mm2": None,
            "length_mm": None,
            "width_mm": None,
            "centroid_x": round(float(centroid_x), 3),
            "centroid_y": round(float(centroid_y), 3),
            "bbox_x": int(x),
            "bbox_y": int(y),
            "bbox_w": int(bbox_w),
            "bbox_h": int(bbox_h),
            "angle_deg": round(float(angle), 3),
            "solidity": round(solidity, 6),
            "extent": round(extent, 6),
            "aspect_ratio": round(aspect_ratio, 6),
            "mean_seedness": round(mean_seedness, 6) if mean_seedness is not None else None,
            "seed_color_distance": round(float(color_distance), 6),
        }

        if pixels_per_mm:
            record["area_mm2"] = round(area / (pixels_per_mm * pixels_per_mm), 5)
            record["length_mm"] = round(float(length) / pixels_per_mm, 5)
            record["width_mm"] = round(float(width) / pixels_per_mm, 5)

        records.append(record)

    if rejected_non_seed:
        logger.info("Rejected %d non-seed-like segments by color model", rejected_non_seed)
    return records, filtered


def color_for_id(grain_id: int) -> tuple[int, int, int]:
    palette = (
        (36, 116, 201),
        (206, 83, 80),
        (48, 150, 106),
        (222, 159, 45),
        (119, 87, 169),
        (41, 161, 183),
        (189, 95, 153),
        (96, 105, 116),
    )
    return palette[(grain_id - 1) % len(palette)]


def draw_overlay(
    rgb: np.ndarray,
    labels: np.ndarray,
    records: list[dict],
    show_labels: bool = True,
    fill_alpha: float = 0.28,
    line_width: int = 2,
    show_axes: bool = False,
) -> np.ndarray:
    overlay = rgb.copy()
    fill = rgb.copy()

    for record in records:
        grain_id = int(record["id"])
        mask = labels == grain_id
        color = np.asarray(color_for_id(grain_id), dtype=np.uint8)
        fill[mask] = np.round((0.38 * fill[mask]) + (0.62 * color)).astype(np.uint8)

    fill_alpha = float(np.clip(fill_alpha, 0.0, 1.0))
    overlay = cv2.addWeighted(fill, fill_alpha, overlay, 1.0 - fill_alpha, 0)

    for record in records:
        grain_id = int(record["id"])
        mask = labels == grain_id
        contour = largest_contour(mask)
        if contour is None:
            continue

        color = color_for_id(grain_id)
        cv2.drawContours(overlay, [contour], -1, color, max(1, int(line_width)), lineType=cv2.LINE_AA)
        axes = segment_axis_vectors(mask) if show_axes else None
        if axes is not None:
            center = (float(record["centroid_x"]), float(record["centroid_y"]))
            major, minor = axes
            draw_axis_line(
                overlay,
                center,
                major,
                float(record["length_px"]),
                (245, 247, 250),
                1,
            )
            draw_axis_line(
                overlay,
                center,
                minor,
                float(record["width_px"]),
                (255, 205, 72),
                1,
            )
        if not show_labels:
            continue

        cx = int(round(float(record["centroid_x"])))
        cy = int(round(float(record["centroid_y"])))
        cv2.putText(overlay, str(grain_id), (cx + 3, cy - 3), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (20, 24, 28), 3, lineType=cv2.LINE_AA)
        cv2.putText(overlay, str(grain_id), (cx + 3, cy - 3), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (255, 255, 255), 1, lineType=cv2.LINE_AA)

    return overlay.astype(np.uint8)


def png_base64(rgb: np.ndarray) -> str:
    buffer = BytesIO()
    Image.fromarray(rgb.astype(np.uint8)).save(buffer, format="PNG")
    return base64.b64encode(buffer.getvalue()).decode("ascii")


def labels_preview_base64(labels: np.ndarray) -> str:
    if labels.size == 0:
        return ""
    preview = PALETTE[np.mod(labels, len(PALETTE))]
    preview[labels == 0] = [0, 0, 0]
    return png_base64(preview)


def cluster_preview_base64(labels: np.ndarray) -> str:
    return png_base64(PALETTE[np.mod(labels, len(PALETTE))])


def mask_base64(mask: np.ndarray) -> str:
    rgb = np.repeat((mask.astype(np.uint8) * 255)[..., None], 3, axis=2)
    return png_base64(rgb)


def records_to_csv(records: list[dict]) -> str:
    output = StringIO()
    writer = csv.DictWriter(output, fieldnames=CSV_COLUMNS, extrasaction="ignore")
    writer.writeheader()
    for record in records:
        writer.writerow({column: record.get(column) for column in CSV_COLUMNS})
    return output.getvalue()


def summarize(records: list[dict]) -> dict:
    if not records:
        return {
            "count": 0,
            "mean_area_px": 0,
            "mean_length_px": 0,
            "mean_width_px": 0,
            "mean_area_mm2": None,
            "mean_length_mm": None,
            "mean_width_mm": None,
        }

    area = np.asarray([r["area_px"] for r in records], dtype=np.float32)
    length = np.asarray([r["length_px"] for r in records], dtype=np.float32)
    width = np.asarray([r["width_px"] for r in records], dtype=np.float32)
    summary = {
        "count": len(records),
        "mean_area_px": round(float(area.mean()), 3),
        "mean_length_px": round(float(length.mean()), 3),
        "mean_width_px": round(float(width.mean()), 3),
        "min_length_px": round(float(length.min()), 3),
        "max_length_px": round(float(length.max()), 3),
    }
    calibrated = [r for r in records if r.get("length_mm") is not None and r.get("width_mm") is not None]
    if calibrated:
        area_mm2 = np.asarray([r["area_mm2"] for r in calibrated], dtype=np.float32)
        length_mm = np.asarray([r["length_mm"] for r in calibrated], dtype=np.float32)
        width_mm = np.asarray([r["width_mm"] for r in calibrated], dtype=np.float32)
        summary.update({
            "mean_area_mm2": round(float(area_mm2.mean()), 5),
            "mean_length_mm": round(float(length_mm.mean()), 5),
            "mean_width_mm": round(float(width_mm.mean()), 5),
            "min_length_mm": round(float(length_mm.min()), 5),
            "max_length_mm": round(float(length_mm.max()), 5),
        })
    else:
        summary.update({
            "mean_area_mm2": None,
            "mean_length_mm": None,
            "mean_width_mm": None,
            "min_length_mm": None,
            "max_length_mm": None,
        })
    return summary


def analyze(image_path: Path, params: dict) -> dict:
    max_side = clamp_int(params.get("maxSide"), 400, 3000, 2000)
    pc_index = clamp_int(params.get("pcIndex"), 0, 2, 0)
    k = clamp_int(params.get("k"), 1, 10, 5)
    split_sensitivity = clamp_int(params.get("splitSensitivity"), 1, 10, 6)
    cluster_space = str(params.get("clusterSpace") or "pca3")
    watershed_mode = str(params.get("watershedMode") or "dense")
    pca_method = str(params.get("pcaMethod") or "correlation")
    if pca_method not in {"correlation", "covariance"}:
        pca_method = "correlation"
    rgb_index_weight = clamp_float(params.get("rgbIndexWeight"), 0.0, 1.0, 0.65)

    prepared = read_image(image_path, max_side=max_side)
    height, width = prepared.rgb.shape[:2]
    pixel_count = height * width

    params.setdefault("minArea", max(20, int(pixel_count * 0.000035)))
    params.setdefault("maxArea", max(int(params["minArea"]) + 1, int(pixel_count * 0.006)))
    params.setdefault("maxLength", int(max(height, width) * 0.18))
    params.setdefault("maskSource", "sam")
    params.setdefault("samModelType", "fast_sam")
    params.setdefault("useSamInstances", True)
    mask_source = str(params.get("maskSource") or "auto")
    reference_px = clamp_float(params.get("referencePixels"), 0.0, 1_000_000.0, 0.0)
    reference_mm = clamp_float(params.get("referenceMm"), 0.0, 1_000_000.0, 0.0)
    reference_pixel_space = str(params.get("referencePixelSpace") or "original")
    adjusted_reference_px = reference_px * max(1e-9, float(prepared.scale)) if reference_pixel_space == "original" else reference_px
    mm_per_pixel = reference_mm / adjusted_reference_px if adjusted_reference_px > 0 and reference_mm > 0 else None

    seed_mask, seedness = build_seed_color_mask(prepared.rgb, params)
    needs_kmeans = mask_source in {"kmeans", "hybrid", "auto", "sam+hybrid"}
    if needs_kmeans:
        features, feature_names = build_color_features(prepared.rgb)
        rgb_pcs, rgb_explained = compute_pca_images(features[..., :3], method=pca_method)
        index_features = features[..., 3:] if features.shape[-1] > 3 else features
        index_pcs, index_explained = compute_pca_images(index_features, method=pca_method)
        pcs = blend_pca_images(rgb_pcs, index_pcs, rgb_index_weight)
        explained = [
            round(float(((1.0 - rgb_index_weight) * rgb_explained[idx]) + (rgb_index_weight * index_explained[idx])), 6)
            for idx in range(len(rgb_explained))
        ]
        if cluster_space == "rgbPca":
            cluster_input = rgb_pcs
        elif cluster_space == "indexPca":
            cluster_input = index_pcs
        elif cluster_space in {"rgbPc", "rgb_pc"}:
            cluster_input = rgb_pcs[..., pc_index]
        elif cluster_space in {"indexPc", "index_pc"}:
            cluster_input = index_pcs[..., pc_index]
        else:
            cluster_input = pcs if cluster_space in {"pca3", "gridfreePca"} else pcs[..., pc_index]
        cluster_labels, centers, counts = run_kmeans(cluster_input, k=k)
        stats = cluster_stats(cluster_labels, prepared.rgb, k)
        if params.get("selectedClusters") is None:
            selected_clusters = suggest_foreground_clusters(cluster_labels, k, stats)
        else:
            selected_clusters = parse_selected_clusters(params.get("selectedClusters"), cluster_labels, k)
        kmeans_mask = build_binary_mask(cluster_labels, selected_clusters, params)
    else:
        _, feature_names = build_color_features(prepared.rgb[:1, :1, :])
        rgb_explained = [0.0, 0.0, 0.0]
        index_explained = [0.0, 0.0, 0.0]
        explained = [0.0, 0.0, 0.0]
        cluster_labels = np.zeros((height, width), dtype=np.int32)
        centers = []
        counts = [int(pixel_count)]
        stats = []
        selected_clusters = []
        kmeans_mask = np.zeros((height, width), dtype=bool)
    raw_mask = combine_masks(seed_mask, kmeans_mask, params)

    # ── SAM mask override ───────────────────────────────────
    sam_summary = None
    sam_instance_labels = None
    if mask_source == "sam":
        try:
            if coerce_bool(params.get("useSamInstances"), True):
                labels_result, sam_summary = build_sam_labels(prepared.rgb, params)
                if int(labels_result.max()) > 0:
                    sam_instance_labels = labels_result.astype(np.int32)
                    raw_mask = sam_instance_labels > 0
                else:
                    sam_result = build_sam_mask(prepared.rgb, params)
                    raw_mask = sam_result
                    sam_summary["fallback"] = "binary_sam_mask"
                    sam_summary["pixels"] = int(sam_result.sum())
                    sam_summary["ratio"] = round(float(sam_result.mean()), 6)
            else:
                sam_result = build_sam_mask(prepared.rgb, params)
                raw_mask = sam_result
                sam_summary = {
                    "enabled": True,
                    "pixels": int(sam_result.sum()),
                    "ratio": round(float(sam_result.mean()), 6),
                }
        except Exception as exc:
            logger.warning("SAM failed, falling back to hybrid: %s", exc)
            sam_summary = {
                "enabled": True,
                "error": str(exc),
                "fallback": "hybrid",
            }
    elif mask_source == "sam+hybrid":
        try:
            sam_result = build_sam_mask(prepared.rgb, params)
            # Kết hợp SAM mask với raw_mask hiện tại
            combined_mask = raw_mask.astype(bool) | sam_result.astype(bool)
            raw_mask = combined_mask
            sam_summary = {
                "enabled": True,
                "mode": "sam+hybrid",
                "sam_pixels": int(sam_result.sum()),
                "hybrid_pixels": int((raw_mask.astype(bool) & ~sam_result).sum()),
                "combined_pixels": int(combined_mask.sum()),
            }
        except Exception as exc:
            logger.warning("SAM+hybrid failed, using hybrid alone: %s", exc)
            sam_summary = {
                "enabled": True,
                "mode": "sam+hybrid",
                "error": str(exc),
                "fallback": "hybrid",
            }

    mask, mask_filter_stats = filter_foreground_mask(raw_mask, seedness, prepared.rgb, params)
    image_profile_type, image_profile_params, image_profile_stats = profile_image_context(
        prepared.rgb,
        raw_mask,
        mask,
        seedness,
        params,
    )
    if coerce_bool(params.get("autoImageProfile"), True):
        params.update(image_profile_params)
        watershed_mode = str(params.get("watershedMode") or watershed_mode)
    dense_pile_mode = should_use_dense_pile_mode(raw_mask, mask, mask_filter_stats, params)
    precomputed_dense_tune = None
    precomputed_dense_effective_params = None
    if dense_pile_mode:
        foreground_pixels_after_filter = int(mask_filter_stats.get("pixels_after") or int(mask.sum()))
        foreground_components_after_filter = int(mask_filter_stats.get("component_count_after") or 0)
        dense_mask = None
        dense_mask_stats = {}
        if coerce_bool(params.get("autoSurfaceTune"), True):
            mask_candidates = parse_int_list(params.get("denseAutoMaskPercentiles"), [24, 28, 34], 5, 45)
            best_pipeline = None
            pipeline_candidates = []
            for mask_percentile in mask_candidates[:4]:
                candidate_params = dict(params)
                candidate_params["denseMaskPercentile"] = float(mask_percentile)
                candidate_mask, candidate_mask_stats = build_dense_pile_mask(prepared.rgb, seedness, candidate_params)
                if int(candidate_mask.sum()) < max(100, int(pixel_count * 0.12)):
                    candidate_mask = raw_mask.astype(bool) if raw_mask.any() else np.ones(mask.shape, dtype=bool)
                    candidate_mask_stats["dense_mask_fallback"] = True
                    candidate_mask_stats["dense_mask_pixels"] = int(candidate_mask.sum())
                    candidate_mask_stats["dense_mask_ratio"] = round(float(candidate_mask.mean()), 6)

                candidate_effective = dense_pile_params(candidate_params, pixel_count)
                (
                    candidate_labels,
                    candidate_distance,
                    candidate_markers,
                    candidate_marker_distance,
                    candidate_peak_threshold,
                    candidate_effective,
                    candidate_tune_stats,
                ) = auto_tune_dense_pile_watershed(
                    candidate_mask,
                    prepared.rgb,
                    seedness,
                    split_sensitivity,
                    marker_min_distance=None,
                    params=candidate_effective,
                    image_scale=prepared.scale,
                )
                selected = dict(candidate_tune_stats.get("selected") or {})
                mask_ratio = float(candidate_mask.mean())
                score = float(selected.get("score", -1_000_000.0))
                score -= max(0.0, mask_ratio - 0.88) * 140.0
                score -= max(0.0, 0.16 - mask_ratio) * 220.0
                selected.update({
                    "denseMaskPercentile": float(mask_percentile),
                    "dense_mask_ratio": round(mask_ratio, 6),
                    "pipeline_score": round(float(score), 6),
                })
                pipeline_candidates.append(selected)
                if best_pipeline is None or score > best_pipeline["score"]:
                    candidate_tune_stats["selected"] = selected
                    best_pipeline = {
                        "score": score,
                        "mask": candidate_mask,
                        "mask_stats": candidate_mask_stats,
                        "labels": candidate_labels,
                        "distance": candidate_distance,
                        "markers": candidate_markers,
                        "marker_distance": candidate_marker_distance,
                        "peak_threshold": candidate_peak_threshold,
                        "effective_params": candidate_effective,
                        "tune_stats": candidate_tune_stats,
                    }

            if best_pipeline is not None:
                dense_mask = best_pipeline["mask"]
                dense_mask_stats = best_pipeline["mask_stats"]
                precomputed_dense_effective_params = best_pipeline["effective_params"]
                precomputed_dense_tune = (
                    best_pipeline["labels"],
                    best_pipeline["distance"],
                    best_pipeline["markers"],
                    best_pipeline["marker_distance"],
                    best_pipeline["peak_threshold"],
                    best_pipeline["tune_stats"],
                )
                dense_mask_stats["dense_pipeline_candidates"] = sorted(
                    pipeline_candidates,
                    key=lambda item: float(item.get("pipeline_score", item.get("score", -1_000_000.0))),
                    reverse=True,
                )[:8]

        if dense_mask is None:
            dense_mask, dense_mask_stats = build_dense_pile_mask(prepared.rgb, seedness, params)
            if int(dense_mask.sum()) < max(100, int(pixel_count * 0.12)):
                dense_mask = raw_mask.astype(bool) if raw_mask.any() else np.ones(mask.shape, dtype=bool)
                dense_mask_stats["dense_mask_fallback"] = True
                dense_mask_stats["dense_mask_pixels"] = int(dense_mask.sum())
                dense_mask_stats["dense_mask_ratio"] = round(float(dense_mask.mean()), 6)
        mask = dense_mask
        mask_filter_stats = dict(mask_filter_stats)
        mask_filter_stats.update({
            "dense_pile_override": True,
            "pixels_after_foreground_filter": foreground_pixels_after_filter,
            "component_count_after_foreground_filter": foreground_components_after_filter,
            "pixels_after": int(mask.sum()),
            "component_count_after": int(measure.label(mask, connectivity=2).max()) if mask.any() else 0,
        })
        mask_filter_stats.update(dense_mask_stats)

    if dense_pile_mode:
        threshold_stats = {
            "enabled": coerce_bool(params.get("dynamicThresholds"), False),
            "component_count": int(measure.label(mask, connectivity=2).max()) if mask.any() else 0,
            "candidate_count": 0,
            "mean_area": 0.0,
            "median_area": 0.0,
            "suggested_min_area": None,
            "suggested_max_area": None,
            "suggested_min_length": None,
            "suggested_max_length": None,
            "suggested_marker_min_distance": None,
            "dense_pile_override": True,
        }
        effective_params = precomputed_dense_effective_params or dense_pile_params(params, pixel_count)
    else:
        threshold_stats = estimate_dynamic_thresholds(mask, params)
        effective_params = apply_dynamic_thresholds(params, threshold_stats)
    dynamic_marker_distance = (
        threshold_stats.get("suggested_marker_min_distance")
        if coerce_bool(effective_params.get("dynamicMarkerSearch"), True)
        else None
    )

    dense_auto_tune_stats = {"enabled": False}
    if dense_pile_mode:
        if precomputed_dense_tune is not None:
            labels, distance, markers, marker_distance, peak_threshold, dense_auto_tune_stats = precomputed_dense_tune
        elif coerce_bool(effective_params.get("autoSurfaceTune"), True):
            labels, distance, markers, marker_distance, peak_threshold, effective_params, dense_auto_tune_stats = auto_tune_dense_pile_watershed(
                mask,
                prepared.rgb,
                seedness,
                split_sensitivity,
                marker_min_distance=dynamic_marker_distance,
                params=effective_params,
                image_scale=prepared.scale,
            )
        else:
            labels, distance, markers, marker_distance, peak_threshold = dense_pile_watershed(
                mask,
                prepared.rgb,
                seedness,
                split_sensitivity,
                marker_min_distance=dynamic_marker_distance,
                params=effective_params,
            )
        effective_watershed_mode = "dense_pile"
    elif watershed_mode == "distance":
        labels, distance, markers, marker_distance, peak_threshold = watershed_split(
            mask,
            split_sensitivity,
            marker_min_distance=dynamic_marker_distance,
        )
        effective_watershed_mode = "distance"
    else:
        labels, distance, markers, marker_distance, peak_threshold = dense_seed_watershed(
            mask,
            prepared.rgb,
            seedness,
            split_sensitivity,
            marker_min_distance=dynamic_marker_distance,
        )
        effective_watershed_mode = "dense"
    refined_labels = refine_oversized_segments(
        labels,
        max_area=clamp_int(effective_params.get("maxArea"), 0, 10_000_000, 0) or None,
        max_length=clamp_int(effective_params.get("maxLength"), 0, 100_000, 0) or None,
        split_sensitivity=split_sensitivity,
        marker_min_distance=marker_distance,
        peak_threshold_rel=peak_threshold,
    )
    snapped_labels, edge_snap_stats = edge_snap_labels(
        refined_labels,
        prepared.rgb,
        seedness,
        effective_params,
    )
    measured_source_labels, label_fill_stats = fill_label_holes(snapped_labels, effective_params)
    records, measured_labels = measure_segments(
        measured_source_labels,
        effective_params,
        seedness=seedness,
        rgb=prepared.rgb,
        image_scale=prepared.scale,
    )

    if sam_instance_labels is not None:
        sam_params = dict(effective_params)
        sam_params["minArea"] = 1
        sam_params["maxArea"] = 0
        sam_params["minLength"] = 0
        sam_params["maxLength"] = 0
        sam_params["minWidth"] = 0
        sam_params["maxWidth"] = 0
        sam_params["maxSegmentAspectRatio"] = 50.0
        sam_params["minSegmentSeednessMean"] = 0
        sam_params["minSegmentSolidity"] = 0.0
        sam_params["minSegmentExtent"] = 0.0
        measured_source_labels, label_fill_stats = fill_label_holes(sam_instance_labels, sam_params)
        records, measured_labels = measure_segments(
            measured_source_labels,
            sam_params,
            seedness=seedness,
            rgb=prepared.rgb,
            image_scale=prepared.scale,
        )
        mask = measured_labels > 0
        mask_filter_stats = {
            "sam_instances": True,
            "pixels_after": int(mask.sum()),
            "component_count_after": int(measured_labels.max()) if measured_labels.size else 0,
        }
        dense_pile_mode = False
        refined_labels = sam_instance_labels
        markers = sam_instance_labels
        marker_distance = 0
        peak_threshold = 0.0
        effective_watershed_mode = "sam_instances"
        threshold_stats = {
            "enabled": False,
            "component_count": int(sam_instance_labels.max()) if sam_instance_labels.size else 0,
            "candidate_count": int(sam_summary.get("candidate_count") or 0) if sam_summary else 0,
            "sam_instances": True,
        }
        effective_params = sam_params

    overlay = draw_overlay(
        prepared.rgb,
        measured_labels,
        records,
        show_labels=not dense_pile_mode,
        fill_alpha=0.16 if dense_pile_mode else 0.28,
        line_width=1 if dense_pile_mode else 2,
        show_axes=coerce_bool(params.get("showMeasurementAxes"), False),
    )
    csv_text = records_to_csv(records)

    result = {
        "image": {
            "width": width,
            "height": height,
            "original_width": prepared.original_width,
            "original_height": prepared.original_height,
            "scale": round(float(prepared.scale), 6),
        },
        "features": {
            "names": feature_names,
            "pca_explained_variance": explained,
            "rgb_pca_explained_variance": rgb_explained,
            "index_pca_explained_variance": index_explained,
            "pc_index": pc_index,
            "pca_method": pca_method,
            "rgb_index_weight": round(float(rgb_index_weight), 3),
        },
        "kmeans": {
            "k": k,
            "cluster_space": cluster_space,
            "centers": centers,
            "counts": counts,
            "stats": stats,
            "selected_clusters": selected_clusters,
        },
        "segmentation": {
            "raw_mask_pixels": int(raw_mask.sum()),
            "mask_pixels": int(mask.sum()),
            "marker_count": int(markers.max()) if markers.size else 0,
            "segment_count_before_filter": int(refined_labels.max()) if refined_labels.size else 0,
            "marker_min_distance": int(marker_distance),
            "peak_threshold_rel": round(float(peak_threshold), 6),
            "split_sensitivity": split_sensitivity,
            "edge_snap": edge_snap_stats,
            "label_fill": label_fill_stats,
            "image_profile": image_profile_stats,
            "segmentation_mode": "dense_pile" if dense_pile_mode else "foreground",
            "watershed_mode": effective_watershed_mode,
            "requested_watershed_mode": watershed_mode,
            "mask_source": str(params.get("maskSource") or "auto"),
            "mask_filter": mask_filter_stats,
            "sam": sam_summary,
            "dense_auto_tune": dense_auto_tune_stats,
            "dynamic_thresholds": threshold_stats,
            "effective_thresholds": {
                "minArea": effective_params.get("minArea"),
                "maxArea": effective_params.get("maxArea"),
                "minLength": effective_params.get("minLength"),
                "maxLength": effective_params.get("maxLength"),
            },
        },
        "calibration": {
            "enabled": bool(mm_per_pixel),
            "reference_pixels": round(float(reference_px), 6) if reference_px > 0 else None,
            "reference_mm": round(float(reference_mm), 6) if reference_mm > 0 else None,
            "reference_pixel_space": reference_pixel_space,
            "image_scale": round(float(prepared.scale), 6),
            "mm_per_pixel": round(float(mm_per_pixel), 8) if mm_per_pixel else None,
            "pixels_per_mm": round(float(1.0 / mm_per_pixel), 6) if mm_per_pixel else None,
        },
        "summary": summarize(records),
        "measurements": records,
        "csv": csv_text,
        "overlay_png_base64": png_base64(overlay),
        "cluster_png_base64": cluster_preview_base64(cluster_labels),
        "mask_png_base64": mask_base64(mask),
        "seed_mask_png_base64": mask_base64(seed_mask),
        "kmeans_mask_png_base64": mask_base64(kmeans_mask),
        "labels_png_base64": labels_preview_base64(measured_labels),
    }

    if params.get("includeIntermediate") in (True, "true", "1", 1):
        result["pc_png_base64"] = mask_base64(pcs[..., pc_index] > 0.5)

    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True)
    parser.add_argument("--params-json", default="{}")
    args = parser.parse_args()

    try:
        params = json.loads(args.params_json or "{}")
        result = analyze(Path(args.image), params)
        sys.stdout.write(json.dumps({"ok": True, "data": result}, ensure_ascii=False))
        return 0
    except Exception as exc:
        sys.stdout.write(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
