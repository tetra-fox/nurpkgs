#!/usr/bin/env python3
# Convert a directory of Windows .ani files into a hyprcursor source tree
# (manifest.hl + hyprcursors/<shape>/{meta.hl, *.svg}) ready to be packaged
# by `hyprcursor-util --create`.
#
# ANI is a RIFF('ACON') container holding N CUR frames in a LIST 'fram'
# chunk, plus an `anih` header with frame timing in 1/60s "jiffies" and
# optional `rate`/`seq ` chunks for per-step overrides. We pull out each
# CUR's hotspot from its ICONDIRENTRY, then shell out to ImageMagick to
# decode each frame to RGBA pixels with the AND-mask alpha applied
# (Pillow's CUR loader ignores the AND mask, so we can't use it).
#
# The frames are 32px pixel art with no larger source art. Rather than ship
# raster PNGs that get resampled at any non-native cursor size, we emit each
# frame as an SVG whose pixels are <rect> squares on a 32-unit viewBox. The
# shape is then resolution-independent: hyprcursor's resvg renderer draws it
# crisp at any size, downscaling to 26 or upscaling past 32, with no blur and
# no resize_algorithm involved. shape-rendering=crispEdges plus integer-
# aligned rects keeps adjacent squares seamless. Runs of same-colour pixels on
# a row merge into one rect to keep the files small.

import argparse
import json
import pathlib
import re
import struct
import subprocess
import sys


def parse_ani(data: bytes):
    if data[:4] != b"RIFF" or data[8:12] != b"ACON":
        raise ValueError("not a RIFF/ACON file")
    pos = 12
    chunks: dict[bytes, bytes] = {}
    icons: list[bytes] = []
    while pos + 8 <= len(data):
        cid = data[pos : pos + 4]
        sz = struct.unpack("<I", data[pos + 4 : pos + 8])[0]
        body = data[pos + 8 : pos + 8 + sz]
        if cid == b"LIST" and body[:4] == b"fram":
            p = 4
            while p + 8 <= len(body):
                sub_id = body[p : p + 4]
                sub_sz = struct.unpack("<I", body[p + 4 : p + 8])[0]
                if sub_id == b"icon":
                    icons.append(body[p + 8 : p + 8 + sub_sz])
                p += 8 + sub_sz + (sub_sz & 1)
        else:
            chunks[cid] = body
        pos += 8 + sz + (sz & 1)

    anih = chunks[b"anih"]
    _, cFrames, cSteps, _, _, _, _, jifRate, _ = struct.unpack("<9I", anih[:36])
    if b"rate" in chunks:
        rates = list(struct.unpack(f"<{cSteps}I", chunks[b"rate"]))
    else:
        rates = [jifRate] * cSteps
    if b"seq " in chunks:
        seq = list(struct.unpack(f"<{cSteps}I", chunks[b"seq "]))
    else:
        seq = list(range(cSteps))
    return icons, seq, rates


def cur_hotspot(cur: bytes) -> tuple[int, int, int, int]:
    # ICONDIR(6) + ICONDIRENTRY(16); we only consider the first entry
    width = cur[6] or 256
    height = cur[7] or 256
    hot_x, hot_y = struct.unpack("<HH", cur[10:14])
    return width, height, hot_x, hot_y


def decode_frame(cur: bytes, idx: int, tmp_dir: pathlib.Path) -> tuple[int, int, dict]:
    # decode the CUR to RGBA via ImageMagick and read back its pixels. returns
    # the canvas size and a {(x, y): (r, g, b, alpha)} map of non-transparent
    # pixels. ImageMagick trims to the bitmap it finds, which can be smaller
    # than the 32x32 cursor canvas, so we read the reported geometry and place
    # pixels at their own coordinates.
    cur_path = tmp_dir / f"_frame{idx:03d}.cur"
    cur_path.write_bytes(cur)
    txt = subprocess.run(
        ["magick", str(cur_path), "-depth", "8", "txt:-"],
        check=True, capture_output=True, text=True,
    ).stdout
    cur_path.unlink()

    pixels: dict[tuple[int, int], tuple[int, int, int, float]] = {}
    w = h = 0
    for line in txt.splitlines():
        m = re.match(r"(\d+),(\d+): \(([^)]*)\)", line)
        if not m:
            continue
        x, y = int(m.group(1)), int(m.group(2))
        w, h = max(w, x + 1), max(h, y + 1)
        comps = [c.strip() for c in m.group(3).split(",")]
        r, g, b = (int(round(float(v))) for v in comps[:3])
        # alpha may come back 0..255 or as a 0..1 float depending on build
        a = float(comps[3]) if len(comps) > 3 else 255.0
        alpha = a / 255.0 if a > 1.0 else a
        if alpha == 0.0:
            continue
        pixels[(x, y)] = (r, g, b, alpha)
    return w, h, pixels


