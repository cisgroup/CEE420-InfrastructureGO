"""The inlet ids and the files derived from the town's layer.

The town's layer has no id column. This module gives every inlet an id that depends on the geometry alone, collapses
the points that lie within a metre of each other into one inlet, and writes the same rows to the places that need
them, so that the pipeline, the app, the backend and the web map agree on every id. The pinned file in data/town is
the reference and is never fetched again into this scheme.

The layer draws every grate as a point of its own, also where two or three grates stand in a row along one kerb.
Such a row is one drain to anyone who stands in front of it, one photograph shows all of it, and a phone cannot
tell its grates apart. So every inlet also gets a site, the id of the first inlet of its row, and the game, the
matching of photographs and the evaluation count by site. An inlet that stands alone is its own site.

    uv run python -m igo.inlets            writes every derived file and prints the counts
    uv run python -m igo.inlets --check    derives again and compares with the files on disk
"""

import argparse
import hashlib
import json
import sys
from dataclasses import dataclass

import numpy as np
import pandas as pd
import pyogrio
import shapely
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree

from igo import LAYER, NATIVE_CRS, ROOT, SNAPSHOT
from igo import geo
from igo import zones as zones_module

TEXT_COLUMNS = ("Inlet_Type", "Owner_Type", "Road_Name", "Grate_Design", "Catch_Basin_Present", "inspected")
DUPLICATE_LINK_M = 1.0        # points closer than this are one inlet drawn twice
SITE_LINK_M = 2.5             # inlets closer than this are the grates of one row along a kerb, one site
COLUMN_TOLERANCE_FT = 1.0     # the Easting and Northing columns may differ from the geometry by this much
BOUNDARY_GEOGRAPHIC = "EPSG:4269"   # NAD83 longitude and latitude, the boundary layer's own datum
SEASON_EPOCH = 2026.8         # the decimal year of the first season, for the note on plate motion

INLETS_CSV = ROOT / "data" / "inlets" / "inlets.csv"
TWINS_CSV = ROOT / "data" / "inlets" / "duplicates.csv"
SUMMARY_JSON = ROOT / "data" / "inlets" / "summary.json"
APP_JSON = ROOT / "app" / "InfrastructureGO" / "Resources" / "inlets.json"
WEB_GEOJSON = ROOT / "web" / "data" / "inlets.geojson"
SEED_CSV = ROOT / "backend" / "seed" / "inlets.csv"

CSV_COLUMNS = ["inlet_id", "fid", "lon", "lat", "inlet_type", "owner_type", "road_name", "grate_design",
               "catch_basin_present", "inspected", "coord_hash", "duplicates", "site", "outside_boundary", "zone",
               "coord_columns_missing", "coord_columns_disagree", "snapshot"]
SEED_COLUMNS = ["inlet_id", "lon", "lat", "inlet_type", "owner_type", "road_name", "grate_design",
                "catch_basin_present", "inspected", "duplicates", "site", "zone", "snapshot"]
TWIN_COLUMNS = ["inlet_id", "fid", "lon", "lat", "inlet_type", "owner_type", "road_name", "grate_design", "distance_m"]


@dataclass
class Derived:
    inlets: pd.DataFrame      # one row per inlet, the collapsed set, in id order
    twins: pd.DataFrame       # the rows that were collapsed into another inlet
    summary: dict             # every count a document may quote


def read_layers(path=LAYER):
    """The inlet points with the layer's row number as index, the boundary polygon, and the provenance of each."""
    inlets = pyogrio.read_dataframe(path, layer="stormwater_inlets", fid_as_index=True)
    boundary = pyogrio.read_dataframe(path, layer="boundary")
    provenance = {name: pyogrio.read_info(path, layer=name)["layer_metadata"] for name in ("stormwater_inlets", "boundary", "roads")}
    return inlets, boundary, provenance


def clean(series):
    """A text column without carriage returns, line feeds and surrounding blanks, the empty string for no value."""
    return series.fillna("").astype(str).str.replace("\r", "", regex=False).str.replace("\n", "", regex=False).str.strip()


