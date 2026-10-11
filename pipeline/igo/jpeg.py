"""What a JPEG file carries besides its picture.

A photograph leaves the private folder only as a JPEG that holds pixels and nothing else. Whether that is so cannot
be seen by opening the file, so this module walks the file's segments and names every one. A clean file has a start,
the tables and the scan a decoder needs, and an end. A position, a time, a camera, a colour profile or a comment
each need a segment of their own, and any such segment makes the file unclean.
"""

from pathlib import Path

from PIL import Image

NAMES = {0xD8: "SOI", 0xD9: "EOI", 0xDA: "SOS", 0xDB: "DQT", 0xC4: "DHT", 0xDD: "DRI", 0xFE: "COM",
         0xC0: "SOF0", 0xC1: "SOF1", 0xC2: "SOF2", 0xC3: "SOF3", 0xCC: "DAC"}
NAMES.update({0xE0 + k: f"APP{k}" for k in range(16)})
NAMES.update({0xD0 + k: f"RST{k}" for k in range(8)})
ALLOWED = {"SOI", "APP0", "DQT", "SOF0", "SOF2", "DHT", "DRI", "SOS", "EOI"}


def segments(data):
    """The segments of a JPEG as a list of names with the first bytes of each payload, in the order of the file.

    The restart markers inside a scan are part of the picture and are not listed. Bytes after the end marker are
    listed as TRAILING, because a second picture or anything else can hide there.
    """
    if data[:2] != b"\xff\xd8":
        raise ValueError("not a JPEG file, the first two bytes are not its start marker")
    out = [("SOI", b"")]
    i = 2
    n = len(data)
    while i < n:
        if data[i] != 0xFF:
            raise ValueError(f"byte {i} should begin a marker and does not")
        while i < n and data[i] == 0xFF:
            i += 1                                   # fill bytes before a marker are allowed
        if i >= n:
            break
        code = data[i]
        i += 1
        name = NAMES.get(code, f"0x{code:02X}")
        if name == "EOI":
            out.append(("EOI", b""))
            if i < n:
                out.append(("TRAILING", data[i:i + 16]))
            return out
        length = int.from_bytes(data[i:i + 2], "big")
        if length < 2 or i + length > n:
            raise ValueError(f"the segment {name} at byte {i} has an impossible length")
        out.append((name, data[i + 2:i + 2 + min(length - 2, 16)]))
        i += length
        if name == "SOS":
            while i < n - 1:                         # the scan runs to the next marker that is not stuffing or a restart
                if data[i] == 0xFF and data[i + 1] != 0x00 and not 0xD0 <= data[i + 1] <= 0xD7:
                    break
                i += 1
            else:
                raise ValueError("the scan runs to the end of the file without an end marker")
    raise ValueError("the file ends without an end marker")


def problems(path):
    """Every reason a JPEG file is not clean, as sentences. An empty list means it holds pixels and nothing else."""
    data = Path(path).read_bytes()
    try:
        found = segments(data)
    except ValueError as error:
        return [f"The file cannot be walked, {error}."]
    out = []
    for name, head in found:
        if name == "APP0" and not head.startswith(b"JFIF\x00"):
            out.append("An APP0 segment that is not the plain JFIF header.")
        elif name not in ALLOWED:
            what = {"APP1": "EXIF or XMP", "APP2": "a colour profile or a second picture", "APP13": "IPTC or Photoshop data",
                    "APP14": "Adobe data", "COM": "a comment", "TRAILING": "bytes after the end of the picture"}.get(name, "something a clean file does not need")
            out.append(f"A {name} segment, which holds {what}.")
    names = [name for name, _ in found]
    if names.count("EOI") != 1 or names.count("SOI") != 1:
        out.append("More than one picture in the file.")
    with Image.open(path) as image:
        if len(image.getexif()):
            out.append("The decoder still reads EXIF tags.")
        for key in ("icc_profile", "xmp", "comment", "exif", "photoshop", "mp"):
            if image.info.get(key):
                out.append(f"The decoder still reads {key}.")
    return out


def verify_clean(path):
    """Raise unless the JPEG file holds pixels and nothing else."""
    found = problems(path)
    if found:
        raise ValueError(f"{Path(path).name} is not clean. " + " ".join(found))
    return path
