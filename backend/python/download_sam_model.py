#!/usr/bin/env python3
"""
Download SAM models for grain analysis.

Supports:
- MobileSAM (~40MB) - Lightweight, suitable for desktop + mobile export
- SAM2 Tiny (~48MB) - Better quality, suitable for desktop
- SAM2 Small (~90MB) - Balanced quality/speed for desktop
- FastSAM (~140MB) - YOLOv8-based, fast detection + segmentation

Usage:
  python download_sam_model.py              # Default: MobileSAM
  python download_sam_model.py --model sam2_tiny
  python download_sam_model.py --model mobile_sam
  python download_sam_model.py --model fast_sam
  python download_sam_model.py --output ./custom_models
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path
from urllib.request import urlretrieve

# Model registry
MODEL_REGISTRY = {
    "mobile_sam": {
        "name": "MobileSAM",
        "checkpoint": "mobile_sam.pt",
        "url": "https://github.com/ChaoningZhang/MobileSAM/raw/master/weights/mobile_sam.pt",
        "sha256": None,
        "description": "Lightweight SAM with TinyViT backbone (~40MB). TFLite exportable.",
        "size_mb": 40,
        "mobile_exportable": True,
        "inference_type": "segment_anything",
    },
    "sam2_tiny": {
        "name": "SAM2 Tiny",
        "checkpoint": "sam2_tiny.pt",
        "url": "https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_tiny.pt",
        "sha256": None,
        "description": "SAM2.1 Hiera Tiny backbone (~48MB). TFLite exportable.",
        "size_mb": 48,
        "mobile_exportable": True,
        "inference_type": "sam2",
    },
    "sam2_small": {
        "name": "SAM2 Small",
        "checkpoint": "sam2_small.pt",
        "url": "https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_small.pt",
        "sha256": None,
        "description": "SAM2.1 Hiera Small backbone (~90MB). Desktop only.",
        "size_mb": 90,
        "mobile_exportable": False,
        "inference_type": "sam2",
    },
    "fast_sam": {
        "name": "FastSAM",
        "checkpoint": "FastSAM-x.pt",
        "url": "https://github.com/ultralytics/assets/releases/download/v8.2.0/FastSAM-x.pt",
        "sha256": None,
        "description": "YOLOv8-seg based (~140MB). Fast detection + segmentation.",
        "size_mb": 140,
        "mobile_exportable": False,
        "inference_type": "fast_sam",
    },
}

MODELS_DIR = Path(__file__).resolve().parent / "models"


def compute_sha256(filepath: Path) -> str:
    """Compute SHA-256 hash for integrity verification."""
    sha = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            sha.update(chunk)
    return sha.hexdigest()


def download_model(model_key: str, output_dir: Path, force: bool = False) -> Path:
    """Download model checkpoint to specified directory."""
    if model_key not in MODEL_REGISTRY:
        available = ", ".join(MODEL_REGISTRY.keys())
        print(f"[ERROR] Model '{model_key}' not supported. Options: {available}")
        sys.exit(1)

    info = MODEL_REGISTRY[model_key]
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / info["checkpoint"]

    if output_path.exists() and not force:
        print(f"[OK] Model already exists: {output_path}")
        print(f"     Use --force to re-download.")
        return output_path

    print(f"[DOWNLOAD] {info['name']}...")
    print(f"           URL: {info['url']}")
    print(f"           Size: ~{info['size_mb']}MB")
    print(f"           Dest: {output_path}")

    try:
        urlretrieve(info["url"], output_path)

        file_size_mb = output_path.stat().st_size / (1024 * 1024)
        print(f"[OK] Downloaded ({file_size_mb:.1f}MB)")

        if info["sha256"]:
            actual = compute_sha256(output_path)
            if actual != info["sha256"]:
                print(f"[WARN] SHA-256 mismatch!")
                print(f"       Expected: {info['sha256'][:16]}...")
                print(f"       Actual:   {actual[:16]}...")
            else:
                print(f"       SHA-256 verified.")

        return output_path

    except Exception as e:
        print(f"[ERROR] Download failed: {e}")
        if output_path.exists():
            output_path.unlink()
        sys.exit(1)


def print_model_info(model_key: str) -> None:
    """Print model details."""
    info = MODEL_REGISTRY[model_key]
    print(f"\n{'='*60}")
    print(f"  {info['name']}")
    print(f"{'='*60}")
    print(f"  File:        {info['checkpoint']}")
    print(f"  Size:        ~{info['size_mb']}MB")
    print(f"  Inference:   {info['inference_type']}")
    print(f"  TFLite:      {'Yes' if info['mobile_exportable'] else 'No'}")
    print(f"  Description: {info['description']}")
    print()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Download SAM model for grain analysis",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python download_sam_model.py                        # Download MobileSAM (default)
  python download_sam_model.py --model sam2_tiny      # Download SAM2 Tiny
  python download_sam_model.py --model fast_sam       # Download FastSAM
  python download_sam_model.py --output ./my_models   # Custom output directory
  python download_sam_model.py --list                 # List available models
  python download_sam_model.py --force                # Force re-download
        """,
    )
    parser.add_argument(
        "--model",
        type=str,
        default="mobile_sam",
        choices=list(MODEL_REGISTRY.keys()),
        help="Model to download (default: mobile_sam)",
    )
    parser.add_argument(
        "--output",
        type=str,
        default=str(MODELS_DIR),
        help=f"Output directory (default: {MODELS_DIR})",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-download even if file exists",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List all available models",
    )

    args = parser.parse_args()

    if args.list:
        print("\nAvailable SAM models:\n")
        for key in MODEL_REGISTRY:
            print_model_info(key)
        return 0

    output_dir = Path(args.output)
    print_model_info(args.model)
    download_model(args.model, output_dir, force=args.force)

    print(f"\nNext steps:")
    print(f"   1. Ensure dependencies: pip install segment-anything")
    print(f"   2. Use sam_helper.py for inference")
    print(f"   3. Or run analyze_grains.py with --mask-source sam")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())