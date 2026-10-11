"""The inlet ids and the derived files.

The numbers asserted here are facts of the pinned layer of 2026-09-11, found by running the derivation and written
down so that a change in the layer, the rule or a library shows up as a failing test and not as a silent new id.
"""

import json
import re

import numpy as np
import pandas as pd
import pytest

from igo import OWNER_TYPES, PERSON_PATTERN, ROOT, geo, inlets


def test_layer_counts(derived):
    s = derived.summary
    assert s["layer_rows"] == 4455
    assert s["inlets"] == 4439
    assert s["collapsed_rows"] == 16
    assert s["inlets"] + s["collapsed_rows"] == s["layer_rows"]
    assert s["linked_pairs_within_link"] == 17
    assert s["rows_at_identical_positions"] == 11
    assert s["coord_columns_missing"] == 75
    assert s["coord_columns_disagree"] == 31
    assert s["text_values_cleaned"]["Inlet_Type"] == 7
    assert s["text_values_cleaned"]["Grate_Design"] == 6


def test_rows_of_grates_form_sites(derived):
    """Grates that stand in a row along one kerb are one site, named after the first inlet of the row."""
    s = derived.summary
    table = derived.inlets
    assert s["sites"] == 4344 and s["sites_of_more_than_one_inlet"] == 89 and s["inlets_in_sites_of_more_than_one"] == 184
    assert s["largest_site_inlets"] == 3 and s["widest_site_m"] < 2 * inlets.SITE_LINK_M + 0.01
    assert table["site"].nunique() == s["sites"]
    assert set(table["site"]) <= set(table["inlet_id"])
    assert (table["site"] <= table["inlet_id"]).all(), "a site is named after its first inlet"
    heads = table[table["inlet_id"] == table["site"]]
    assert len(heads) == s["sites"]
    assert s["sites_across_two_zones"] == 0, "a zone edge cuts a row of grates in two, move the edge"
    pardoe = table[table["site"] == "in1342"]
    assert pardoe["inlet_id"].tolist() == ["in1342", "in1343", "in1344"] and set(pardoe["road_name"]) == {"Pardoe Road"}


def test_inlets_of_different_sites_stand_apart(derived):
    xy = np.c_[geo.metres(derived.inlets["lon"].to_numpy(), derived.inlets["lat"].to_numpy())]
    site = derived.inlets["site"].to_numpy()
    pairs = inlets.cKDTree(xy).query_pairs(r=inlets.SITE_LINK_M - 0.02, output_type="ndarray")
    assert len(pairs) > 80
    assert (site[pairs[:, 0]] == site[pairs[:, 1]]).all()
    far = inlets.cKDTree(xy).query_pairs(r=inlets.SITE_LINK_M + 0.02, output_type="ndarray")
    assert len(far) >= len(pairs)


def test_owner_counts_cover_every_inlet(derived):
    by_owner = derived.summary["by_owner"]
    assert set(by_owner) == set(OWNER_TYPES)
    assert sum(by_owner.values()) == len(derived.inlets)


def test_ids_are_unique_and_in_order(derived):
    ids = derived.inlets["inlet_id"].tolist()
    assert ids == [f"in{k:04d}" for k in range(1, len(ids) + 1)]
    assert all(re.fullmatch(r"in\d{4}", i) for i in ids)


def test_duplicates_account_for_every_layer_row(derived):
    assert int(derived.inlets["duplicates"].sum()) == len(derived.twins)
    assert set(derived.twins["inlet_id"]) <= set(derived.inlets["inlet_id"])
    assert set(derived.inlets["fid"]).isdisjoint(derived.twins["fid"])
    assert len(set(derived.inlets["fid"]) | set(derived.twins["fid"])) == 4455
    assert derived.twins["distance_m"].max() <= inlets.DUPLICATE_LINK_M * 2      # a chain of three spans two links at most


