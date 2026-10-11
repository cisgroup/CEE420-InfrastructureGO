"""Fetch the free art and sound the game is built from, each from its author's page.

The files land in art/downloads/, which git ignores, and art/sources.json records for every file the page it
came from, the licence its author states, the day it was fetched, its size and its SHA-256, so that the credits
in the app are written from a file a script wrote. Nothing here needs a package.

    python3 tools/art/fetch.py            fetch what is missing
    python3 tools/art/fetch.py --list     say what would be fetched and fetch nothing
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import html
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOWNLOADS = ROOT / "art" / "downloads"
SOURCES = ROOT / "art" / "sources.json"
AGENT = {"User-Agent": "Mozilla/5.0 (InfrastructureGO art fetch)"}

# Creatures of the pack that the game leaves out, because it is meant for every resident.
LEFT_OUT = {"Alien", "Blue Demon", "Demon", "Ghost Skull", "Ninja", "Orc", "Orc Enemy", "Tribal", "Wizard"}

# The creatures. Their author links a Google Drive folder from quaternius.com, which answered "quota exceeded" on
# 11 October 2026, so they are taken from poly.pizza, where the same author offers the same pack one model a file.
POLY_PIZZA = {
    "pack": "Ultimate Monsters",
    "author": "Quaternius",
    "page": "https://poly.pizza/bundle/Ultimate-Monsters-Bundle-5oyGWAmOB6",
    "into": "ultimate_monsters",
}

DRIVE_PACKS = [
    {
        "pack": "Ultimate Modular Men",
        "author": "Quaternius",
        "page": "https://quaternius.com/packs/ultimatemodularcharacters.html",
        "licence": "CC0 1.0, as the page and the pack's License.txt state",
        "folder": "1USAAquX2JJWuA2m6zol0KUkFe3UkZ8zX",
        "take": [("", r"^License\.txt$"), ("Individual Characters/glTF", r"^Worker\.gltf$")],
        "into": "modular_men",
    },
    {
        "pack": "Ultimate Modular Women",
        "author": "Quaternius",
        "page": "https://quaternius.com/packs/ultimatemodularwomen.html",
        "licence": "CC0 1.0, as the page and the pack's License.txt state",
        "folder": "1720N9IGyQHXYvtvZJzazhxtTTlz-y2Vf",
        "take": [("", r"^License\.txt$"), ("Individual Characters/glTF", r"^Worker\.gltf$")],
        "into": "modular_women",
    },
]

ARCHIVES = [
    {
        "pack": "Interface Sounds",
        "author": "Kenney",
        "page": "https://kenney.nl/assets/interface-sounds",
        "licence": "CC0 1.0, as the page states",
        "link": r"https://kenney\.nl/media/pages/assets/interface-sounds/[^'\"]*\.zip",
        "into": "kenney_interface_sounds",
    },
    {
        "pack": "Impact Sounds",
        "author": "Kenney",
        "page": "https://kenney.nl/assets/impact-sounds",
        "licence": "CC0 1.0, as the page states",
        "link": r"https://kenney\.nl/media/pages/assets/impact-sounds/[^'\"]*\.zip",
        "into": "kenney_impact_sounds",
    },
    {
        "pack": "Swishes Sound Pack",
        "author": "artisticdude",
        "page": "https://opengameart.org/content/swishes-sound-pack",
        "licence": "CC0, as the page states",
        "link": r"https://opengameart\.org/sites/default/files/swishes\.zip",
        "into": "swishes",
    },
]


def get(url: str) -> bytes:
    with urllib.request.urlopen(urllib.request.Request(url, headers=AGENT), timeout=120) as answer:
        return answer.read()


def drive_listing(folder: str) -> list[dict]:
    """The entries of a shared Google Drive folder, read from the page Google serves for embedding it."""
    page = get(f"https://drive.google.com/embeddedfolderview?id={folder}#list").decode("utf-8", "replace")
    found = re.finditer(r'<div class="flip-entry" id="entry-([^"]+)".*?<a href="([^"]+)".*?<div class="flip-entry-title">(.*?)</div>', page, flags=re.S)
    return [{"id": m.group(1), "name": html.unescape(m.group(3)), "folder": "/folders/" in m.group(2)} for m in found]


def drive_files(pack: dict) -> list[tuple[str, str]]:
    """The files of a pack to take, as their path inside the pack and their Drive id."""
    wanted = []
    for path, pattern in pack["take"]:
        folder = pack["folder"]
        for step in [s for s in path.split("/") if s]:
            below = {e["name"]: e["id"] for e in drive_listing(folder) if e["folder"]}
            if step not in below:
                raise SystemExit(f"{pack['pack']}: the folder {path} is not there any more")
            folder = below[step]
            time.sleep(0.3)
        for entry in drive_listing(folder):
            stem = entry["name"].rsplit(".", 1)[0]
            if entry["folder"] or not re.match(pattern, entry["name"]) or stem in LEFT_OUT:
                continue
            wanted.append((f"{path}/{entry['name']}".lstrip("/"), entry["id"]))
        time.sleep(0.3)
    return wanted


def keep(target: Path, data: bytes) -> dict:
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def looks_like_a_web_page(data: bytes) -> bool:
    return data[:200].lstrip().lower().startswith((b"<!doctype html", b"<html"))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--list", action="store_true", help="say what would be fetched and fetch nothing")
    asked = parser.parse_args()
    today = datetime.date.today().isoformat()
    known = json.loads(SOURCES.read_text()) if SOURCES.exists() else {"about": "", "files": []}
    by_path = {f["path"]: f for f in known["files"]}
    refused = ""
    missing: list[str] = []

    listing = get(POLY_PIZZA["page"]).decode("utf-8", "replace").replace("\\u002F", "/")
    models = re.findall(r'"title":"([^"]+)","alt":"[^"]*","creator":\{[^{}]*\},"url":"(/m/[^"]+)","previewUrl":"https://static\.poly\.pizza/([0-9a-f-]+)\.webp",'
                        r'"publicID":"([^"]+)","licence":"([^"]+)"', listing)
    if not models:
        raise SystemExit("poly.pizza: the page no longer lists its models the way this script reads them")
    for title, link, file_id, public_id, licence in models:
        if title in LEFT_OUT:
            continue
        path = f"{POLY_PIZZA['into']}/{title.replace(' ', '')}_{public_id}.glb"
        target = DOWNLOADS / path
        if asked.list:
            print("would fetch" if not target.exists() else "have", path)
            continue
        if target.exists() and path in by_path:
            continue
        data = get(f"https://static.poly.pizza/{file_id}.glb")
        if data[:4] != b"glTF":
            raise SystemExit(f"{path}: poly.pizza answered with something that is not a model")
        by_path[path] = {"path": path, "pack": POLY_PIZZA["pack"], "author": POLY_PIZZA["author"], "page": f"https://poly.pizza{link}",
                         "licence": f"{licence}, as the model's page states", "from": f"https://static.poly.pizza/{file_id}.glb", "retrieved": today,
                         **keep(target, data)}
        print("fetched", path, by_path[path]["bytes"])
        time.sleep(0.2)

    for archive in ARCHIVES:
        page = get(archive["page"]).decode("utf-8", "replace")
        link = re.search(archive["link"], page)
        if not link:
            raise SystemExit(f"{archive['pack']}: no download link on {archive['page']}")
        path = f"{archive['into']}/{link.group(0).rsplit('/', 1)[-1]}"
        target = DOWNLOADS / path
        if asked.list:
            print("would fetch" if not target.exists() else "have", path)
            continue
        if target.exists() and path in by_path:
            continue
        by_path[path] = {"path": path, "pack": archive["pack"], "author": archive["author"], "page": archive["page"], "licence": archive["licence"],
                         "from": link.group(0), "retrieved": today, **keep(target, get(link.group(0)))}
        print("fetched", path, by_path[path]["bytes"])

    for pack in DRIVE_PACKS:
        for inside, drive_id in drive_files(pack):
            path = f"{pack['into']}/{inside}"
            target = DOWNLOADS / path
            if asked.list:
                print("would fetch" if not target.exists() else "have", path)
                continue
            if target.exists() and path in by_path:
                continue
            if refused:
                missing.append(path)
                continue
            data = get(f"https://drive.usercontent.google.com/download?id={drive_id}&export=download&confirm=t")
            if looks_like_a_web_page(data):
                # Google limits how often a shared file may be fetched in a day. Asking again and again only
                # makes it worse, so the first refusal ends the fetching from Google for this run.
                refused = "quota exceeded" if b"Quota exceeded" in data else "a web page instead of the file"
                missing.append(path)
                continue
            by_path[path] = {"path": path, "pack": pack["pack"], "author": pack["author"], "page": pack["page"], "licence": pack["licence"],
                             "from": f"https://drive.google.com/file/d/{drive_id}", "retrieved": today, **keep(target, data)}
            print("fetched", path, by_path[path]["bytes"])
            time.sleep(0.4)

    if not asked.list:
        known["about"] = ("Every file the art scripts start from, with the page of its author, the licence stated there, the day it was "
                          "fetched, its size and its SHA-256. Written by tools/art/fetch.py. The files themselves stay in art/downloads/, "
                          "which git ignores.")
        known["files"] = [by_path[p] for p in sorted(by_path)]
        SOURCES.write_text(json.dumps(known, indent=1) + "\n")
        print(f"{len(known['files'])} files, {sum(f['bytes'] for f in known['files']) / 1e6:.1f} MB, listed in {SOURCES.relative_to(ROOT)}")
    if missing:
        raise SystemExit(f"{len(missing)} files were not fetched, Google answered with {refused}. The first is {missing[0]}. Run again later.")


if __name__ == "__main__":
    sys.exit(main())