def components(xy, link_m):
    """Single linkage groups of points in metres. Two points share a group when a chain of steps shorter than
    `link_m` joins them. Returns the group number of every point and the number of linked pairs."""
    pairs = cKDTree(xy).query_pairs(r=link_m, output_type="ndarray")
    n = len(xy)
    graph = coo_matrix((np.ones(len(pairs)), (pairs[:, 0], pairs[:, 1])), shape=(n, n))
    return connected_components(graph, directed=False)[1], len(pairs)


def spacing(xy):
    """The distance from every point to its nearest neighbour, summarised the way the documents quote it."""
    nearest = cKDTree(xy).query(xy, k=2)[0][:, 1]
    return {
        "median_nearest_m": round(float(np.median(nearest)), 2),
        "share_within_5_m": round(float((nearest < 5).mean()), 4),
        "share_within_10_m": round(float((nearest < 10).mean()), 4),
        "share_within_15_m": round(float((nearest < 15).mean()), 4),
    }


def inside_boundary(x_ft, y_ft, boundary):
    """Whether positions in the layer's feet lie inside the municipal boundary.

    The boundary is on the first NAD83 and the inlets on NAD83(2011). The best operation between the two needs a
    grid file that is not everywhere installed, and a result that depends on the machine is worse than a few
    decimetres at the town line. So both are taken to plain longitude and latitude by undoing their projections,
    which every machine does alike, and compared there.
    """
    town = boundary.to_crs(BOUNDARY_GEOGRAPHIC).geometry.union_all()
    lon, lat = geo.nad83_geographic(x_ft, y_ft)
    return shapely.contains_xy(town, lon, lat)


