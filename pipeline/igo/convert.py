"""From the phone's files to upright sRGB JPEGs without metadata, and the facts of each capture.

Everything this step reads and writes lies under data/private, which git ignores. It opens every original, takes
the position, the time, the accuracy and the heading out of the metadata into captures.csv, and writes the picture
alone as a JPEG at full resolution for labelling and review. A photograph gets its id here, p and five digits in
the order of capture, and keeps it for good. An id is never given twice, also when an original is later removed.

    uv run python -m igo.convert            converts what is new and prints the captures
    uv run python -m igo.convert --check    compares the orientation of every converted picture with ImageMagick's
"""

import argparse
import hashlib
import io
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
import pillow_heif
from PIL import ExifTags, Image, ImageCms, ImageOps

from igo import ROOT, jpeg

pillow_heif.register_heif_opener()

PRIVATE = ROOT / "data" / "private"
ORIGINALS = PRIVATE / "originals"
CONVERTED = PRIVATE / "converted"
CAPTURES = PRIVATE / "captures.csv"
SHEETS = PRIVATE / "sheets"
SUFFIXES = {".heic", ".heif", ".jpg", ".jpeg"}
QUALITY = 92
COLUMNS = ["photo_id", "original", "sha256", "captured_at", "lat", "lon", "h_error_m", "heading", "speed_mps", "altitude_m",
           "exif_orientation_raw", "transposed", "width", "height", "device_family"]
SPEED_TO_MPS = {"K": 1 / 3.6, "M": 0.44704, "N": 0.514444}


def degrees(parts, reference):
    """Degrees, minutes and seconds with their hemisphere letter as signed decimal degrees."""
    d, m, s = (float(v) for v in parts)
    value = d + m / 60 + s / 3600
    return -value if reference in ("S", "W") else value


def facts(image):
    """What the metadata of an opened photograph says about the capture. A fact the file does not hold is None."""
    exif = image.getexif()
    gps = {ExifTags.GPSTAGS.get(k, k): v for k, v in exif.get_ifd(ExifTags.IFD.GPSInfo).items()}
    sub = {ExifTags.TAGS.get(k, k): v for k, v in exif.get_ifd(ExifTags.IFD.Exif).items()}
    out = dict(captured_at=None, lat=None, lon=None, h_error_m=None, heading=None, speed_mps=None, altitude_m=None)
    if "GPSLatitude" in gps and "GPSLongitude" in gps:
        out["lat"] = round(degrees(gps["GPSLatitude"], gps.get("GPSLatitudeRef", "N")), 7)
        out["lon"] = round(degrees(gps["GPSLongitude"], gps.get("GPSLongitudeRef", "E")), 7)
    if "GPSHPositioningError" in gps:
        out["h_error_m"] = round(float(gps["GPSHPositioningError"]), 1)
    if "GPSImgDirection" in gps and gps.get("GPSImgDirectionRef", "T") == "T":
        out["heading"] = round(float(gps["GPSImgDirection"]), 1)
    if "GPSSpeed" in gps:
        out["speed_mps"] = round(float(gps["GPSSpeed"]) * SPEED_TO_MPS.get(gps.get("GPSSpeedRef", "K"), 1 / 3.6), 2)
    if "GPSAltitude" in gps:
        out["altitude_m"] = round(float(gps["GPSAltitude"]) * (-1 if gps.get("GPSAltitudeRef") in (1, b"\x01") else 1), 1)
    taken = sub.get("DateTimeOriginal")
    if taken and sub.get("OffsetTimeOriginal"):
        moment = datetime.strptime(taken, "%Y:%m:%d %H:%M:%S").isoformat()
        fraction = str(sub.get("SubsecTimeOriginal") or "").strip()
        out["captured_at"] = moment + (f".{fraction}" if fraction.isdigit() else "") + sub["OffsetTimeOriginal"]
    elif "GPSDateStamp" in gps and "GPSTimeStamp" in gps:                 # no local offset in the file, so the satellite's UTC time
        h, m, s = (float(v) for v in gps["GPSTimeStamp"])
        day = datetime.strptime(gps["GPSDateStamp"], "%Y:%m:%d")
        out["captured_at"] = day.replace(hour=int(h), minute=int(m), second=int(s), tzinfo=timezone.utc).isoformat()
    make, model = str(exif.get(0x010F, "")), str(exif.get(0x0110, ""))
    out["device_family"] = "iphone" if make.startswith("Apple") and model.startswith("iPhone") else "other"
    return out


