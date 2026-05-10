#!/usr/bin/env python3
"""Batch-convert HEIC files to JPEG/PNG/WebP using all CPU cores."""

import argparse
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import pillow_heif
from PIL import Image

pillow_heif.register_heif_opener()


def convert_one(src: Path, out_dir: Path, fmt: str, quality: int) -> str:
    dst = out_dir / f"{src.stem}.{fmt}"
    img = Image.open(src)
    img.save(dst, format=fmt.upper(), quality=quality)
    return f"{src.name} -> {dst.name}"


def main():
    p = argparse.ArgumentParser(description="Batch-convert HEIC photos.")
    p.add_argument("input", nargs="?", default=".", help="Directory with HEIC files (default: current dir)")
    p.add_argument("-o", "--output", help="Output directory (default: <input>/converted)")
    p.add_argument("-f", "--format", default="jpeg", choices=["jpeg", "png", "webp"], help="Output format (default: jpeg)")
    p.add_argument("-q", "--quality", type=int, default=90, help="Quality 1-100, ignored for PNG (default: 90)")
    p.add_argument("-w", "--workers", type=int, default=None, help="Worker processes (default: all CPUs)")
    args = p.parse_args()

    in_dir = Path(args.input).resolve()
    out_dir = Path(args.output).resolve() if args.output else in_dir / "converted"
    files = sorted(in_dir.glob("*.HEIC")) + sorted(in_dir.glob("*.heic"))

    if not files:
        print(f"No HEIC files found in {in_dir}")
        sys.exit(1)

    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"Converting {len(files)} files to {args.format.upper()} -> {out_dir}")

    t0 = time.time()
    done, failed = 0, 0

    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(convert_one, f, out_dir, args.format, args.quality): f for f in files}
        for fut in as_completed(futures):
            try:
                print(f"  [{done + failed + 1}/{len(files)}] {fut.result()}")
                done += 1
            except Exception as e:
                print(f"  FAILED {futures[fut].name}: {e}", file=sys.stderr)
                failed += 1

    elapsed = time.time() - t0
    print(f"\nDone: {done} converted, {failed} failed in {elapsed:.1f}s")


if __name__ == "__main__":
    main()
