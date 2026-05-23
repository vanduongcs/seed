from __future__ import annotations

import csv
from io import StringIO

import cv2
import numpy as np

from .config import CSV_COLUMNS, float_param, int_param
from .yolo_segment import InstanceMask

SEED_CLASS_IDS = {0}
SEED_CLASS_NAMES = {"seed"}


def filter_and_measure(instances: list[InstanceMask], params: dict, scale: float) -> tuple[np.ndarray, list[dict], int]:
    min_area = int_param(params, "minArea")
    max_area = int_param(params, "maxArea")
    max_aspect = float_param(params, "maxSegmentAspectRatio")
    min_solidity = float_param(params, "minSegmentSolidity")
    min_extent = float_param(params, "minSegmentExtent")
    pixel_to_mm = calibration_factor(params, scale)

    if not instances:
        return np.zeros((1, 1), dtype=np.int32), [], 0

    height, width = instances[0].mask.shape[:2]
    labels = np.zeros((height, width), dtype=np.int32)
    measurements: list[dict] = []
    reference_line = reference_line_points(params, scale, width, height)
    excluded_reference_object_count = 0

    for instance in sorted(instances, key=lambda item: item.confidence, reverse=True):
        if not is_seed_instance(instance):
            continue
        if reference_line is not None and is_reference_object(instance.mask, reference_line):
            excluded_reference_object_count += 1
            continue
        available = np.logical_and(instance.mask, labels == 0)
        metrics = mask_metrics(available)
        if metrics is None:
            continue
        if metrics["area_px"] < min_area or metrics["area_px"] > max_area:
            continue
        if metrics["aspect_ratio"] > max_aspect:
            continue
        if metrics["solidity"] < min_solidity or metrics["extent"] < min_extent:
            continue

        item_id = len(measurements) + 1
        labels[available] = item_id
        measurement = {
            "id": item_id,
            **metrics,
            "area_mm2": round(metrics["area_px"] * pixel_to_mm * pixel_to_mm, 6) if pixel_to_mm else 0.0,
            "length_mm": round(metrics["length_px"] * pixel_to_mm, 6) if pixel_to_mm else 0.0,
            "width_mm": round(metrics["width_px"] * pixel_to_mm, 6) if pixel_to_mm else 0.0,
            "confidence": round(instance.confidence, 6),
            "class_id": instance.class_id,
            "class_name": instance.class_name,
        }
        measurements.append(measurement)

    return labels, measurements, excluded_reference_object_count


def is_seed_instance(instance: InstanceMask) -> bool:
    return instance.class_id in SEED_CLASS_IDS or str(instance.class_name).strip().lower() in SEED_CLASS_NAMES


def mask_metrics(mask: np.ndarray) -> dict | None:
    area = int(np.count_nonzero(mask))
    if area <= 0:
        return None
    ys, xs = np.nonzero(mask)
    x, y, w, h = cv2.boundingRect(np.column_stack([xs, ys]).astype(np.int32))
    contours, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None
    contour = max(contours, key=cv2.contourArea)
    hull = cv2.convexHull(contour)
    hull_area = max(float(cv2.contourArea(hull)), 1.0)
    rect = cv2.minAreaRect(contour)
    (rect_w, rect_h) = rect[1]
    length = max(float(rect_w), float(rect_h), 1.0)
    width = max(min(float(rect_w), float(rect_h)), 1.0)
    return {
        "area_px": area,
        "length_px": round(length, 3),
        "width_px": round(width, 3),
        "centroid_x": round(float(xs.mean()), 3),
        "centroid_y": round(float(ys.mean()), 3),
        "bbox_x": int(x),
        "bbox_y": int(y),
        "bbox_w": int(w),
        "bbox_h": int(h),
        "angle_deg": round(float(rect[2]), 3),
        "solidity": round(float(area / hull_area), 6),
        "extent": round(float(area / max(w * h, 1)), 6),
        "aspect_ratio": round(float(length / width), 6),
    }


def calibration_factor(params: dict, scale: float) -> float:
    reference_pixels = float_param(params, "referencePixels")
    reference_mm = float_param(params, "referenceMm")
    if reference_pixels <= 0 or reference_mm <= 0:
        return 0.0
    pixel_space = str(params.get("referencePixelSpace") or "original").strip().lower()
    processed_pixels = reference_pixels * scale if pixel_space != "processed" else reference_pixels
    return reference_mm / max(processed_pixels, 1e-6)


def reference_line_points(params: dict, scale: float, width: int, height: int) -> tuple[int, int, int, int] | None:
    points = [
        float_param(params, "referenceX1"),
        float_param(params, "referenceY1"),
        float_param(params, "referenceX2"),
        float_param(params, "referenceY2"),
    ]
    if min(points) < 0:
        return None
    pixel_space = str(params.get("referencePixelSpace") or "original").strip().lower()
    coordinate_scale = scale if pixel_space != "processed" else 1.0
    x1, y1, x2, y2 = [int(round(value * coordinate_scale)) for value in points]
    if x1 == x2 and y1 == y2:
        return None
    return (
        max(0, min(width - 1, x1)),
        max(0, min(height - 1, y1)),
        max(0, min(width - 1, x2)),
        max(0, min(height - 1, y2)),
    )


def is_reference_object(mask: np.ndarray, line: tuple[int, int, int, int]) -> bool:
    x1, y1, x2, y2 = line
    distance = float(np.hypot(x2 - x1, y2 - y1))
    sample_count = max(2, int(np.ceil(distance)) + 1)
    xs = np.rint(np.linspace(x1, x2, sample_count)).astype(np.int32)
    ys = np.rint(np.linspace(y1, y2, sample_count)).astype(np.int32)
    line_coverage = float(np.count_nonzero(mask[ys, xs])) / float(sample_count)
    midpoint_inside = bool(mask[int(round((y1 + y2) / 2)), int(round((x1 + x2) / 2))])
    return midpoint_inside and line_coverage >= 0.55


def measurements_csv(measurements: list[dict]) -> str:
    buffer = StringIO()
    writer = csv.DictWriter(buffer, fieldnames=CSV_COLUMNS, extrasaction="ignore", lineterminator="\n")
    writer.writeheader()
    for item in measurements:
        writer.writerow(item)
    return buffer.getvalue()


def summary_for(measurements: list[dict]) -> dict:
    if not measurements:
        return {
            "count": 0,
            "total_area_px": 0,
            "mean_area_px": 0,
            "mean_length_px": 0,
            "mean_width_px": 0,
            "mean_area_mm2": 0,
            "mean_length_mm": 0,
            "mean_width_mm": 0,
        }

    def mean(name: str) -> float:
        return round(sum(float(item.get(name, 0) or 0) for item in measurements) / len(measurements), 6)

    return {
        "count": len(measurements),
        "total_area_px": int(sum(int(item.get("area_px", 0) or 0) for item in measurements)),
        "mean_area_px": mean("area_px"),
        "mean_length_px": mean("length_px"),
        "mean_width_px": mean("width_px"),
        "mean_area_mm2": mean("area_mm2"),
        "mean_length_mm": mean("length_mm"),
        "mean_width_mm": mean("width_mm"),
    }