def write_svg(path: pathlib.Path, w: int, h: int, pixels: dict) -> None:
    # one <rect> per horizontal run of identical pixels. crispEdges keeps the
    # squares hard and seamless at any render size.
    rects = []
    for y in range(h):
        x = 0
        while x < w:
            col = pixels.get((x, y))
            if col is None:
                x += 1
                continue
            run = x
            while pixels.get((run + 1, y)) == col:
                run += 1
            width = run - x + 1
            r, g, b, alpha = col
            op = f' fill-opacity="{alpha:.3f}"' if alpha < 0.999 else ""
            rects.append(
                f'<rect x="{x}" y="{y}" width="{width}" height="1" '
                f'fill="#{r:02x}{g:02x}{b:02x}"{op}/>'
            )
            x = run + 1
    body = "\n".join(rects)
    path.write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
        f'viewBox="0 0 {w} {h}" shape-rendering="crispEdges">\n{body}\n</svg>\n'
    )


def write_meta(path: pathlib.Path, hot_x_frac: float, hot_y_frac: float,
               size: int, frames: list[tuple[str, int]], overrides: list[str]) -> None:
    lines = [
        f"hotspot_x = {hot_x_frac:.6f}",
        f"hotspot_y = {hot_y_frac:.6f}",
    ]
    for o in overrides:
        lines.append(f"define_override = {o}")
    for filename, duration_ms in frames:
        # `define_size = <size>, <file>, <duration_ms>`. duration_ms must be > 0
        # for animated; we always pass it (a single frame with duration is
        # treated as static by the renderer). size is the nominal native size;
        # the svg renders at whatever the caller requests.
        lines.append(f"define_size = {size}, {filename}, {max(1, duration_ms)}")
    path.write_text("\n".join(lines) + "\n")


def convert_one(ani_path: pathlib.Path, shape_dir: pathlib.Path,
                shape: str, overrides: list[str]) -> None:
    icons, seq, rates = parse_ani(ani_path.read_bytes())
    shape_dir.mkdir(parents=True, exist_ok=True)

    # decode each unique icon once and write its svg, keyed by index in the
    # fram LIST. the CUR header gives the authoritative canvas size and
    # hotspot; ImageMagick decodes onto that same full canvas so the pixel
    # coordinates and the hotspot share one frame of reference.
    rendered: dict[int, tuple[str, int, int, int, int]] = {}
    for icon_idx, cur in enumerate(icons):
        canvas_w, canvas_h, hx, hy = cur_hotspot(cur)
        w, h, pixels = decode_frame(cur, icon_idx, shape_dir)
        w, h = max(w, canvas_w), max(h, canvas_h)
        svg_name = f"frame{icon_idx:03d}.svg"
        write_svg(shape_dir / svg_name, w, h, pixels)
        rendered[icon_idx] = (svg_name, w, h, hx, hy)

    # build frame list using `seq` for ordering and `rates` for durations
    frames: list[tuple[str, int]] = []
    sizes = set()
    hotspot_x_frac = 0.0
    hotspot_y_frac = 0.0
    for step, (icon_idx, jiffies) in enumerate(zip(seq, rates)):
        svg_name, w, h, hx, hy = rendered[icon_idx]
        if w != h:
            raise RuntimeError(f"{ani_path.name}: non-square frame ({w}x{h})")
        sizes.add(w)
        # 1 jiffy = 1/60s -> ms
        duration_ms = int(round(jiffies * 1000 / 60))
        frames.append((svg_name, duration_ms))
        # use first frame's hotspot as canonical (they should all match)
        if step == 0:
            hotspot_x_frac = hx / w
            hotspot_y_frac = hy / h

    if len(sizes) != 1:
        raise RuntimeError(f"{ani_path.name}: mixed sizes {sizes}")
    size = sizes.pop()

    write_meta(shape_dir / "meta.hl", hotspot_x_frac, hotspot_y_frac,
               size, frames, overrides)
    print(f"  {ani_path.name} -> {shape}/ ({len(frames)} frames @ {size}px svg)")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, type=pathlib.Path,
                    help="directory containing the input .ani files")
    ap.add_argument("--mapping", required=True, type=pathlib.Path,
                    help="json mapping ANI filename -> {shape, overrides}")
    ap.add_argument("--out", required=True, type=pathlib.Path,
                    help="output theme source dir (will be created)")
    ap.add_argument("--name", required=True, help="theme name (manifest)")
    ap.add_argument("--description", default="", help="theme description")
    ap.add_argument("--version", default="1.0", help="theme version")
    args = ap.parse_args()

    mapping = json.loads(args.mapping.read_text())
    cursors_dir = args.out / "hyprcursors"
    cursors_dir.mkdir(parents=True, exist_ok=True)

    print(f"converting {len(mapping)} cursors -> {args.out}")
    for ani_name, spec in mapping.items():
        ani_path = args.src / ani_name
        if not ani_path.exists():
            raise SystemExit(f"missing input: {ani_path}")
        convert_one(ani_path, cursors_dir / spec["shape"],
                    spec["shape"], spec.get("overrides", []))

    manifest = args.out / "manifest.hl"
    manifest.write_text(
        f"name = {args.name}\n"
        f"description = {args.description}\n"
        f"version = {args.version}\n"
        f"cursors_directory = hyprcursors\n"
    )
    print(f"wrote {manifest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