def upright_srgb(image):
    """The picture alone, upright and in sRGB, as a new image that carries no metadata at all.

    The HEIC reader already turns the pixels the way the file asks and then sets the orientation tag to normal,
    keeping the tag's first value aside. Any other reader leaves the turning to us. So the picture is turned here
    exactly when the tag still asks for it, which is right in both cases and never turns twice. Returns the image,
    the orientation the file first stated, and whether this function did the turning.
    """
    tag = int(image.getexif().get(0x0112, 1) or 1)
    raw = int(image.info.get("original_orientation") or tag)
    turned = tag != 1
    if turned:
        image = ImageOps.exif_transpose(image)
    profile = image.info.get("icc_profile")
    image = image.convert("RGB") if image.mode != "RGB" else image
    if profile:
        source = ImageCms.ImageCmsProfile(io.BytesIO(profile))
        image = ImageCms.profileToProfile(image, source, ImageCms.createProfile("sRGB"), outputMode="RGB")
    return Image.fromarray(np.asarray(image)), raw, turned


def convert_file(source, target):
    """Convert one original and return the row of facts about it, without the id and the file's own name."""
    with Image.open(source) as image:
        row = facts(image)
        picture, raw, turned = upright_srgb(image)
    target.parent.mkdir(parents=True, exist_ok=True)
    picture.save(target, "JPEG", quality=QUALITY)
    jpeg.verify_clean(target)
    row.update(exif_orientation_raw=raw, transposed=turned, width=picture.width, height=picture.height)
    return row


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def known_captures(path=None):
    path = path or CAPTURES
    if not path.exists():
        return pd.DataFrame(columns=COLUMNS)
    return pd.read_csv(path, dtype={"photo_id": str, "original": str, "sha256": str, "captured_at": str, "device_family": str})


def capture_order(rows):
    """New captures in the order they were taken, the ones without a time last, by file name within the same time."""
    return sorted(rows, key=lambda r: (r["captured_at"] is None, _instant(r["captured_at"]), r["original"]))


def _instant(text):
    return datetime.fromisoformat(text) if text else datetime.max.replace(tzinfo=timezone.utc)


def run(originals=None, converted=None, captures=None, force=False):
    """Convert every original that is new and return the whole table of captures, old rows first and unchanged."""
    originals, converted, captures = originals or ORIGINALS, converted or CONVERTED, captures or CAPTURES
    known = known_captures(captures)
    seen = dict(zip(known["sha256"], known["photo_id"]))
    files = sorted(p for p in originals.rglob("*") if p.suffix.lower() in SUFFIXES and not p.name.startswith("."))
    fresh = []
    for path in files:
        sha = digest(path)
        if sha in seen:
            target = converted / f"{seen[sha]}.jpg"
            if force or not target.exists():
                convert_file(path, target)
            continue
        with Image.open(path) as image:
            row = facts(image)
        row.update(original=str(path.relative_to(originals)), sha256=sha, source=path)
        fresh.append(row)
    last = max((int(i[1:]) for i in known["photo_id"]), default=0)
    rows = []
    for k, row in enumerate(capture_order(fresh), start=last + 1):
        photo_id = f"p{k:05d}"
        done = convert_file(row.pop("source"), converted / f"{photo_id}.jpg")
        rows.append(dict(done, photo_id=photo_id, original=row["original"], sha256=row["sha256"]))
    table = pd.concat([known, pd.DataFrame(rows, columns=COLUMNS)], ignore_index=True) if rows else known
    captures.parent.mkdir(parents=True, exist_ok=True)
    table.to_csv(captures, index=False, lineterminator="\n")
    return table, len(rows)