def derive(raw, boundary, zones, provenance=None):
    """Ids, collapsed duplicates, coordinates, flags and zones for the raw layer.

    The order that carries the ids is the geometry's easting, then its northing, both rounded to a hundredth of a
    foot, then the inlet type with untyped rows last, then the layer's row number. Nothing in it reads the Easting
    and Northing columns, which are empty on some rows and wrong on others, and nothing reads the Longitude and
    Latitude columns except the comparison that goes into the summary.
    """
    if raw.crs is None or raw.crs.to_epsg() != int(NATIVE_CRS.split(":")[1]):
        raise ValueError(f"The inlet layer is expected in {NATIVE_CRS} and is in {raw.crs}.")
    g = raw.copy()
    g["fid"] = np.asarray(g.index, dtype=int)
    g = g.reset_index(drop=True)
    cleaned = {}
    for column in TEXT_COLUMNS:
        tidy = clean(g[column])
        cleaned[column] = int((g[column].fillna("") != tidy).sum())
        g[column] = tidy
    g["x"] = g.geometry.x
    g["y"] = g.geometry.y
    g["x_key"] = g["x"].round(2)
    g["y_key"] = g["y"].round(2)
    g["type_key"] = g["Inlet_Type"].where(g["Inlet_Type"] != "", "~")       # the tilde sorts after every letter
    g = g.sort_values(["x_key", "y_key", "type_key", "fid"], kind="mergesort").reset_index(drop=True)
    n = len(g)

    lon, lat = geo.native_to_wgs84(g["x"].to_numpy(), g["y"].to_numpy())
    xy = np.c_[geo.metres(lon, lat)]
    group, linked_pairs = components(xy, DUPLICATE_LINK_M)
    g["group"] = group
    g["position"] = np.arange(n)
    g["untyped"] = (g["Inlet_Type"] == "").astype(int)
    keeper = g.sort_values(["group", "untyped", "position"], kind="mergesort").groupby("group")["position"].first()
    g["keeper"] = g["group"].map(keeper)
    kept_mask = (g["keeper"] == g["position"]).to_numpy()

    g["lon"] = np.round(lon, 7)
    g["lat"] = np.round(lat, 7)
    missing = (g["Easting"].isna() | g["Northing"].isna()).to_numpy()
    offset_ft = np.hypot(g["x"] - g["Easting"], g["y"] - g["Northing"]).to_numpy()
    disagree = ~missing & (offset_ft > COLUMN_TOLERANCE_FT)
    g["coord_columns_missing"] = missing
    g["coord_columns_disagree"] = disagree
    g["coord_hash"] = [hashlib.sha1(f"{x:.1f},{y:.1f}".encode()).hexdigest()[:8] for x, y in zip(g["x"], g["y"])]
    g["outside_boundary"] = ~inside_boundary(g["x"].to_numpy(), g["y"].to_numpy(), boundary)
    g["zone"] = zones_module.zone_of(g["lon"].to_numpy(), g["lat"].to_numpy(), zones)

    kept = g[kept_mask].copy().reset_index(drop=True)
    kept["inlet_id"] = [f"in{k:04d}" for k in range(1, len(kept) + 1)]
    kept["duplicates"] = (kept["group"].map(g.groupby("group").size()) - 1).astype(int)
    kept["snapshot"] = SNAPSHOT
    id_of_position = dict(zip(kept["position"], kept["inlet_id"]))
    kept_xy = xy[kept_mask]
    row, site_pairs = components(kept_xy, SITE_LINK_M)
    kept["site"] = kept.groupby(row)["inlet_id"].transform("min")        # ids count up in the order of the rows, so the smallest is the first
    widths = [float(np.hypot(*(kept_xy[members][:, None, :] - kept_xy[members][None, :, :]).transpose(2, 0, 1)).max())
              for members in (np.flatnonzero(row == r) for r in np.flatnonzero(np.bincount(row) > 1))]

    twins = g[~kept_mask].copy()
    twins["inlet_id"] = twins["keeper"].map(id_of_position)
    twins["distance_m"] = np.hypot(*(xy[twins["position"].to_numpy()] - xy[twins["keeper"].to_numpy()]).T).round(3)
    twins = twins.sort_values(["inlet_id", "fid"]).reset_index(drop=True)

    names = {"Inlet_Type": "inlet_type", "Owner_Type": "owner_type", "Road_Name": "road_name",
             "Grate_Design": "grate_design", "Catch_Basin_Present": "catch_basin_present"}
    inlets = pd.DataFrame(kept.rename(columns=names)[CSV_COLUMNS])
    twins = pd.DataFrame(twins.rename(columns=names)[TWIN_COLUMNS])

    exact = g.duplicated(subset=["x", "y"], keep=False)
    head = (inlets["inlet_id"] == inlets["site"]).to_numpy()
    site_size = inlets.groupby("site")["inlet_id"].transform("size").to_numpy()
    zones_of_site = inlets.groupby("site")["zone"].nunique()
    plain_lon, plain_lat = geo.nad83_geographic(g["x"].to_numpy(), g["y"].to_numpy())
    comparable = (~missing & ~disagree & g["Longitude"].notna().to_numpy())
    against_town = geo.offset_m(lon[comparable], lat[comparable], g["Longitude"].to_numpy()[comparable], g["Latitude"].to_numpy()[comparable])
    today_lon, today_lat = geo.itrf2014(plain_lon, plain_lat, SEASON_EPOCH)
    coordinates = {
        "about": "Longitude and latitude are WGS 84, taken from the geometry with a named datum operation. The town's own Longitude and Latitude columns are never copied and serve as the check.",
        "operation": geo.datum_operation_name(),
        "rows_compared_with_the_towns_columns": int(comparable.sum()),
        "median_difference_from_the_towns_columns_cm": round(float(np.median(against_town)) * 100, 2) if comparable.any() else None,
        "largest_difference_from_the_towns_columns_cm": round(float(against_town.max()) * 100, 2) if comparable.any() else None,
        "shift_a_plain_reprojection_would_drop_m": round(float(np.median(geo.offset_m(lon, lat, plain_lon, plain_lat))), 3),
        "season_epoch": SEASON_EPOCH,
        "distance_to_itrf2014_at_the_season_epoch_m": round(float(np.median(geo.offset_m(lon, lat, today_lon, today_lat))), 3),
    }
    owners_of_zone = {z["id"]: set(z["owners"]) for _, z in zones.iterrows()}
    playable = np.array([o in owners_of_zone.get(z, ()) for z, o in zip(inlets["zone"], inlets["owner_type"])])
    by_zone = {}
    for zone_id in zones["id"]:
        inside = inlets["zone"] == zone_id
        by_zone[zone_id] = {
            "inlets": int(inside.sum()),
            "playable": int((inside & playable).sum()),
            "sites": int((inside & head).sum()),
            "playable_sites": int((inside & head & playable).sum()),
            "by_owner": {k: int(v) for k, v in inlets.loc[inside, "owner_type"].value_counts().sort_index().items()},
        }
    summary = {
        "about": "Counts from the town's stormwater inlet layer, written by pipeline/igo/inlets.py. Documents quote these numbers and type none.",
        "layer": LAYER.name,
        "snapshot": SNAPSHOT,
        "provenance": (provenance or {}).get("stormwater_inlets", {}),
        "coordinates": coordinates,
        "rule": {
            "id_order": "geometry easting, geometry northing (both rounded to 0.01 ft), inlet type with untyped last, layer row number",
            "duplicate_link_m": DUPLICATE_LINK_M,
            "site_link_m": SITE_LINK_M,
            "column_tolerance_ft": COLUMN_TOLERANCE_FT,
        },
        "layer_rows": n,
        "inlets": len(inlets),
        "collapsed_rows": len(twins),
        "linked_pairs_within_link": int(linked_pairs),
        "sites": int(head.sum()),
        "sites_of_more_than_one_inlet": int((head & (site_size > 1)).sum()),
        "inlets_in_sites_of_more_than_one": int((site_size > 1).sum()),
        "largest_site_inlets": int(site_size.max()),
        "widest_site_m": round(max(widths), 1) if widths else 0.0,
        "sites_across_two_zones": int((zones_of_site > 1).sum()),
        "groups_of_more_than_one": int((g.groupby("group").size() > 1).sum()),
        "rows_at_identical_positions": int(exact.sum()),
        "text_values_cleaned": cleaned,
        "coord_columns_missing": int(missing.sum()),
        "coord_columns_disagree": int(disagree.sum()),
        "coord_columns_largest_offset_ft": round(float(np.nanmax(offset_ft)), 1) if (~missing).any() else None,
        "outside_boundary": int(inlets["outside_boundary"].sum()),
        "without_road_name": int((inlets["road_name"] == "").sum()),
        "without_inlet_type": int((inlets["inlet_type"] == "").sum()),
        "with_inspection_date": int((inlets["inspected"] != "").sum()),
        "inspection_first": min((d for d in inlets["inspected"] if d), default=""),
        "inspection_last": max((d for d in inlets["inspected"] if d), default=""),
        "by_owner": {k: int(v) for k, v in inlets["owner_type"].value_counts().sort_index().items()},
        "by_inlet_type": {k or "(none)": int(v) for k, v in inlets["inlet_type"].value_counts().sort_index().items()},
        "by_grate_design": {k or "(none)": int(v) for k, v in inlets["grate_design"].value_counts().sort_index().items()},
        "spacing": spacing(xy[kept_mask]),
        "spacing_of_layer_rows": spacing(xy),
        "zones": by_zone,
        "in_a_zone": int((inlets["zone"] != "").sum()),
        "playable": int(playable.sum()),
        "playable_sites": int((head & playable).sum()),
    }
    return Derived(inlets=inlets, twins=twins, summary=summary)


