"""The need of a drain, once more in Python, and the check of the game's data files.

The app decides in Swift what it shows before the server answers, and the server will decide in SQL what counts.
This module is another telling of the one rule both must agree on today, the need of a drain and the points of a
look. It exists so that the shared cases in model/spawn_cases.json can be checked here, where the pipeline's
tests run. Who lives at a drain, the throw, the veil, the gear and the jobs are still being tuned by play. They
are tested in Swift alone until they have settled, and this module only checks that their data files are sound.

    uv run python -m igo.game             checks the game's data files and replays the shared cases
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
WORLD = RESOURCES / "world_rules.json"
KEEPERS = RESOURCES / "keepers.json"
GEAR = RESOURCES / "gear.json"
JOBS = RESOURCES / "jobs.json"
FACTS = RESOURCES / "facts.json"
MODELS = RESOURCES / "Models"
CASES = ROOT / "model" / "spawn_cases.json"
DAY_S = 86400
KINDS = ("common", "uncommon", "rare", "visitor")
ROLES = ("idle", "tell", "leap", "land", "accept", "refuse", "goodbye")
JOB_KINDS = ("looks", "new_sites", "new_keeper", "seal", "cells")
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
    """The need of a drain for one player at one instant, under its old name.

    The drain rests when the player already looked at it on the same local day. Otherwise the need is the highest
    during a storm window and when nobody ever looked, and after that it follows the elapsed time since the last
    look by anyone. A last look stamped after now counts as an age of zero.
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
    """The points of a look. The bonus named great catch is kept for the shared cases and skips resting drains."""
    base = next(t["points"] for t in rules["tiers"] if t["tier"] == tier)
    return base + (rules["great_catch"]["points"] if great_catch and tier > 0 else 0)


def hash_index(key, count):
    """The first four bytes of the MD5 of the key as a big endian number, modulo the count."""
    return int.from_bytes(hashlib.md5(key.encode("utf-8")).digest()[:4], "big") % count


def sitting_share(timing):
    """The least share of a round a keeper sits on the grate, taken with its shortest watch."""
    sitting = timing["watch_s"][0] + timing["tell_s"] + timing["settle_s"]
    away = timing["air_s"] + (timing["hide_s"] / timing["hide_every"] if timing["hide_every"] else 0)
    return sitting / (sitting + away)


