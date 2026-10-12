"""Pick the few sounds the game plays out of the fetched packs and write them as files the app loads.

Every sound of the game is named here with the file it comes from, so that the credits can say so. The packs are
opened in art/work/, which git ignores, and each chosen sound is written as one small .caf file under the app's
Resources/Sounds with the game's own name for it, because the app's bundle is flat.

    python3 tools/art/sounds.py
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOWNLOADS = ROOT / "art" / "downloads"
WORK = ROOT / "art" / "work" / "sounds"
OUT = ROOT / "app" / "InfrastructureGO" / "Resources" / "Sounds"
TABLE = ROOT / "art" / "sounds.json"

INTERFACE = "kenney_interface_sounds/kenney_interface-sounds.zip"
IMPACT = "kenney_impact_sounds/kenney_impact-sounds.zip"
SWISHES = "swishes/swishes.zip"

# The game's name for a sound, the pack and the file inside it, and when the game plays it.
SOUNDS = [
    ("tick", INTERFACE, "tick_001.ogg", "the detector ticks"),
    ("rattle", IMPACT, "impactMetal_light_002.ogg", "the grate rattles before a keeper comes out"),
    ("pop", INTERFACE, "pluck_001.ogg", "a keeper pops out"),
    ("swish", SWISHES, "swish-3.wav", "the marker is thrown"),
    ("tap", IMPACT, "impactPlate_light_001.ogg", "the marker lands"),
    ("hop", IMPACT, "impactSoft_medium_002.ogg", "a keeper lands from a hop"),
    ("accept", INTERFACE, "confirmation_001.ogg", "a keeper accepts the marker"),
    ("refuse", INTERFACE, "back_002.ogg", "a throw missed"),
    ("slip", INTERFACE, "drop_003.ogg", "a keeper slips away"),
    ("crate", IMPACT, "impactWood_light_002.ogg", "the crate rises"),
    ("open", IMPACT, "impactWood_medium_001.ogg", "the crate opens"),
    ("part", INTERFACE, "glass_002.ogg", "a part of gear flies out"),
    ("piece", INTERFACE, "confirmation_003.ogg", "a piece of gear is finished"),
    ("seal", IMPACT, "impactPunch_medium_001.ogg", "a seal is stamped"),
    ("page", INTERFACE, "scroll_003.ogg", "a page of the journal turns"),
    ("hello", INTERFACE, "glass_005.ogg", "a keeper the player knows"),
    ("level", INTERFACE, "confirmation_004.ogg", "a level is reached"),
    ("select", INTERFACE, "select_002.ogg", "a button is pressed"),
    ("uncover", INTERFACE, "drop_001.ogg", "a drain appears from under the veil"),
]


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    table = []
    for name, pack, inside, when in SOUNDS:
        archive = DOWNLOADS / pack
        folder = WORK / Path(pack).parent.name
        folder.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive) as opened:
            member = next((m for m in opened.namelist() if m.rsplit("/", 1)[-1] == inside and "__MACOSX" not in m), None)
            if member is None:
                raise SystemExit(f"{pack} has no file named {inside}")
            source = folder / inside
            source.write_bytes(opened.read(member))
        target = OUT / f"{name}.caf"
        done = subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16@44100", "-c", "1", str(source), str(target)], capture_output=True, text=True)
        if done.returncode != 0:
            ffmpeg = shutil.which("ffmpeg")
            if not ffmpeg:
                raise SystemExit(f"{inside}: afconvert failed and ffmpeg is not installed. {done.stderr.strip()}")
            subprocess.run([ffmpeg, "-loglevel", "error", "-y", "-i", str(source), "-ac", "1", "-ar", "44100", "-c:a", "pcm_s16le", str(target)], check=True)
        table.append({"name": name, "file": f"{name}.caf", "from": inside, "pack": pack.split("/")[0], "when": when, "bytes": target.stat().st_size})
        print(f"{name:8s} {target.stat().st_size:7d} bytes  from {inside}")
    about = "The sounds of the game and the file each was made from, written by tools/art/sounds.py. The packs and their licences are in art/sources.json."
    TABLE.write_text(json.dumps({"about": about, "sounds": table}, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
