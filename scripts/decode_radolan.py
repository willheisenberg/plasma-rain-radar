#!/usr/bin/env python3
import argparse
import sys
from pathlib import Path

import numpy as np

try:
    import wradlib as wrl
except Exception as exc:  # pragma: no cover
    print(f"wradlib import failed: {exc}", file=sys.stderr)
    sys.exit(3)


def normalize(data: np.ndarray) -> np.ndarray:
    arr = np.array(data, dtype=np.float32)
    arr[~np.isfinite(arr)] = np.nan
    arr[arr < 0.0] = np.nan

    if np.all(np.isnan(arr)):
        return np.zeros(arr.shape, dtype=np.float32)

    lo = float(np.nanpercentile(arr, 5.0))
    hi = float(np.nanpercentile(arr, 95.0))
    if not np.isfinite(lo) or not np.isfinite(hi) or hi <= lo:
        hi = float(np.nanmax(arr))
        lo = 0.0
        if hi <= lo:
            hi = lo + 1.0

    arr = (arr - lo) / (hi - lo)
    arr = np.clip(arr, 0.0, 1.0)
    arr[np.isnan(arr)] = 0.0
    return arr


def colormap(norm: np.ndarray) -> np.ndarray:
    # Light-weight rain-style color ramp (blue -> green -> yellow -> red)
    stops = np.array([0.0, 0.25, 0.5, 0.75, 1.0], dtype=np.float32)
    colors = np.array(
        [
            [13, 31, 76],
            [37, 164, 210],
            [71, 176, 74],
            [250, 212, 70],
            [214, 53, 55],
        ],
        dtype=np.float32,
    )

    flat = norm.reshape(-1)
    rgb = np.empty((flat.size, 3), dtype=np.uint8)
    for c in range(3):
        rgb[:, c] = np.interp(flat, stops, colors[:, c]).astype(np.uint8)
    return rgb.reshape(norm.shape[0], norm.shape[1], 3)


def write_ppm(path: Path, rgb: np.ndarray) -> None:
    h, w, _ = rgb.shape
    with path.open("wb") as f:
        f.write(f"P6\\n{w} {h}\\n255\\n".encode("ascii"))
        f.write(rgb.tobytes(order="C"))


def try_decode(src: Path, dst: Path) -> bool:
    try:
        data, _attrs = wrl.io.radolan.read_radolan_composite(str(src))
    except Exception:
        return False

    if hasattr(data, "filled"):
        data = data.filled(np.nan)

    norm = normalize(np.asarray(data))
    rgb = colormap(norm)
    write_ppm(dst, rgb)
    return True


def candidate_files(root: Path):
    for p in sorted(root.rglob("*")):
        if not p.is_file():
            continue
        lower = p.name.lower()
        if lower.endswith((".png", ".jpg", ".jpeg", ".gif", ".webp", ".ppm", ".json", ".txt", ".xml", ".html")):
            continue
        if p.stat().st_size < 2048:
            continue
        yield p


def main() -> int:
    parser = argparse.ArgumentParser(description="Decode RADOLAN composites into PPM frames")
    parser.add_argument("--input-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--max-files", type=int, default=12)
    args = parser.parse_args()

    src_root = Path(args.input_dir)
    out_root = Path(args.output_dir)
    out_root.mkdir(parents=True, exist_ok=True)

    decoded = 0
    for i, src in enumerate(candidate_files(src_root)):
        if decoded >= args.max_files:
            break
        dst = out_root / f"decoded_{decoded:02d}.ppm"
        if try_decode(src, dst):
            decoded += 1

    if decoded == 0:
        print("no radolan files decoded", file=sys.stderr)
        return 2

    print(f"decoded={decoded}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
