from __future__ import annotations

import argparse
import base64
import csv
import json
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
            not_too_bright = value <= 0.92
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
    hole_size = clamp_int(params.get("holeSize"), 1, 50_000, 64)

    mask = np.isin(labels, np.asarray(selected_clusters, dtype=np.int32))
    if opening_radius > 0:
        mask = morphology.opening(mask, footprint=morphology.disk(opening_radius))
    if closing_radius > 0:
        mask = morphology.closing(mask, footprint=morphology.disk(closing_radius))
    if noise_size > 1:
        mask = morphology.remove_small_objects(mask, max_size=noise_size)
    if hole_size > 1:
        mask = morphology.remove_small_holes(mask, max_size=hole_size)
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
    hole_size = clamp_int(params.get("holeSize"), 1, 50_000, 64)

    if opening_radius > 0:
        mask = morphology.opening(mask, footprint=morphology.disk(opening_radius))
    if closing_radius > 0:
        mask = morphology.closing(mask, footprint=morphology.disk(closing_radius))
    if noise_size > 1:
        mask = morphology.remove_small_objects(mask, max_size=noise_size)
    if hole_size > 1:
        mask = morphology.remove_small_holes(mask, max_size=hole_size)

    return mask.astype(bool), seedness.astype(np.float32)


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
    suggested_marker = int(np.clip(round(math.sqrt(max(1.0, median_area)) * shrink_factor), 3, 40))

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

    if coerce_bool(params.get("dynamicDiagonalThresholds"), True):
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
        marker_distance = min(int(marker_distance), sensitivity_distance)

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
        marker_distance = min(int(np.clip(marker_min_distance, 3, 40)), sensitivity_distance)
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


def measure_segments(
    labels: np.ndarray,
    params: dict,
    seedness: np.ndarray | None = None,
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

    records = []
    filtered = np.zeros(labels.shape, dtype=np.int32)

    for source_id in [int(v) for v in np.unique(labels) if v > 0]:
        mask = labels == source_id
        contour = largest_contour(mask)
        if contour is None:
            continue

        area = float(cv2.contourArea(contour))
        if area <= 0:
            area = float(mask.sum())

        length, width, angle = contour_axes(contour)
        aspect_ratio = float(length / max(width, 1e-6))
        x, y, bbox_w, bbox_h = cv2.boundingRect(contour)
        bbox_area = max(1.0, float(bbox_w * bbox_h))
        extent = float(area / bbox_area)
        hull = cv2.convexHull(contour)
        hull_area = float(cv2.contourArea(hull))
        solidity = float(area / hull_area) if hull_area > 0 else 0.0
        mean_seedness = None
        if seedness is not None:
            seed_values = seedness[mask]
            mean_seedness = float(seed_values.mean()) if seed_values.size else 0.0

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

        centroid_x, centroid_y = contour_centroid(contour, mask)
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
        }

        if pixels_per_mm:
            record["area_mm2"] = round(area / (pixels_per_mm * pixels_per_mm), 5)
            record["length_mm"] = round(float(length) / pixels_per_mm, 5)
            record["width_mm"] = round(float(width) / pixels_per_mm, 5)

        records.append(record)

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


def draw_overlay(rgb: np.ndarray, labels: np.ndarray, records: list[dict]) -> np.ndarray:
    overlay = rgb.copy()
    fill = rgb.copy()

    for record in records:
        grain_id = int(record["id"])
        mask = labels == grain_id
        color = np.asarray(color_for_id(grain_id), dtype=np.uint8)
        fill[mask] = np.round((0.38 * fill[mask]) + (0.62 * color)).astype(np.uint8)

    overlay = cv2.addWeighted(fill, 0.28, overlay, 0.72, 0)

    for record in records:
        grain_id = int(record["id"])
        mask = labels == grain_id
        contour = largest_contour(mask)
        if contour is None:
            continue

        color = color_for_id(grain_id)
        cv2.drawContours(overlay, [contour], -1, color, 2, lineType=cv2.LINE_AA)
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
        }

    area = np.asarray([r["area_px"] for r in records], dtype=np.float32)
    length = np.asarray([r["length_px"] for r in records], dtype=np.float32)
    width = np.asarray([r["width_px"] for r in records], dtype=np.float32)
    return {
        "count": len(records),
        "mean_area_px": round(float(area.mean()), 3),
        "mean_length_px": round(float(length.mean()), 3),
        "mean_width_px": round(float(width.mean()), 3),
        "min_length_px": round(float(length.min()), 3),
        "max_length_px": round(float(length.max()), 3),
    }


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
    params.setdefault("maskSource", "auto")

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
    seed_mask, seedness = build_seed_color_mask(prepared.rgb, params)
    raw_mask = combine_masks(seed_mask, kmeans_mask, params)
    mask, mask_filter_stats = filter_foreground_mask(raw_mask, seedness, prepared.rgb, params)
    threshold_stats = estimate_dynamic_thresholds(mask, params)
    effective_params = apply_dynamic_thresholds(params, threshold_stats)
    dynamic_marker_distance = (
        threshold_stats.get("suggested_marker_min_distance")
        if coerce_bool(effective_params.get("dynamicMarkerSearch"), True)
        else None
    )

    if watershed_mode == "distance":
        labels, distance, markers, marker_distance, peak_threshold = watershed_split(
            mask,
            split_sensitivity,
            marker_min_distance=dynamic_marker_distance,
        )
    else:
        labels, distance, markers, marker_distance, peak_threshold = dense_seed_watershed(
            mask,
            prepared.rgb,
            seedness,
            split_sensitivity,
            marker_min_distance=dynamic_marker_distance,
        )
    refined_labels = refine_oversized_segments(
        labels,
        max_area=clamp_int(effective_params.get("maxArea"), 0, 10_000_000, 0) or None,
        max_length=clamp_int(effective_params.get("maxLength"), 0, 100_000, 0) or None,
        split_sensitivity=split_sensitivity,
        marker_min_distance=marker_distance,
        peak_threshold_rel=peak_threshold,
    )
    records, measured_labels = measure_segments(
        refined_labels,
        effective_params,
        seedness=seedness,
        image_scale=prepared.scale,
    )

    overlay = draw_overlay(prepared.rgb, measured_labels, records)
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
            "watershed_mode": watershed_mode,
            "mask_source": str(params.get("maskSource") or "auto"),
            "mask_filter": mask_filter_stats,
            "dynamic_thresholds": threshold_stats,
            "effective_thresholds": {
                "minArea": effective_params.get("minArea"),
                "maxArea": effective_params.get("maxArea"),
                "minLength": effective_params.get("minLength"),
                "maxLength": effective_params.get("maxLength"),
            },
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