def orientation_check(converted=None, originals=None, captures=None, sheet=None):
    """Compare every converted picture with what ImageMagick makes of the same original.

    The two are shrunk to small grey pictures and subtracted. A picture turned the wrong way differs from the
    reference by far more than two readers of the same file ever do, so one number per photograph settles it, and
    a sheet of both renderings side by side is written for a look. Returns one row per photograph.
    """
    converted, originals, captures = converted or CONVERTED, originals or ORIGINALS, captures or CAPTURES
    magick = shutil.which("magick")
    if not magick:
        raise SystemExit("ImageMagick is not installed, so there is nothing to compare with. The command is magick.")
    table = known_captures(captures)
    rows, pairs = [], []
    for r in table.itertuples(index=False):
        source, ours_path = originals / r.original, converted / f"{r.photo_id}.jpg"
        if not source.exists() or not ours_path.exists():
            continue
        png = subprocess.run([magick, str(source), "-auto-orient", "-strip", "-resize", "256x256", "png:-"], check=True, capture_output=True).stdout
        reference = Image.open(io.BytesIO(png)).convert("RGB")
        ours = Image.open(ours_path)
        same_shape = (ours.width > ours.height) == (reference.width > reference.height)
        small = ours.resize(reference.size, Image.Resampling.LANCZOS)
        gap = float(np.abs(np.asarray(small.convert("L"), dtype=float) - np.asarray(reference.convert("L"), dtype=float)).mean())
        rows.append(dict(photo_id=r.photo_id, original=r.original, size=f"{ours.width} by {ours.height}", raw_orientation=r.exif_orientation_raw,
                         turned_here=r.transposed, same_shape=same_shape, mean_grey_difference=round(gap, 2), agrees=same_shape and gap < 12))
        pairs.append((r.photo_id, small, reference))
    if pairs:
        sheet = sheet or SHEETS / "convert_check.jpg"
        sheet.parent.mkdir(parents=True, exist_ok=True)
        cell_w = max(p[1].width for p in pairs)
        cell_h = max(p[1].height for p in pairs)
        canvas = Image.new("RGB", (len(pairs) * (cell_w + 8) + 8, 2 * (cell_h + 8) + 8), "white")
        for k, (_, ours, reference) in enumerate(pairs):
            canvas.paste(ours, (8 + k * (cell_w + 8), 8))
            canvas.paste(reference, (8 + k * (cell_w + 8), 16 + cell_h))
        canvas.save(sheet, "JPEG", quality=85)
    return rows


def main(argv=None):
    parser = argparse.ArgumentParser(description="From the phone's files to upright sRGB JPEGs without metadata.")
    parser.add_argument("--check", action="store_true", help="compare the orientation of every converted picture with ImageMagick's rendering")
    parser.add_argument("--force", action="store_true", help="write every converted picture again")
    args = parser.parse_args(argv)
    if args.check:
        rows = orientation_check()
        for r in rows:
            print(f"{r['photo_id']}  {r['size']:>13}  orientation in the file {r['raw_orientation']}, turned here {r['turned_here']}, "
                  f"mean grey difference {r['mean_grey_difference']:5.2f}  {'agrees' if r['agrees'] else 'DIFFERS'}")
        print(f"{sum(r['agrees'] for r in rows)} of {len(rows)} pictures agree with ImageMagick, the sheet is {SHEETS / 'convert_check.jpg'}")
        return 0 if rows and all(r["agrees"] for r in rows) else 1
    if not ORIGINALS.exists():
        print("data/private/originals does not exist, so there is nothing to convert")
        return 1
    table, new = run(force=args.force)
    show = table[["photo_id", "original", "captured_at", "lat", "lon", "h_error_m", "heading", "speed_mps", "width", "height"]]
    print(show.to_string(index=False))
    without = int(table["lat"].isna().sum())
    print(f"{len(table)} captures, {new} of them new" + (f", {without} without a position" if without else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
