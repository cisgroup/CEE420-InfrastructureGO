"""The rules of the game, once more in Python.

The app decides in Swift what it shows before the server answers, and the server decides in SQL what counts. This
module is the third telling of the same three rules, the tier of a drain, the points of a catch and the species of
the day. It exists so that the shared cases in model/spawn_cases.json can be checked here, where the pipeline's
tests run, and so that the species each case expects is computed by something other than the app.

    uv run python -m igo.game             checks the game's data files and replays the shared cases
    uv run python -m igo.game --species   prints the species cases for model/spawn_cases.json
"""

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime
from zoneinfo import ZoneInfo

from igo import ROOT

RESOURCES = ROOT / "app" / "InfrastructureGO" / "Resources"
RULES = RESOURCES / "spawn_rules.json"
SPECIES = RESOURCES / "species.json"
GEAR = RESOURCES / "gear.json"
FACTS = RESOURCES / "facts.json"
CASES = ROOT / "model" / "spawn_cases.json"
DAY_S = 86400
DASHES = re.compile(r"[‒–—―]| - | -- ")      # a dash used as punctuation, which the app's text never carries


def read(path):
    return json.loads(path.read_text())


def instant(text):
    """A timestamp with its offset as an aware datetime, or None for no timestamp."""
    return None if text is None else datetime.fromisoformat(text)


def local_day(moment, rules):
    """The calendar day of an instant in the game's timezone, as text."""
    return moment.astimezone(ZoneInfo(rules["timezone"])).date().isoformat()


def spawn_tier(now, last_any_at, my_last_at, storm_open, rules):
    """The tier of a drain for one player at one instant.

    The drain rests when the player already reported it on the same local day. Otherwise it is rare during a
    storm window, rare when nobody ever reported it, and after that its tier follows the elapsed time since the
    last report by anyone. A last report stamped after now counts as an age of zero.
    """
    if my_last_at is not None and local_day(my_last_at, rules) == local_day(now, rules):
        return 0
    if storm_open or last_any_at is None:
        return 3
    age_s = max(0.0, (now - last_any_at).total_seconds())
    by_age = sorted((t for t in rules["tiers"] if "min_age_days" in t), key=lambda t: -t["min_age_days"])
    for t in by_age:
        if age_s >= t["min_age_days"] * DAY_S:
            return t["tier"]
    return 1


def points(tier, great_catch, rules):
    """The points of a catch. A great catch adds its bonus at every tier but the resting one."""
    base = next(t["points"] for t in rules["tiers"] if t["tier"] == tier)
    return base + (rules["great_catch"]["points"] if great_catch and tier > 0 else 0)


def hash_index(key, count):
    """The first four bytes of the MD5 of the key as a big endian number, modulo the count."""
    return int.from_bytes(hashlib.md5(key.encode("utf-8")).digest()[:4], "big") % count


def species_for(inlet_id, day, tier, storm_open, species):
    """The id of the species at a drain on a local day, or None for a resting drain.

    The pool is the storm pool while a storm window is open and the tier has storm species, the base pool
    otherwise. The choice within the pool is the hash of the drain, the day, the tier and the pool, in the order
    the species file lists them.
    """
    if tier == 0:
        return None
    pool = "storm" if storm_open else "base"
    choices = [s["id"] for s in species if s["tier"] == tier and s["pool"] == pool]
    if not choices and pool == "storm":
        pool = "base"
        choices = [s["id"] for s in species if s["tier"] == tier and s["pool"] == pool]
    if not choices:
        return None
    return choices[hash_index(f"{inlet_id}|{day}|{tier}|{pool}", len(choices))]


