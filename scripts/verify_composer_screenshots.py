#!/usr/bin/env python3
"""Reject composer screenshots obscured by a centered iOS permission dialog.

The CI screenshot fixture is only useful when its composer is actually visible.
This heuristic checks relative luminance of two regions; it does not OCR or
record personal content, and does not identify the cause of the system alert.
"""
import argparse
from pathlib import Path
from statistics import median

from PIL import Image


def patch_median(image, rect):
    width, height = image.size
    x1, y1, x2, y2 = rect
    patch = image.crop((
        int(width * x1), int(height * y1),
        int(width * x2), int(height * y2),
    )).resize((32, 32))
    return float(median(patch.getpixel((x, y))
                        for y in range(32) for x in range(32)))


def has_centered_system_alert(path):
    with Image.open(path) as source:
        image = source.convert("L")
    if min(image.size) < 200:
        raise ValueError("invalid screenshot dimensions")
    outside = patch_median(image, (0.03, 0.38, 0.11, 0.56))
    center = patch_median(image, (0.44, 0.38, 0.56, 0.56))
    return outside < 210 and center > 220 and center - outside > 30


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("screenshots", nargs="+", type=Path)
    args = parser.parse_args()
    failures = []
    for path in args.screenshots:
        if not path.is_file():
            failures.append(path.name + ": missing")
        elif has_centered_system_alert(path):
            failures.append(path.name + ": system alert obscures composer")
    if failures:
        raise SystemExit("Composer screenshot QA failed: " + "; ".join(failures))
    print("Composer screenshots free of centered system alerts:", len(args.screenshots))


if __name__ == "__main__":
    main()