def test_no_two_inlets_within_the_link(derived):
    xy = np.c_[geo.metres(derived.inlets["lon"].to_numpy(), derived.inlets["lat"].to_numpy())]
    nearest = inlets.cKDTree(xy).query(xy, k=2)[0][:, 1]
    assert nearest.min() > inlets.DUPLICATE_LINK_M - 0.02      # the seven decimals of the files round by a centimetre


def test_a_typed_row_is_kept_over_an_untyped_twin(layers, play_zones):
    raw, boundary, provenance = layers
    pair = raw.iloc[[0, 0]].copy()
    pair.index = [900001, 900002]
    pair.loc[900001, "Inlet_Type"] = None
    pair.loc[900002, "Inlet_Type"] = "Type A - Single Grate Inlet"
    out = inlets.derive(pair, boundary, play_zones, provenance)
    assert len(out.inlets) == 1 and len(out.twins) == 1
    assert out.inlets.loc[0, "fid"] == 900002 and out.inlets.loc[0, "duplicates"] == 1
    assert out.twins.loc[0, "fid"] == 900001


def test_ids_come_from_the_geometry_alone(layers, play_zones, derived):
    raw, boundary, provenance = layers
    spoiled = raw.copy()
    spoiled["Easting"] = spoiled["Easting"] + 200.0
    spoiled["Northing"] = np.nan
    spoiled["Longitude"] = 0.0
    spoiled["Latitude"] = 0.0
    out = inlets.derive(spoiled, boundary, play_zones, provenance)
    assert out.inlets[["inlet_id", "fid", "lon", "lat", "coord_hash"]].equals(derived.inlets[["inlet_id", "fid", "lon", "lat", "coord_hash"]])
    assert out.summary["coord_columns_missing"] == 4455
    assert out.summary["coordinates"]["rows_compared_with_the_towns_columns"] == 0


def test_ids_do_not_depend_on_the_row_order(layers, play_zones, derived):
    raw, boundary, provenance = layers
    shuffled = raw.sample(frac=1.0, random_state=7)
    out = inlets.derive(shuffled, boundary, play_zones, provenance)
    assert out.inlets.equals(derived.inlets)
    assert out.twins.equals(derived.twins)


def test_a_layer_in_another_system_is_refused(layers, play_zones):
    raw, boundary, provenance = layers
    with pytest.raises(ValueError, match="expected in EPSG:6527"):
        inlets.derive(raw.to_crs("EPSG:4326"), boundary, play_zones, provenance)


def test_coordinates_match_the_towns_own_columns(layers, derived):
    """The geometry with the named datum operation lands on the town's Longitude and Latitude where those are sound."""
    raw, _, _ = layers
    town = raw.loc[derived.inlets["fid"]]
    sound = ~(derived.inlets["coord_columns_missing"] | derived.inlets["coord_columns_disagree"]).to_numpy()
    assert sound.sum() > 4300
    gap = geo.offset_m(derived.inlets["lon"].to_numpy()[sound], derived.inlets["lat"].to_numpy()[sound],
                       town["Longitude"].to_numpy()[sound], town["Latitude"].to_numpy()[sound])
    assert gap.max() < 0.03
    c = derived.summary["coordinates"]
    assert c["operation"].startswith("EPSG:1515")
    assert 0.85 < c["shift_a_plain_reprojection_would_drop_m"] < 0.98


def test_a_plain_reprojection_would_miss_the_towns_columns(layers):
    """The negative control of the test above. Without the datum operation the gap is most of a metre."""
    raw, _, _ = layers
    sound = (raw["Longitude"].notna() & (np.hypot(raw.geometry.x - raw["Easting"], raw.geometry.y - raw["Northing"]) <= 1.0)).to_numpy()
    lon, lat = geo.nad83_geographic(raw.geometry.x.to_numpy()[sound], raw.geometry.y.to_numpy()[sound])
    gap = geo.offset_m(lon, lat, raw["Longitude"].to_numpy()[sound], raw["Latitude"].to_numpy()[sound])
    assert gap.min() > 0.85