def data_problems():
    """Every reason the game's data files cannot be shipped, as sentences. An empty list means they are sound."""
    out = []
    rules, world, keepers, gear, jobs = read(RULES), read(WORLD), read(KEEPERS)["keepers"], read(GEAR), read(JOBS)["jobs"]
    facts = {f["id"]: f for f in read(FACTS)["facts"]} if FACTS.exists() else {}

    tiers = [t["tier"] for t in rules["tiers"]]
    if tiers != [0, 1, 2, 3]:
        out.append(f"The tiers are {tiers} and must be 0, 1, 2 and 3.")
    ages = [t.get("min_age_days") for t in rules["tiers"]]
    if ages[:2] != [None, None] or not (0 < ages[2] < ages[3]):
        out.append("Only the two highest needs carry a minimum age, and the highest the larger.")
    tier_points = [t["points"] for t in rules["tiers"]]
    if tier_points != sorted(tier_points) or len(set(tier_points)) != 4:
        out.append("The points must grow with the tier.")
    if not rules["fence"]["radius_m"] < rules["fence"]["server_max_distance_m"]:
        out.append("The server's distance limit must lie outside the fence.")

    if world["kinds"]["common"] + world["kinds"]["uncommon"] != 100:
        out.append("The common and the uncommon share must add up to a hundred.")
    crate = world["crate_parts"]
    if len(crate) != 4 or crate[0] != 0 or crate != sorted(crate):
        out.append("A crate must hold nothing at a resting drain and never less at a drain with a higher need.")
    if world["rungs"] != sorted(set(world["rungs"])) or len(world["rungs"]) != 4:
        out.append("The four rungs of the journal must come at growing numbers of meetings.")
    if not rules["fence"]["radius_m"] < world["slip"]["min_m"] < world["slip"]["wheel_max_m"] <= world["slip"]["max_m"]:
        out.append("A keeper that slipped away must wait outside the fence, and nearer with the survey wheel.")

    ids = [k["id"] for k in keepers]
    if len(set(ids)) != len(ids):
        out.append("Two keepers share an id.")
    if not keepers or keepers[0]["kind"] != "common":
        out.append("The first keeper of the file is every player's first and must be a common one.")
    for k in keepers:
        if k["kind"] not in KINDS:
            out.append(f"Keeper {k['id']} has the unknown kind {k['kind']}.")
        if not k["credit"]:
            out.append(f"Keeper {k['id']} has no credit line.")
        for role in ROLES:
            clip = k["clips"].get(role)
            if clip is None:
                out.append(f"Keeper {k['id']} has no movement for {role}.")
            elif not (MODELS / f"{k['model']}_{clip}.usdz").exists():
                out.append(f"Keeper {k['id']} names the movement {clip}, and {k['model']}_{clip}.usdz is not in Resources/Models.")
        if sitting_share(k["timing"]) < world["catch"]["sitting_share"]:
            out.append(f"Keeper {k['id']} is away from the grate too much of the time for a fair throw.")

    levels = gear["levels"]
    if [l["level"] for l in levels] != list(range(1, len(levels) + 1)) or levels[0]["points"] != 0:
        out.append("Levels must count up from 1 and the first must start at 0 points.")
    if any(b["points"] <= a["points"] for a, b in zip(levels, levels[1:])):
        out.append("Every level must need more points than the one before.")
    pieces = gear["pieces"]
    prices = [p["parts"] for p in pieces]
    if len({p["id"] for p in pieces}) != len(pieces) or prices[0] != 0 or prices != sorted(prices):
        out.append("The pieces of gear need ids of their own, the first must be free and no piece may cost less than the one before.")
    opened = [p["opens"] for p in pieces if p["opens"]]
    if len(set(opened)) != len(opened):
        out.append("Two pieces of gear open the same thing.")

    if len({j["id"] for j in jobs}) != len(jobs):
        out.append("Two jobs share an id.")
    for j in jobs:
        if j["kind"] not in JOB_KINDS or j["count"] < 1:
            out.append(f"The job {j['id']} has an unknown kind or counts nothing.")
    if len({j["kind"] for j in jobs}) < world["jobs"]["slots"]:
        out.append("There are fewer kinds of jobs than jobs open at a time.")

    for f in facts.values():
        if not (f.get("text") and f.get("source") and f.get("retrieved")):
            out.append(f"The fact {f.get('id')} lacks its text, its source or its retrieval date.")
    shown = [gear["role"]["name"]] + [l["rank"] for l in levels] + [t for p in pieces for t in (p["name"], p["says"])] + [j["text"] for j in jobs]
    shown += [t for k in keepers for t in (k["name"], k["keeps"], k["tell"], k["hint"], k["returning"], k["pose"], k["joke"])]
    shown += [f.get("text", "") for f in facts.values()]
    for text in shown:
        if DASHES.search(text):
            out.append(f"The text '{text}' uses a dash as punctuation.")
    return out


def replay(cases=None):
    """The shared cases against this module. Returns the names of the cases that came out differently."""
    cases = cases or read(CASES)
    rules = read(RULES)
    wrong = []
    for c in cases["tier_cases"]:
        got = spawn_tier(instant(c["now"]), instant(c["last_any_at"]), instant(c["my_last_at"]), c["storm_open"], rules)
        if got != c["tier"]:
            wrong.append(f"tier case '{c['name']}' gave {got}, expected {c['tier']}")
    for c in cases["points_cases"]:
        got = points(c["tier"], c["great_catch"], rules)
        if got != c["points"]:
            wrong.append(f"points case tier {c['tier']} great {c['great_catch']} gave {got}, expected {c['points']}")
    return wrong


def main(argv=None):
    argparse.ArgumentParser(description="Check the game's data files and replay the shared cases.").parse_args(argv)
    found = data_problems() + replay()
    for line in found:
        print(line)
    if found:
        return 1
    cases = read(CASES)
    print(f"the game's data files are sound and {len(cases['tier_cases'])} tier cases and {len(cases['points_cases'])} points cases came out as expected")
    return 0


if __name__ == "__main__":
    sys.exit(main())
