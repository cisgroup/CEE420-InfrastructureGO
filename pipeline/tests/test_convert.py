"""From a phone's file to an upright sRGB JPEG without metadata. No private photograph is read here, every input is made in the test."""

import io
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
from PIL import Image, ImageCms

from igo import convert, jpeg

DISPLAY_P3 = Path("/System/Library/ColorSync/Profiles/Display P3.icc")


def sensor_frame(width=64, height=48):
    """A frame as a sensor stores it, landscape, with a red top left corner and a blue top right corner."""
    a = np.full((height, width, 3), 128, np.uint8)
    a[:12, :16] = (255, 0, 0)
    a[:12, -16:] = (0, 0, 255)
    return Image.fromarray(a)


def phone_exif(orientation=6, offset="-04:00", with_gps=True):
    exif = Image.Exif()
    exif[0x0112] = orientation
    exif[0x010F] = "Apple"
    exif[0x0110] = "iPhone 14 Pro"
    sub = {0x9003: "2026:10:10 17:09:18", 0x9291: "125"}
    if offset:
        sub[0x9011] = offset
    exif[0x8769] = sub
    if with_gps:
        exif[0x8825] = {1: "N", 2: (40.0, 21.0, 24.45), 3: "W", 4: (74.0, 40.0, 21.63), 5: 0, 6: 56.4, 12: "K", 13: 1.5375,
                        16: "T", 17: 193.407, 29: "2026:10:10", 7: (21.0, 9.0, 16.0), 31: 3.1549}
    return exif.tobytes()


def write_heic(path, **options):
    sensor_frame().save(path, format="HEIF", quality=95, **options)
    return path


def is_colour(pixel, colour, slack=40):
    return all(abs(int(a) - int(b)) <= slack for a, b in zip(pixel, colour))


def test_a_rotated_heic_comes_out_upright_and_clean(tmp_path):
    source = write_heic(tmp_path / "IMG_0001.HEIC", exif=phone_exif(orientation=6))
    target = tmp_path / "out" / "p00001.jpg"
    row = convert.convert_file(source, target)
    assert (row["width"], row["height"]) == (48, 64), "the sensor's 64 by 48 frame stands upright as 48 by 64"
    assert row["exif_orientation_raw"] == 6 and row["transposed"] is False, "the HEIC reader had already turned the pixels"
    pixels = np.asarray(Image.open(target))
    assert is_colour(pixels[4, -5], (255, 0, 0)), "the sensor's top left corner is the upright picture's top right"
    assert is_colour(pixels[-5, -5], (0, 0, 255)), "the sensor's top right corner is the upright picture's bottom right"
    assert is_colour(pixels[4, 4], (128, 128, 128)) and is_colour(pixels[-5, 4], (128, 128, 128))
    assert jpeg.problems(target) == []


def test_a_jpeg_with_an_orientation_tag_is_turned_here(tmp_path):
    """The other reader. A JPEG keeps its pixels as the sensor stored them, so the turning is ours to do, once."""
    source = tmp_path / "IMG_0002.JPG"
    sensor_frame().save(source, "JPEG", quality=95, exif=phone_exif(orientation=6))
    with Image.open(source) as stored:
        assert stored.size == (64, 48)
    row = convert.convert_file(source, tmp_path / "p00002.jpg")
    assert (row["width"], row["height"]) == (48, 64)
    assert row["exif_orientation_raw"] == 6 and row["transposed"] is True
    pixels = np.asarray(Image.open(tmp_path / "p00002.jpg"))
    assert is_colour(pixels[4, -5], (255, 0, 0)) and is_colour(pixels[-5, -5], (0, 0, 255))
    assert jpeg.problems(tmp_path / "p00002.jpg") == []


def test_an_upright_file_is_left_as_it_is(tmp_path):
    source = tmp_path / "IMG_0003.JPG"
    sensor_frame().save(source, "JPEG", quality=95, exif=phone_exif(orientation=1))
    row = convert.convert_file(source, tmp_path / "p00003.jpg")
    assert (row["width"], row["height"]) == (64, 48) and row["transposed"] is False and row["exif_orientation_raw"] == 1
    pixels = np.asarray(Image.open(tmp_path / "p00003.jpg"))
    assert is_colour(pixels[4, 4], (255, 0, 0)) and is_colour(pixels[4, -5], (0, 0, 255))