def shown(path):
    """A path the way a message names it, relative to the repository where it lies inside it."""
    return str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)


def flag(value):
    """A boolean the way the csv files spell it."""
    return "true" if value else "false"


def csv_text(frame, columns):
    """A frame as csv text with seven decimals on coordinates, lower case booleans and Unix line ends."""
    out = frame[columns].copy()
    for column in out.columns:
        if out[column].dtype == bool:
            out[column] = out[column].map(flag)
    return out.to_csv(index=False, float_format="%.7f", lineterminator="\n")


def credit(provenance):
    """The source, licence and retrieval date every derived file repeats."""
    meta = (provenance or {}).get("stormwater_inlets", {})
    return {"source": meta.get("source", ""), "licence": meta.get("licence", ""), "retrieved": meta.get("retrieved", SNAPSHOT)}


def app_json_text(inlets, provenance):
    """The app's bundled inlets, one inlet per line so that a change shows as a line in a diff."""
    head = dict(credit(provenance), layer=LAYER.name, count=len(inlets))
    rows = []
    for r in inlets.itertuples(index=False):
        row = {"id": r.inlet_id, "lon": r.lon, "lat": r.lat, "owner": r.owner_type, "road": r.road_name,
               "type": r.inlet_type, "grate": r.grate_design, "dup": int(r.duplicates), "site": r.site, "zone": r.zone}
        rows.append("  " + json.dumps(row, ensure_ascii=False, separators=(",", ":")))
    lines = ["{"] + [f" {json.dumps(k)}: {json.dumps(v)}," for k, v in head.items()]
    return "\n".join(lines + [' "inlets": [', ",\n".join(rows), " ]", "}"]) + "\n"