def test_committed_files_equal_a_fresh_derivation(derived, layers):
    _, _, provenance = layers
    for path, text in inlets.rendered(derived, provenance).items():
        assert path.exists(), f"{path.relative_to(ROOT)} is missing, run make inlets"
        assert path.read_text() == text, f"{path.relative_to(ROOT)} differs from a fresh derivation, run make inlets"


def test_derived_files_share_one_id_set():
    table = pd.read_csv(inlets.INLETS_CSV, dtype=str, keep_default_na=False)
    seed = pd.read_csv(inlets.SEED_CSV, dtype=str, keep_default_na=False)
    app = json.loads(inlets.APP_JSON.read_text())
    web = json.loads(inlets.WEB_GEOJSON.read_text())
    ids = table["inlet_id"].tolist()
    assert seed["inlet_id"].tolist() == ids
    assert [r["id"] for r in app["inlets"]] == ids
    assert [f["properties"]["id"] for f in web["features"]] == ids
    assert app["count"] == len(ids)
    lon = table["lon"].astype(float).tolist()
    lat = table["lat"].astype(float).tolist()
    assert [r["lon"] for r in app["inlets"]] == lon and [r["lat"] for r in app["inlets"]] == lat
    assert [f["geometry"]["coordinates"] for f in web["features"]] == [[a, b] for a, b in zip(lon, lat)]
    assert seed["lon"].astype(float).tolist() == lon and seed["zone"].tolist() == table["zone"].tolist()
    assert [r["zone"] for r in app["inlets"]] == table["zone"].tolist()
    assert [f["properties"]["zone"] for f in web["features"]] == table["zone"].tolist()
    assert [r["site"] for r in app["inlets"]] == table["site"].tolist() == seed["site"].tolist()
    assert [f["properties"]["site"] for f in web["features"]] == table["site"].tolist()


def test_every_derived_file_says_where_it_comes_from(layers):
    _, _, provenance = layers
    for name in ("stormwater_inlets", "boundary", "roads"):
        assert {"source", "licence", "retrieved"} <= set(provenance[name]), f"the layer {name} lost its provenance"
    for path in (inlets.APP_JSON, inlets.WEB_GEOJSON):
        head = json.loads(path.read_text())
        assert head["source"] and head["licence"] and head["retrieved"] == "2026-09-11"
    summary = json.loads(inlets.SUMMARY_JSON.read_text())
    assert summary["provenance"]["source"] and summary["provenance"]["licence"]
    for path in (inlets.INLETS_CSV, inlets.SEED_CSV):
        assert set(pd.read_csv(path, dtype=str)["snapshot"]) == {"2026-09-11"}


def test_no_derived_file_can_name_a_person():
    pattern = re.compile(PERSON_PATTERN, re.IGNORECASE)
    columns = list(pd.read_csv(inlets.INLETS_CSV, nrows=0).columns) + list(pd.read_csv(inlets.SEED_CSV, nrows=0).columns)
    columns += list(pd.read_csv(inlets.TWINS_CSV, nrows=0).columns)
    columns += list(json.loads(inlets.APP_JSON.read_text())["inlets"][0])
    columns += list(json.loads(inlets.WEB_GEOJSON.read_text())["features"][0]["properties"])
    assert not [c for c in columns if pattern.search(c)]


def test_the_check_notices_a_stale_file(tmp_path, monkeypatch, capsys):
    """The negative control of the check mode. A changed byte in one derived file makes it report that file."""
    assert inlets.main(["--check"]) == 0
    stale = tmp_path / "inlets.csv"
    stale.write_text(inlets.INLETS_CSV.read_text().replace("in0001", "in9999", 1))
    monkeypatch.setattr(inlets, "INLETS_CSV", stale)
    capsys.readouterr()
    assert inlets.main(["--check"]) == 1
    assert "inlets.csv" in capsys.readouterr().out