def test_the_facts_of_a_capture_are_read(tmp_path):
    source = write_heic(tmp_path / "IMG_0004.HEIC", exif=phone_exif())
    row = convert.convert_file(source, tmp_path / "p00004.jpg")
    assert row["captured_at"] == "2026-10-10T17:09:18.125-04:00"
    assert row["lat"] == pytest.approx(40.356792, abs=1e-6) and row["lon"] == pytest.approx(-74.672675, abs=1e-6)
    assert row["h_error_m"] == 3.2 and row["heading"] == 193.4 and row["altitude_m"] == 56.4
    assert row["speed_mps"] == pytest.approx(1.5375 / 3.6, abs=0.01), "the phone writes kilometres an hour"
    assert row["device_family"] == "iphone"


def test_a_file_without_a_position_or_an_offset_says_so(tmp_path):
    source = tmp_path / "IMG_0005.JPG"
    sensor_frame().save(source, "JPEG", exif=phone_exif(orientation=1, offset=None, with_gps=False))
    row = convert.convert_file(source, tmp_path / "p00005.jpg")
    assert row["lat"] is None and row["lon"] is None and row["heading"] is None and row["h_error_m"] is None
    assert row["captured_at"] is None, "a local time without its offset is not an instant, so it is not used"
    bare = tmp_path / "IMG_0006.JPG"
    sensor_frame().save(bare, "JPEG")
    row = convert.convert_file(bare, tmp_path / "p00006.jpg")
    assert row["device_family"] == "other" and row["exif_orientation_raw"] == 1


def test_no_metadata_reaches_the_converted_file(tmp_path):
    """The file going in carries a position, a camera, a comment and a profile. The file coming out carries none."""
    source = tmp_path / "IMG_0007.JPG"
    srgb = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    sensor_frame().save(source, "JPEG", exif=phone_exif(orientation=1), icc_profile=srgb, comment=b"Pardoe Road")
    assert jpeg.problems(source), "the input must be unclean for this test to mean anything"
    convert.convert_file(source, tmp_path / "p00007.jpg")
    assert jpeg.problems(tmp_path / "p00007.jpg") == []
    data = (tmp_path / "p00007.jpg").read_bytes()
    assert b"Apple" not in data and b"Pardoe" not in data and b"Exif" not in data


@pytest.mark.skipif(not DISPLAY_P3.exists(), reason="the Display P3 profile ships with macOS and is not on this machine")
def test_display_p3_becomes_srgb(tmp_path):
    """A phone stores Display P3. The same numbers mean a more saturated colour there, so they must change, and grey must not."""
    def linear(v):
        v = np.asarray(v, dtype=float) / 255
        return np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)

    def encoded(v):
        v = np.clip(v, 0, 1)
        return np.round(255 * np.where(v <= 0.0031308, 12.92 * v, 1.055 * v ** (1 / 2.4) - 0.055))

    p3_to_xyz = np.array([[0.48657095, 0.26566769, 0.19821729], [0.22897456, 0.69173852, 0.07928691], [0.0, 0.04511338, 1.04394437]])
    srgb_to_xyz = np.array([[0.41239080, 0.35758434, 0.18048079], [0.21263901, 0.71516868, 0.07219232], [0.01933082, 0.11919478, 0.95053215]])
    colours = [(128, 128, 128), (200, 100, 100), (90, 160, 110), (60, 80, 180)]
    a = np.zeros((8, 8 * len(colours), 3), np.uint8)
    for k, c in enumerate(colours):
        a[:, 8 * k:8 * k + 8] = c
    source = tmp_path / "p3.png"
    Image.fromarray(a).save(source, "PNG", icc_profile=DISPLAY_P3.read_bytes())
    with Image.open(source) as image:
        out, _, _ = convert.upright_srgb(image)
    got = np.asarray(out)
    for k, c in enumerate(colours):
        expected = encoded(np.linalg.solve(srgb_to_xyz, p3_to_xyz @ linear(c)))
        assert np.abs(got[4, 8 * k + 4].astype(float) - expected).max() <= 2, f"{c} in Display P3 should be {expected} in sRGB"
    assert tuple(got[4, 4]) == (128, 128, 128)
    assert got[4, 12, 0] > 200 and got[4, 12, 1] < 100, "the red of Display P3 is a stronger red in sRGB numbers"
    assert out.info == {}, "the new image carries no profile and no other baggage"