def web_geojson_text(inlets, provenance):
    """The web map's inlets as GeoJSON points, one feature per line."""
    head = dict(credit(provenance), layer=LAYER.name)
    feats = []
    for r in inlets.itertuples(index=False):
        props = {"id": r.inlet_id, "owner": r.owner_type, "road": r.road_name, "type": r.inlet_type,
                 "grate": r.grate_design, "dup": int(r.duplicates), "site": r.site, "zone": r.zone}
        feat = {"type": "Feature", "properties": props, "geometry": {"type": "Point", "coordinates": [r.lon, r.lat]}}
        feats.append("  " + json.dumps(feat, ensure_ascii=False, separators=(",", ":")))
    lines = ["{", ' "type": "FeatureCollection",'] + [f" {json.dumps(k)}: {json.dumps(v)}," for k, v in head.items()]
    return "\n".join(lines + [' "features": [', ",\n".join(feats), " ]", "}"]) + "\n"


def rendered(derived, provenance):
    """Every derived file as a path and its text, the single list that both writing and checking walk."""
    return {
        INLETS_CSV: csv_text(derived.inlets, CSV_COLUMNS),
        TWINS_CSV: csv_text(derived.twins, TWIN_COLUMNS),
        SUMMARY_JSON: json.dumps(derived.summary, indent=1, ensure_ascii=False) + "\n",
        APP_JSON: app_json_text(derived.inlets, provenance),
        WEB_GEOJSON: web_geojson_text(derived.inlets, provenance),
        SEED_CSV: csv_text(derived.inlets, SEED_COLUMNS),
    }


def run():
    """Read the pinned layer and the zones and derive everything."""
    raw, boundary, provenance = read_layers()
    zones = zones_module.read_zones()
    return derive(raw, boundary, zones, provenance), provenance


def main(argv=None):
    parser = argparse.ArgumentParser(description="The inlet ids and the files derived from the town's layer.")
    parser.add_argument("--check", action="store_true", help="derive again and compare with the files on disk, writing nothing")
    args = parser.parse_args(argv)
    derived, provenance = run()
    files = rendered(derived, provenance)
    if args.check:
        stale = [shown(p) for p, text in files.items() if not p.exists() or p.read_text() != text]
        zone_source = zones_module.ZONES.read_bytes()
        stale += [shown(p) for p in zones_module.COPIES if not p.exists() or p.read_bytes() != zone_source]
        if stale:
            print("These files differ from a fresh derivation, run make inlets:", ", ".join(stale))
            return 1
        print(f"{len(files) + len(zones_module.COPIES)} derived files agree with a fresh derivation")
        return 0
    for path, text in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    copies = zones_module.write_copies()
    s = derived.summary
    print(f"{s['layer_rows']} rows in the layer, {s['inlets']} inlets after collapsing {s['collapsed_rows']} rows within {DUPLICATE_LINK_M:g} m "
          f"({s['linked_pairs_within_link']} linked pairs, {s['rows_at_identical_positions']} rows at identical positions)")
    print(f"{s['coord_columns_missing']} rows without coordinate columns, {s['coord_columns_disagree']} whose columns disagree with the geometry, "
          f"the worst by {s['coord_columns_largest_offset_ft']} ft")
    print(f"{s['outside_boundary']} inlets outside the boundary, {s['without_road_name']} without a road name, {s['without_inlet_type']} without a type")
    print(f"{s['sites']} sites, {s['sites_of_more_than_one_inlet']} of them rows of grates within {SITE_LINK_M:g} m holding {s['inlets_in_sites_of_more_than_one']} inlets, "
          f"the widest {s['widest_site_m']} m")
    print(f"median distance to the nearest inlet {s['spacing']['median_nearest_m']} m")
    for zone_id, z in s["zones"].items():
        print(f"zone {zone_id}: {z['inlets']} inlets at {z['sites']} sites, {z['playable_sites']} sites playable")
    for path in list(files) + copies:
        print("wrote", shown(path), f"({path.stat().st_size / 1024:.0f} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
