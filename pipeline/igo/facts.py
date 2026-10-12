"""The fact cards of the game.

A fact is one or two plain sentences with the source they come from and the day the source was read. Every number
in a fact is filled in here from data/inlets/summary.json, which the inlets step wrote, so that no number in the
app is typed by hand. A fact whose source has not been read is not written. The keepers have no facts yet for
that reason.

    uv run python -m igo.facts            writes the app's facts.json
    uv run python -m igo.facts --check    renders again and compares with the file on disk
"""

import argparse
import json
import sys
from datetime import date

from igo import ROOT
from igo.inlets import SUMMARY_JSON

FACTS_JSON = ROOT / "app" / "InfrastructureGO" / "Resources" / "facts.json"
LAYER_SOURCE = "Municipality of Princeton, stormwater inlet layer, snapshot of {snapshot}"
FLYER_SOURCE = "Municipality of Princeton, Adopt a Drain flyer, princetonnj.gov/adoptadrain"
FLYER_RETRIEVED = "2026-09-16"


def count(n):
    """A count the way a card prints it, with a comma at the thousands."""
    return f"{n:,}"


def month_year(day):
    return date.fromisoformat(day).strftime("%B %Y")


def render(summary):
    """The facts with their numbers filled in from the summary of the inlets step."""
    layer = {"source": LAYER_SOURCE.format(snapshot=summary["snapshot"]), "retrieved": summary["provenance"].get("retrieved", summary["snapshot"])}
    flyer = {"source": FLYER_SOURCE, "retrieved": FLYER_RETRIEVED}
    near = round(100 * summary["spacing"]["share_within_10_m"])
    facts = [
        dict(id="drains_on_the_map", text=f"The town's map shows {count(summary['inlets'])} storm drains.", **layer),
        dict(id="who_owns_them", text=f"The town itself owns {count(summary['by_owner']['Municipality'])} of the drains on its map. "
                                      "The others belong to the county, the State, neighbouring towns and private owners.", **layer),
        dict(id="bicycle_safe", text=f"{count(summary['by_grate_design']['NJDOT Bicycle Safe Grate'])} drains in town carry the grate the State calls bicycle safe.", **layer),
        dict(id="last_inspection", text=f"The town inspected {count(summary['with_inspection_date'])} drains between "
                                        f"{month_year(summary['inspection_first'])} and {month_year(summary['inspection_last'])}.", **layer),
        dict(id="drains_like_company", text=f"Drains like company. {near} of every hundred drains in town have another drain within ten metres.", **layer),
        dict(id="check_before_and_after", text="Princeton's Adopt a Drain volunteers check their drain every couple of weeks, before and after a storm.", **flyer),
        dict(id="why_it_matters", text="A clear drain helps prevent flooding on the road and keeps the waterways clean.", **flyer),
    ]
    head = {
        "version": 1,
        "about": "The fact cards of the game, written by pipeline/igo/facts.py. Every number comes from data/inlets/summary.json and every fact names its source and the day the source was read.",
    }
    return head, facts


def text(summary):
    head, facts = render(summary)
    lines = ["{"] + [f" {json.dumps(k)}: {json.dumps(v, ensure_ascii=False)}," for k, v in head.items()] + [' "facts": [']
    lines.append(",\n".join("  " + json.dumps(f, ensure_ascii=False) for f in facts))
    return "\n".join(lines + [" ]", "}"]) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description="The fact cards of the game.")
    parser.add_argument("--check", action="store_true", help="render again and compare with the file on disk, writing nothing")
    args = parser.parse_args(argv)
    fresh = text(json.loads(SUMMARY_JSON.read_text()))
    if args.check:
        if not FACTS_JSON.exists() or FACTS_JSON.read_text() != fresh:
            print("app/InfrastructureGO/Resources/facts.json differs from a fresh rendering, run make facts")
            return 1
        print("the fact cards agree with a fresh rendering")
        return 0
    FACTS_JSON.write_text(fresh)
    for f in render(json.loads(SUMMARY_JSON.read_text()))[1]:
        print(f"{f['id']:24s} {f['text']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