def data_problems():
    """Every reason the game's data files cannot be shipped, as sentences. An empty list means they are sound."""
    out = []
    rules, species, gear = read(RULES), read(SPECIES)["species"], read(GEAR)
    facts = {f["id"]: f for f in read(FACTS)["facts"]} if FACTS.exists() else {}
    tiers = [t["tier"] for t in rules["tiers"]]
    if tiers != [0, 1, 2, 3]:
        out.append(f"The tiers are {tiers} and must be 0, 1, 2 and 3.")
    ages = [t.get("min_age_days") for t in rules["tiers"]]
    if ages[:2] != [None, None] or not (0 < ages[2] < ages[3]):
        out.append("Only the uncommon and the rare tier carry a minimum age, and the rare one the larger.")
    tier_points = [t["points"] for t in rules["tiers"]]
    if tier_points != sorted(tier_points) or len(set(tier_points)) != 4:
        out.append("The points must grow with the tier.")
    if not rules["fence"]["radius_m"] < rules["fence"]["server_max_distance_m"]:
        out.append("The server's distance limit must lie outside the fence.")
    if not rules["ring"]["end_scale"] < rules["great_catch"]["ring_scale_max"] < rules["ring"]["start_scale"]:
        out.append("The great catch must be reachable, between the ring's smallest and largest size.")
    ids = [s["id"] for s in species]
    if len(set(ids)) != len(ids):
        out.append("Two species share an id.")
    for tier in (1, 2, 3):
        if not [s for s in species if s["tier"] == tier and s["pool"] == "base"]:
            out.append(f"Tier {tier} has no species in the base pool.")
    for s in species:
        if s["pool"] not in ("base", "storm") or s["tier"] not in (1, 2, 3):
            out.append(f"Species {s['id']} has an unknown pool or tier.")
        if s["model"] != "procedural" and not s["credit"]:
            out.append(f"Species {s['id']} uses a model file without a credit line.")
        if s["model"] != "procedural" and not (RESOURCES / "Models" / s["model"]).exists():
            out.append(f"Species {s['id']} names the model {s['model']}, which is not in Resources/Models.")
    levels = gear["levels"]
    if [l["level"] for l in levels] != list(range(1, len(levels) + 1)) or levels[0]["points"] != 0:
        out.append("Levels must count up from 1 and the first must start at 0 points.")
    if any(b["points"] <= a["points"] for a, b in zip(levels, levels[1:])):
        out.append("Every level must need more points than the one before.")
    gear_ids = [g["id"] for g in gear["gear"]]
    handed = [l["gear"] for l in levels if l["gear"]]
    if sorted(handed) != sorted(gear_ids) or len(set(gear_ids)) != len(gear_ids):
        out.append("Every piece of gear must be handed out by exactly one level.")
    for owner, fact_id in [(f"species {s['id']}", s["fact_id"]) for s in species] + [(f"gear {g['id']}", g["fact_id"]) for g in gear["gear"]]:
        if fact_id is not None and fact_id not in facts:
            out.append(f"The fact {fact_id} of {owner} is not in facts.json.")
    for f in facts.values():
        if not (f.get("text") and f.get("source") and f.get("retrieved")):
            out.append(f"The fact {f.get('id')} lacks its text, its source or its retrieval date.")
    shown = [s["name"] for s in species] + [g["name"] for g in gear["gear"]] + [gear["role"]["name"]] + [f.get("text", "") for f in facts.values()]
    for text in shown:
        if DASHES.search(text):
            out.append(f"The text '{text}' uses a dash as punctuation.")
    return out


def replay(cases=None):
    """The shared cases against this module. Returns the names of the cases that came out differently."""
    cases = cases or read(CASES)
    rules, species = read(RULES), read(SPECIES)["species"]
    wrong = []
    for c in cases["tier_cases"]:
        got = spawn_tier(instant(c["now"]), instant(c["last_any_at"]), instant(c["my_last_at"]), c["storm_open"], rules)
        if got != c["tier"]:
            wrong.append(f"tier case '{c['name']}' gave {got}, expected {c['tier']}")
    for c in cases["points_cases"]:
        got = points(c["tier"], c["great_catch"], rules)
        if got != c["points"]:
            wrong.append(f"points case tier {c['tier']} great {c['great_catch']} gave {got}, expected {c['points']}")
    for c in cases["species_cases"]:
        got = species_for(c["inlet_id"], c["day"], c["tier"], c["storm_open"], species)
        if got != c["species"]:
            wrong.append(f"species case {c['inlet_id']} {c['day']} tier {c['tier']} gave {got}, expected {c['species']}")
    return wrong


def species_cases():
    """The species cases for the shared file, computed here. The app and the server must come to the same ids."""
    species = read(SPECIES)["species"]
    rows = []
    for inlet_id in ("in0001", "in0742", "in1495", "in2167", "in2371", "in3196", "in4439", "DEMO-LOBBY"):
        for day in ("2026-10-24", "2026-11-01", "2026-11-10"):
            for tier, storm in ((1, False), (2, False), (3, False), (3, True)):
                rows.append({"inlet_id": inlet_id, "day": day, "tier": tier, "storm_open": storm,
                             "species": species_for(inlet_id, day, tier, storm, species)})
    rows.append({"inlet_id": "in0001", "day": "2026-11-10", "tier": 0, "storm_open": False, "species": None})
    rows.append({"inlet_id": "in0001", "day": "2026-11-10", "tier": 0, "storm_open": True, "species": None})
    return rows


def main(argv=None):
    parser = argparse.ArgumentParser(description="Check the game's data files and replay the shared cases.")
    parser.add_argument("--species", action="store_true", help="print the species cases as json and stop")
    args = parser.parse_args(argv)
    if args.species:
        print(json.dumps(species_cases(), indent=1))
        return 0
    found = data_problems() + replay()
    for line in found:
        print(line)
    if found:
        return 1
    cases = read(CASES)
    print(f"the game's data files are sound and {len(cases['tier_cases'])} tier cases, {len(cases['points_cases'])} points cases "
          f"and {len(cases['species_cases'])} species cases came out as expected")
    return 0


if __name__ == "__main__":
    sys.exit(main())
