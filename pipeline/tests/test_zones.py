"""The play zones. The file is drawn by hand, so the tests are the proof that a new drawing is usable."""

import copy
import json
from datetime import date

import pandas as pd

from igo import OWNER_TYPES, ZONES, inlets, zones


def raw_zones():
    return json.loads(ZONES.read_text())


def test_the_zones_file_is_sound():
    assert zones.problems(raw_zones()) == []


def test_zone_ids(play_zones):
    assert play_zones["id"].tolist() == ["west", "downtown", "campus"]


def test_every_zone_holds_drains_that_can_be_caught(derived):
    for zone_id, counts in derived.summary["zones"].items():
        assert counts["inlets"] >= 50, f"zone {zone_id} holds almost no inlet"
        assert 0 < counts["playable"] <= counts["inlets"]
        assert 0 < counts["playable_sites"] <= counts["sites"] <= counts["inlets"]
    assert derived.summary["playable"] == sum(z["playable"] for z in derived.summary["zones"].values())
    assert derived.summary["playable_sites"] == sum(z["playable_sites"] for z in derived.summary["zones"].values())


def test_inlet_zones_are_zone_ids_or_empty(derived, play_zones):
    assert set(derived.inlets["zone"]) <= set(play_zones["id"]) | {""}


def test_the_streets_of_the_first_photographs_are_in_the_west(derived):
    table = derived.inlets
    for road in ("Pardoe Road", "Wilson Road", "Mountain Avenue", "Bayard Lane"):
        found = set(table.loc[table["road_name"] == road, "zone"])
        assert found == {"west"}, f"{road} lies in {found}"
    assert set(table.loc[table["road_name"] == "Witherspoon Street", "zone"]) == {"downtown"}
    assert set(table.loc[table["road_name"] == "Nassau Street", "zone"]) >= {"downtown"}
    assert set(table.loc[table["road_name"] == "Ivy Lane", "zone"]) == {"campus"}
    assert set(table.loc[table["road_name"] == "Faculty Road", "zone"]) == {"campus"}


def test_private_drains_are_playable_on_campus_only(play_zones):
    owners = dict(zip(play_zones["id"], play_zones["owners"]))
    assert "Private" in owners["campus"]
    assert "Private" not in owners["west"] and "Private" not in owners["downtown"]
    assert all(set(o) <= set(OWNER_TYPES) for o in owners.values())


def test_copies_are_the_source_byte_for_byte():
    source = ZONES.read_bytes()
    for path in zones.COPIES:
        assert path.read_bytes() == source, f"{path.name} differs from data/zones.geojson, run make inlets"


def test_activity_by_date(play_zones):
    west = play_zones.iloc[0]
    assert not zones.is_active(west, date(2026, 10, 11))
    assert zones.is_active(west, date(2026, 10, 12))
    assert zones.is_active(west, date(2027, 3, 1))
    closed = west.copy()
    closed["active_to"] = "2026-12-07"
    assert zones.is_active(closed, date(2026, 12, 7)) and not zones.is_active(closed, date(2026, 12, 8))


def test_problems_are_found_one_by_one():
    """The negative controls. Each spoiled copy of the file must be refused for its own reason."""
    good = raw_zones()

    def spoiled(change):
        raw = copy.deepcopy(good)
        change(raw)
        return " ".join(zones.problems(raw))

    assert "does not say its licence" in spoiled(lambda r: r.pop("licence"))
    assert "holds no zone" in spoiled(lambda r: r.update(features=[]))
    assert "share an id" in spoiled(lambda r: r["features"][1]["properties"].update(id="west"))
    assert "lowercase" in spoiled(lambda r: r["features"][0]["properties"].update(id="West Side"))
    assert "not a date" in spoiled(lambda r: r["features"][0]["properties"].update(active_from="next week"))
    assert "needs an active_from" in spoiled(lambda r: r["features"][0]["properties"].update(active_from=None))
    assert "needs owners" in spoiled(lambda r: r["features"][0]["properties"].update(owners=["Municipality", "Nobody"]))
    assert "has no owners" in spoiled(lambda r: r["features"][0]["properties"].pop("owners"))
    assert "overlap" in spoiled(lambda r: r["features"][1]["geometry"].update(coordinates=r["features"][0]["geometry"]["coordinates"]))

    def bow_tie(r):
        r["features"][2]["geometry"]["coordinates"] = [[[-74.66, 40.34], [-74.65, 40.35], [-74.65, 40.34], [-74.66, 40.35], [-74.66, 40.34]]]
    assert "not a valid polygon" in spoiled(bow_tie)


def test_the_zone_column_follows_the_drawing(layers, play_zones, derived):
    """Moving a zone moves the drains with it. A zone pushed out to sea holds none."""
    raw, boundary, provenance = layers
    moved = play_zones.copy()
    moved["geometry"] = moved.geometry.translate(xoff=5.0)
    out = inlets.derive(raw, boundary, moved, provenance)
    assert (out.inlets["zone"] == "").all()
    assert out.inlets["inlet_id"].equals(derived.inlets["inlet_id"])
    assert pd.Series(out.summary["zones"]).map(lambda z: z["inlets"]).sum() == 0
