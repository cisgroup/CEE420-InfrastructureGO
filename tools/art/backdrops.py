"""Prepare the photographs that stand behind a meeting in the simulator, where there is no camera.

The photographs are Jürgen's own pictures of Princeton drains under data/private/, which git ignores, and the
copies go to app/InfrastructureGO/Resources/Local/, which git ignores as well. Nothing here is ever committed
but this script. For each picture the four corners of the grate were read off by eye, and from them the script
works out where the camera stood, so that the app can seat a keeper on the grate at its true size. The size of
the grate is an assumption that only serves this seating.

    uv run python tools/art/backdrops.py            write the copies and backdrops.json
    uv run python tools/art/backdrops.py --check    also draw the fitted grate onto each picture under build/
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps
from scipy.optimize import least_squares

ROOT = Path(__file__).resolve().parents[2]
PHOTOS = ROOT / "data" / "private" / "converted"
LOCAL = ROOT / "app" / "InfrastructureGO" / "Resources" / "Local"
CANVAS = (1080, 2400)        # taller than any phone's screen, so the app only ever cuts from top and bottom
KEEP_WIDTH = 0.8             # the share of the picture's width that is kept, cut evenly from both sides
FOV_VERTICAL_DEG = 67.4      # a phone's main camera held upright, 26 mm in the terms of a small picture camera
GRATE_LENGTH_M = 1.2         # along the kerb, assumed
GRATE_DEPTH_M = 0.6          # from the kerb into the street, assumed

# The corners of each grate as fractions of the picture's width and height, read off a gridded copy by eye:
# far left, far right, near right, near left, where far is the edge at the kerb.
CORNERS = {
    "p00008": [(0.200, 0.500), (0.800, 0.500), (0.845, 0.690), (0.105, 0.680)],
    "p00006": [(0.300, 0.400), (0.800, 0.600), (0.655, 0.800), (0.175, 0.565)],
}


def project(point, pitch, height, aspect):
    """Where a point on the ground appears in the picture. The camera stands at the origin of the ground, at its
    height, looks along minus z and is tilted down by its pitch. The answer is in fractions of width and height."""
    x, z = point
    depth = height * math.sin(pitch) - z * math.cos(pitch)
    up = -height * math.cos(pitch) - z * math.sin(pitch)
    focal = 0.5 / math.tan(math.radians(FOV_VERTICAL_DEG) / 2)
    return 0.5 + x / depth * focal / aspect, 0.5 - up / depth * focal


def corners_on_ground(cx, cz, yaw):
    along = np.array([math.cos(yaw), math.sin(yaw)])
    toward = np.array([-math.sin(yaw), math.cos(yaw)])
    centre = np.array([cx, cz])
    half_l, half_d = GRATE_LENGTH_M / 2, GRATE_DEPTH_M / 2
    return [centre - along * half_l - toward * half_d, centre + along * half_l - toward * half_d,
            centre + along * half_l + toward * half_d, centre - along * half_l + toward * half_d]


def fit(corners, aspect):
    def miss(p):
        pitch, height, cx, cz, yaw = p
        out = []
        for seen, ground in zip(corners, corners_on_ground(cx, cz, yaw)):
            u, v = project(ground, pitch, height, aspect)
            out += [(u - seen[0]) * aspect, v - seen[1]]
        return out
    best = None
    for yaw0 in (0.0, 0.5, -0.5, 1.0, -1.0):
        found = least_squares(miss, [math.radians(60), 1.5, 0.0, -1.0, yaw0],
                              bounds=([0.2, 0.8, -3, -6, -math.pi / 2], [math.pi / 2, 2.2, 3, 0.5, math.pi / 2]))
        if best is None or found.cost < best.cost:
            best = found
    return best


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--check", action="store_true", help="draw the fitted grate onto each picture under build/")
    asked = parser.parse_args()
    LOCAL.mkdir(parents=True, exist_ok=True)
    entries = []
    for photo, corners in CORNERS.items():
        picture = Image.open(PHOTOS / f"{photo}.jpg").convert("RGB")
        aspect = picture.width / picture.height
        found = fit(corners, aspect)
        pitch, height, cx, cz, yaw = found.x
        worst = max(abs(m) for m in found.fun)

        # A phone's screen is much taller than a photograph. The picture keeps most of its width, and the missing
        # height is filled above and below with its own edge, mirrored, which here is lawn above and street below.
        cut = round(picture.width * (1 - KEEP_WIDTH) / 2)
        kept = picture.crop((cut, 0, picture.width - cut, picture.height))
        kept = kept.resize((CANVAS[0], round(kept.height * CANVAS[0] / kept.width)), Image.LANCZOS)
        extra = (CANVAS[1] - kept.height) // 2
        if extra < 0:
            raise SystemExit(f"{photo}: the picture is taller than the canvas, keep less of its width")
        canvas = Image.new("RGB", CANVAS)
        canvas.paste(ImageOps.flip(kept.crop((0, 0, kept.width, extra))).filter(ImageFilter.GaussianBlur(3)), (0, 0))
        canvas.paste(kept, (0, extra))
        below = ImageOps.flip(kept.crop((0, kept.height - (CANVAS[1] - extra - kept.height), kept.width, kept.height)))
        canvas.paste(below.filter(ImageFilter.GaussianBlur(3)), (0, extra + kept.height))
        Image.frombytes("RGB", canvas.size, canvas.tobytes()).save(LOCAL / f"backdrop_{photo}.jpg", quality=88)
        share = kept.height / CANVAS[1]          # how much of the canvas's height the picture itself covers
        fov = 2 * math.degrees(math.atan(math.tan(math.radians(FOV_VERTICAL_DEG) / 2) / share))

        entries.append({"id": photo, "file": f"backdrop_{photo}", "aspect": round(CANVAS[0] / CANVAS[1], 4), "fov_vertical_deg": round(fov, 2),
                        "pitch_deg": round(math.degrees(pitch), 2), "height_m": round(height, 3),
                        "grate_x_m": round(cx, 3), "grate_z_m": round(cz, 3), "grate_yaw_deg": round(math.degrees(yaw), 2),
                        "grate_length_m": GRATE_LENGTH_M, "grate_depth_m": GRATE_DEPTH_M, "worst_miss": round(worst, 4)})
        print(f"{photo}: pitch {math.degrees(pitch):.1f} degrees, camera {height:.2f} m up, grate at x {cx:.2f} z {cz:.2f}, "
              f"turned {math.degrees(yaw):.1f} degrees, worst miss {worst:.3f} of the picture's height, canvas sees {fov:.1f} degrees")
        if asked.check:
            small = picture.resize((picture.width // 4, picture.height // 4))
            draw = ImageDraw.Draw(small)
            fitted = [project(g, pitch, height, aspect) for g in corners_on_ground(cx, cz, yaw)]
            draw.polygon([(u * small.width, v * small.height) for u, v in fitted], outline=(255, 220, 0), width=5)
            draw.polygon([(u * small.width, v * small.height) for u, v in corners], outline=(0, 200, 255), width=2)
            (ROOT / "build").mkdir(exist_ok=True)
            small.save(ROOT / "build" / f"backdrop_check_{photo}.jpg", quality=80)
            canvas.resize((CANVAS[0] // 3, CANVAS[1] // 3)).save(ROOT / "build" / f"backdrop_canvas_{photo}.jpg", quality=80)
    about = ("Where the camera stood for each backdrop of the simulator, worked out by tools/art/backdrops.py from the corners of "
             "the grate. The pictures are private and stay on this Mac. The size of the grate is assumed.")
    (LOCAL / "backdrops.json").write_text(json.dumps({"about": about, "backdrops": entries}, indent=1) + "\n")


if __name__ == "__main__":
    main()
