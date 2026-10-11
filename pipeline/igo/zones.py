"""The play zones, where the game is switched on.

A zone is a named polygon in data/zones.geojson with the day it becomes active and the owner types whose drains can
be caught inside it. The file is drawn by hand and is the only place a zone is edited. This module reads it, checks
it, and says which zone a point lies in. The inlets step copies the file to the app, the web map and the backend
seed, so that all of them switch the same drains on.
"""

import json
from datetime import date
from pathlib import Path

import geopandas as gpd
from shapely.geometry import shape

from igo import METRIC_CRS, OWNER_TYPES, ROOT, WGS84, ZONES

COPIES = (
    ROOT / "app" / "InfrastructureGO" / "Resources" / "zones.geojson",
    ROOT / "web" / "data" / "zones.geojson",
    ROOT / "backend" / "seed" / "zones.geojson",
)
REQUIRED = ("id", "name", "active_from", "active_to", "owners")


def read_zones(path=ZONES):
    """The zones as a GeoDataFrame in WGS 84 with one row per zone, after `problems` found nothing wrong."""
    raw = json.loads(Path(path).read_text())
    found = problems(raw)
    if found:
        raise ValueError("data/zones.geojson is not usable. " + " ".join(found))
    rows = [dict(f["properties"], geometry=shape(f["geometry"])) for f in raw["features"]]
    return gpd.GeoDataFrame(rows, geometry="geometry", crs=WGS84)


def problems(raw):
    """Every reason the zones file cannot be used, as sentences. An empty list means the file is sound."""
    out = []
    for key in ("source", "licence", "retrieved"):
        if not raw.get(key):
            out.append(f"The file does not say its {key}.")
    feats = raw.get("features") or []
    if not feats:
        return out + ["The file holds no zone."]
    ids = []
    geoms = []
    for k, f in enumerate(feats):
        p = f.get("properties") or {}
        label = p.get("id") or f"number {k + 1}"
        for key in REQUIRED:
            if key not in p:
                out.append(f"Zone {label} has no {key}.")
        if not p.get("id") or p["id"] != p["id"].lower() or not p["id"].replace("_", "").isalnum():
            out.append(f"Zone {label} needs an id of lowercase letters, digits and underscores.")
        ids.append(p.get("id"))
        for key in ("active_from", "active_to"):
            if p.get(key) is not None:
                try:
                    date.fromisoformat(p[key])
                except (TypeError, ValueError):
                    out.append(f"Zone {label} has an {key} that is not a date.")
        if p.get("active_from") is None:
            out.append(f"Zone {label} needs an active_from date.")
        unknown = [o for o in (p.get("owners") or []) if o not in OWNER_TYPES]
        if unknown or not p.get("owners"):
            out.append(f"Zone {label} needs owners from the layer's owner types, and has {unknown or 'none'}.")
        geom = shape(f["geometry"])
        if geom.geom_type not in ("Polygon", "MultiPolygon") or not geom.is_valid or geom.is_empty:
            out.append(f"Zone {label} is not a valid polygon.")
        geoms.append(geom)
    if len(set(ids)) != len(ids):
        out.append("Two zones share an id.")
    if not out:
        metric = gpd.GeoSeries(geoms, crs=WGS84).to_crs(METRIC_CRS)
        for a in range(len(geoms)):
            for b in range(a + 1, len(geoms)):
                shared = metric.iloc[a].intersection(metric.iloc[b]).area
                if shared > 1.0:
                    out.append(f"Zones {ids[a]} and {ids[b]} overlap on {shared:.0f} square metres.")
    return out


def zone_of(lon, lat, zones):
    """The zone id of every WGS 84 position, or the empty string where a position lies in no zone."""
    pts = gpd.GeoDataFrame(geometry=gpd.points_from_xy(lon, lat, crs=WGS84))
    joined = gpd.sjoin(pts, zones[["id", "geometry"]], predicate="within", how="left")
    if joined.index.duplicated().any():
        raise ValueError("A point lies in two zones, so the zones overlap.")
    return joined["id"].fillna("").to_numpy()


def is_active(zone, day):
    """Whether a zone row is switched on on the given date."""
    start = date.fromisoformat(zone["active_from"])
    end = date.fromisoformat(zone["active_to"]) if zone["active_to"] else None
    return start <= day and (end is None or day <= end)


def write_copies(path=ZONES, copies=COPIES):
    """Copy the zones file byte for byte to the places that bundle it, and return the paths written."""
    data = Path(path).read_bytes()
    for target in copies:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    return list(copies)