def test_a_picture_without_a_profile_keeps_its_numbers(tmp_path):
    with Image.open(io.BytesIO(_png(sensor_frame()))) as image:
        out, raw, turned = convert.upright_srgb(image)
    assert np.array_equal(np.asarray(out), np.asarray(sensor_frame())) and raw == 1 and turned is False


def _png(image):
    buffer = io.BytesIO()
    image.save(buffer, "PNG")
    return buffer.getvalue()


def make_originals(folder):
    """Three originals on two days, written out of order so that the ids must follow the time and not the name."""
    (folder / "2026-10-17").mkdir(parents=True)
    (folder / "2026-10-10").mkdir(parents=True)
    times = {"2026-10-17/IMG_0002.HEIC": "2026:10:17 10:00:00", "2026-10-10/IMG_0009.HEIC": "2026:10:10 17:00:00", "2026-10-10/IMG_0001.HEIC": "2026:10:10 17:05:00"}
    for k, (name, taken) in enumerate(times.items()):
        exif = Image.Exif()
        exif[0x0112] = 6
        exif[0x8769] = {0x9003: taken, 0x9011: "-04:00"}
        exif[0x8825] = {1: "N", 2: (40.0, 21.0, 24.0 + k), 3: "W", 4: (74.0, 40.0, 21.0)}
        frame = np.asarray(sensor_frame()).copy()
        frame[20:28, 20:28] = (10 * k, 200, 50)
        Image.fromarray(frame).save(folder / name, format="HEIF", quality=95, exif=exif.tobytes())


def test_ids_follow_the_time_of_capture_and_are_kept_for_good(tmp_path):
    originals, converted, captures = tmp_path / "originals", tmp_path / "converted", tmp_path / "captures.csv"
    make_originals(originals)
    table, new = convert.run(originals, converted, captures)
    assert new == 3 and table["photo_id"].tolist() == ["p00001", "p00002", "p00003"]
    assert table["original"].tolist() == ["2026-10-10/IMG_0009.HEIC", "2026-10-10/IMG_0001.HEIC", "2026-10-17/IMG_0002.HEIC"]
    assert sorted(p.name for p in converted.iterdir()) == ["p00001.jpg", "p00002.jpg", "p00003.jpg"]
    assert all(jpeg.problems(p) == [] for p in converted.iterdir())

    again, new = convert.run(originals, converted, captures)
    assert new == 0 and again["photo_id"].tolist() == table["photo_id"].tolist(), "a second run changes nothing"

    exif = Image.Exif()
    exif[0x8769] = {0x9003: "2026:10:03 09:00:00", 0x9011: "-04:00"}
    late = np.asarray(sensor_frame()).copy()
    late[30:40, 30:40] = (250, 250, 0)
    (originals / "2026-10-03").mkdir()
    Image.fromarray(late).save(originals / "2026-10-03" / "IMG_0100.HEIC", format="HEIF", quality=95, exif=exif.tobytes())
    (originals / "2026-10-10" / "IMG_0009.HEIC").unlink()
    grown, new = convert.run(originals, converted, captures)
    assert new == 1
    assert grown["photo_id"].tolist() == ["p00001", "p00002", "p00003", "p00004"], "an earlier photograph that arrives later still gets the next id"
    assert grown["original"].iloc[3] == "2026-10-03/IMG_0100.HEIC"
    assert grown["original"].iloc[0] == "2026-10-10/IMG_0009.HEIC", "the row of a removed original stays, so its id is never given again"
    on_disk = pd.read_csv(captures, dtype=str)
    assert on_disk["photo_id"].tolist() == grown["photo_id"].tolist() and list(on_disk.columns) == convert.COLUMNS


def test_the_same_bytes_under_another_name_are_one_photograph(tmp_path):
    originals, converted, captures = tmp_path / "originals", tmp_path / "converted", tmp_path / "captures.csv"
    make_originals(originals)
    convert.run(originals, converted, captures)
    copy = originals / "2026-10-17" / "IMG_0002 copy.HEIC"
    copy.write_bytes((originals / "2026-10-17" / "IMG_0002.HEIC").read_bytes())
    table, new = convert.run(originals, converted, captures)
    assert new == 0 and len(table) == 3


def test_a_missing_converted_file_is_written_again(tmp_path):
    originals, converted, captures = tmp_path / "originals", tmp_path / "converted", tmp_path / "captures.csv"
    make_originals(originals)
    convert.run(originals, converted, captures)
    (converted / "p00002.jpg").unlink()
    convert.run(originals, converted, captures)
    assert (converted / "p00002.jpg").exists()
