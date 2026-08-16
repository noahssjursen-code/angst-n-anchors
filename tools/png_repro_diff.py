#!/usr/bin/env python3
"""Compare two directories of PNGs captured by two runs of the same rig.

Reports, per frame, the percentage of pixels whose RGB differs at all, and the
largest per-channel delta in that frame. The two numbers answer different
questions and both are needed:

  * a frame can move 95% of its pixels by 1/255 — a real lighting change too
    small to see, which nonetheless moves the md5 and makes any md5 comparison
    worthless;
  * a frame can move 0.9% of its pixels by 241/255 — a one-pixel outline around
    every silhouette edge, which is a sub-pixel geometry or rasterisation race.

Exit 0 when every common frame is byte-identical, 1 when any frame moved, 2 on
a usage or file error.  Used by tools/repro.sh.
"""
import hashlib
import os
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.stderr.write("png_repro_diff: Pillow is not installed\n")
    sys.exit(2)


def md5(path):
    with open(path, "rb") as handle:
        return hashlib.md5(handle.read()).hexdigest()


def compare(path_a, path_b):
    """(percent of pixels differing, worst per-channel delta) or None on size mismatch."""
    image_a = Image.open(path_a).convert("RGB")
    image_b = Image.open(path_b).convert("RGB")
    if image_a.size != image_b.size:
        return None
    data_a = image_a.tobytes()
    data_b = image_b.tobytes()
    pixels = image_a.size[0] * image_a.size[1]
    moved = 0
    worst = 0
    for index in range(0, len(data_a), 3):
        d0 = abs(data_a[index] - data_b[index])
        d1 = abs(data_a[index + 1] - data_b[index + 1])
        d2 = abs(data_a[index + 2] - data_b[index + 2])
        delta = max(d0, d1, d2)
        if delta:
            moved += 1
            if delta > worst:
                worst = delta
    return 100.0 * moved / pixels, worst


def main(argv):
    if len(argv) < 3:
        sys.stderr.write("usage: png_repro_diff.py <dir-run1> <dir-run2> [label]\n")
        return 2
    dir_a, dir_b = argv[1], argv[2]
    label = argv[3] if len(argv) > 3 else os.path.basename(dir_a.rstrip("/"))
    files_a = {f for f in os.listdir(dir_a) if f.endswith(".png")}
    files_b = {f for f in os.listdir(dir_b) if f.endswith(".png")}
    common = sorted(files_a & files_b)
    only_a = sorted(files_a - files_b)
    only_b = sorted(files_b - files_a)

    if not common:
        print("%s: REPRO INDETERMINATE — no frame written by both runs" % label)
        return 1

    moved_frames = []
    worst_pct = 0.0
    worst_name = ""
    worst_delta = 0
    for name in common:
        a = os.path.join(dir_a, name)
        b = os.path.join(dir_b, name)
        if md5(a) == md5(b):
            continue
        result = compare(a, b)
        if result is None:
            print("   %-52s SIZE MISMATCH" % name)
            moved_frames.append(name)
            worst_pct = 100.0
            worst_name = name
            continue
        pct, delta = result
        moved_frames.append(name)
        print("   %-52s %8.4f%% of pixels, worst channel delta %d/255" % (name, pct, delta))
        if pct > worst_pct:
            worst_pct, worst_name = pct, name
        worst_delta = max(worst_delta, delta)

    for name in only_a:
        print("   %-52s written by run 1 only" % name)
    for name in only_b:
        print("   %-52s written by run 2 only" % name)

    if moved_frames or only_a or only_b:
        print(
            "%s: NOT REPRODUCIBLE — %d of %d frames moved, worst %.4f%% (%s), "
            "largest channel delta %d/255"
            % (label, len(moved_frames), len(common), worst_pct, worst_name, worst_delta)
        )
        return 1
    print("%s: REPRODUCIBLE — %d frames byte-identical across two runs" % (label, len(common)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
