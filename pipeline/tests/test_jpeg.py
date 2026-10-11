"""The walk over a JPEG's segments, the proof that a published photograph carries pixels and nothing else."""

import io

import numpy as np
import pytest
from PIL import Image

from igo import jpeg


def picture(width=64, height=48):
    rng = np.random.default_rng(3)
    return Image.fromarray(rng.integers(0, 255, (height, width, 3), dtype=np.uint8))


def saved(tmp_path, name="p.jpg", **options):
    path = tmp_path / name
    picture().save(path, "JPEG", **options)
    return path


def test_a_plainly_saved_jpeg_is_clean(tmp_path):
    path = saved(tmp_path, quality=90)
    names = [name for name, _ in jpeg.segments(path.read_bytes())]
    assert names[0] == "SOI" and names[-1] == "EOI" and "SOS" in names
    assert set(names) <= jpeg.ALLOWED
    assert jpeg.problems(path) == []
    assert jpeg.verify_clean(path) == path


def test_a_progressive_jpeg_with_restart_markers_is_clean(tmp_path):
    path = saved(tmp_path, quality=90, progressive=True, restart_marker_rows=1)
    names = [name for name, _ in jpeg.segments(path.read_bytes())]
    assert "SOF2" in names and "DRI" in names and names.count("SOS") > 1
    assert jpeg.problems(path) == []


def exif_bytes():
    exif = Image.Exif()
    exif[0x010F] = "Apple"
    exif[0x8825] = {1: "N", 2: (40.0, 21.0, 24.45), 3: "W", 4: (74.0, 40.0, 21.63)}
    return exif.tobytes()


@pytest.mark.parametrize("options, expected", [
    (dict(exif=exif_bytes()), "APP1"),
    (dict(icc_profile=b"\x00" * 200), "APP2"),
    (dict(comment=b"taken on Pardoe Road"), "COM"),
    (dict(xmp=b"<x:xmpmeta xmlns:x='adobe:ns:meta/'></x:xmpmeta>"), "APP1"),
])
def test_each_kind_of_baggage_is_found(tmp_path, options, expected):
    """The negative controls. A file saved with a position, a profile, a comment or XMP must be refused for it."""
    path = saved(tmp_path, **options)
    found = " ".join(jpeg.problems(path))
    assert expected in found
    with pytest.raises(ValueError, match="is not clean"):
        jpeg.verify_clean(path)


def test_bytes_after_the_end_are_found(tmp_path):
    path = saved(tmp_path)
    path.write_bytes(path.read_bytes() + b"a second picture could hide here")
    assert "TRAILING" in " ".join(jpeg.problems(path))


def test_an_adobe_segment_is_found(tmp_path):
    clean = saved(tmp_path).read_bytes()
    adobe = b"\xff\xee" + (14).to_bytes(2, "big") + b"Adobe\x00d\x00\x00\x00\x00\x01"
    path = tmp_path / "adobe.jpg"
    path.write_bytes(clean[:2] + adobe + clean[2:])
    assert "APP14" in " ".join(jpeg.problems(path))


def test_an_app0_that_is_not_jfif_is_found(tmp_path):
    clean = saved(tmp_path).read_bytes()
    assert clean[2:4] == b"\xff\xe0" and clean[6:11] == b"JFIF\x00"
    path = tmp_path / "jfxx.jpg"
    path.write_bytes(clean[:6] + b"NOTES" + clean[11:])
    assert "not the plain JFIF header" in " ".join(jpeg.problems(path))


def test_a_file_that_is_not_a_jpeg_is_refused(tmp_path):
    buffer = io.BytesIO()
    picture().save(buffer, "PNG")
    with pytest.raises(ValueError, match="not a JPEG"):
        jpeg.segments(buffer.getvalue())


def test_a_truncated_file_is_refused(tmp_path):
    data = saved(tmp_path).read_bytes()
    with pytest.raises(ValueError):
        jpeg.segments(data[:len(data) // 2])
    path = tmp_path / "half.jpg"
    path.write_bytes(data[:len(data) // 2])
    assert "cannot be walked" in " ".join(jpeg.problems(path))
