"""Make every keeper of the game from its model in the pack, and write the credits.

For each keeper of art/keepers.json this runs Blender without a window on tools/art/export_clips.py, which writes
one USDZ per movement and two pictures. The files go to the app's Resources/Models under the keeper's name, and
they are committed, so that the app builds on a Mac without Blender. No output may carry a path of this Mac. The
credits are written from art/sources.json, the record of where every fetched file came from.

    python3 tools/art/build.py                 every keeper
    python3 tools/art/build.py frog dino       only the ones named
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BLENDER = Path("/Applications/Blender.app/Contents/MacOS/Blender")
RECIPE = ROOT / "art" / "keepers.json"
SOURCES = ROOT / "art" / "sources.json"
SOUNDS = ROOT / "art" / "sounds.json"
DOWNLOADS = ROOT / "art" / "downloads"
WORK = ROOT / "art" / "work" / "keepers"
MODELS = ROOT / "app" / "InfrastructureGO" / "Resources" / "Models"
PICTURE_PX = 512


def build(keeper: dict) -> list[Path]:
    work = WORK / keeper["id"]
    shutil.rmtree(work, ignore_errors=True)
    command = [str(BLENDER), "--background", "--factory-startup", "--python", str(ROOT / "tools" / "art" / "export_clips.py"), "--",
               "--source", str(DOWNLOADS / keeper["source"]), "--keeper", keeper["id"], "--out", str(work), "--pictures", str(work / "pictures"),
               "--clips", ",".join(f"{name}={clip}" for name, clip in keeper["clips"].items()),
               "--paints", ",".join(f"{name}={colour}" for name, colour in keeper["paints"].items()),
               "--portrait", keeper["portrait"], "--pose", keeper["pose"]]
    done = subprocess.run(command, capture_output=True, text=True)
    if done.returncode != 0 or "Traceback" in done.stdout + done.stderr:
        raise SystemExit(f"{keeper['id']}: Blender failed\n{done.stdout[-1500:]}\n{done.stderr[-1500:]}")
    for line in done.stdout.splitlines():
        if line.startswith("TURNED"):
            print("  ", line.lower())
    made = []
    for old in list(MODELS.glob(f"{keeper['id']}_*.usdz")) + list(MODELS.glob(f"{keeper['id']}_*.png")):
        old.unlink()
    for name in keeper["clips"]:
        source = work / f"{keeper['id']}_{name}.usdz"
        if not source.exists():
            raise SystemExit(f"{keeper['id']}: Blender wrote no file for the movement {name}")
        text = subprocess.run(["usdcat", str(source)], capture_output=True, text=True).stdout
        if "/Users/" in text or "def SkelAnimation" not in text:
            raise SystemExit(f"{source.name} carries a path of this Mac or has no movement in it")
        shutil.copy2(source, MODELS / source.name)
        made.append(MODELS / source.name)
    for word in ("portrait", "pose"):
        source = work / "pictures" / f"{keeper['id']}_{word}.png"
        target = MODELS / source.name
        subprocess.run(["sips", "-Z", str(PICTURE_PX), str(source), "--out", str(target)], capture_output=True, check=True)
        made.append(target)
    return made


def credits(recipe: dict) -> str:
    sources = {f["path"]: f for f in json.loads(SOURCES.read_text())["files"]}
    lines = ["# Credits", "",
             "Written by `tools/art/build.py` from `art/sources.json`, `art/keepers.json` and `art/sounds.json`. Every model and sound of the game is listed with its author, the page it was fetched from, the licence stated there and the day it was fetched.", "",
             "## Keepers", "",
             "The keepers are models of the pack Ultimate Monsters by Quaternius, repainted in the game's colours and written out one movement a file by `tools/art/export_clips.py`.", "",
             "| Keeper | Model | Author | Licence | Page | Fetched |", "|---|---|---|---|---|---|"]
    for keeper in recipe["keepers"]:
        source = sources.get(keeper["source"])
        if source is None:
            raise SystemExit(f"{keeper['id']}: its source {keeper['source']} is not in art/sources.json")
        model = Path(keeper["source"]).name.split("_")[0]
        lines.append(f"| {keeper['id']} | {model} of {source['pack']} | {source['author']} | {source['licence']} | {source['page']} | {source['retrieved']} |")
    if SOUNDS.exists():
        packs = {Path(path).parts[0]: f for path, f in sources.items()}
        lines += ["", "## Sounds", "", "| Sound | When it plays | Made from | Pack | Author | Licence | Page | Fetched |", "|---|---|---|---|---|---|---|---|"]
        for sound in json.loads(SOUNDS.read_text())["sounds"]:
            pack = packs[sound["pack"]]
            lines.append(f"| {sound['file']} | {sound['when']} | {sound['from']} | {pack['pack']} | {pack['author']} | {pack['licence']} | {pack['page']} | {pack['retrieved']} |")
    return "\n".join(lines) + "\n"


def main() -> int:
    recipe = json.loads(RECIPE.read_text())
    wanted = set(sys.argv[1:])
    unknown = wanted - {k["id"] for k in recipe["keepers"]}
    if unknown:
        raise SystemExit(f"no keeper named {', '.join(sorted(unknown))} in art/keepers.json")
    MODELS.mkdir(parents=True, exist_ok=True)
    for keeper in recipe["keepers"]:
        if wanted and keeper["id"] not in wanted:
            continue
        made = build(keeper)
        size = sum(f.stat().st_size for f in made)
        print(f"{keeper['id']:10s} {len(keeper['clips'])} movements, 2 pictures, {size / 1e6:.1f} MB")
    (MODELS / "CREDITS.md").write_text(credits(recipe))
    print("credits written to", (MODELS / "CREDITS.md").relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
