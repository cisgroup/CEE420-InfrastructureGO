"""A walk for an outing, planned the evening before.

An outing photographs every drain on a loop, the clear ones as well as the clogged ones, so the loop is chosen from
the map and not from what looks interesting on the day. This step takes a starting point, picks the drains nearest
to it, by site, and puts them in an order that makes a short round trip. It prints the walk street by street and
draws it. The distances are straight lines between drains, so the real walk along the streets is somewhat longer.

    uv run python -m igo.loops --zone west --count 35
    uv run python -m igo.loops --start 40.3568,-74.6727 --count 30 --all-owners
    uv run python -m igo.loops --zone west --road "Pardoe Road" --road "Wilson Road"
"""

import argparse
import json
import sys
from datetime import date

import numpy as np
import pandas as pd

from igo import ROOT, geo, zones
from igo.match import read_inlets

OUT = ROOT / "build" / "loops"
DEFAULT_COUNT = 35


def sites(inlets, play_zones, zone=None, roads=None, all_owners=False):
    """One row per site that an outing may visit, with its position in metres and the number of its grates."""
    table = inlets.assign(grates=inlets.groupby("site")["inlet_id"].transform("size"))
    heads = table[table["inlet_id"] == table["site"]].copy()
    if zone:
        heads = heads[heads["zone"] == zone]
    if roads:
        wanted = {r.lower() for r in roads}
        heads = heads[heads["road_name"].str.lower().isin(wanted)]
    if not all_owners:
        owners = {z["id"]: set(z["owners"]) for _, z in play_zones.iterrows()}
        heads = heads[[o in owners.get(z, ()) for z, o in zip(heads["zone"], heads["owner_type"])]]
    east, north = geo.metres(heads["lon"].to_numpy(), heads["lat"].to_numpy())
    return heads.assign(east=east, north=north).reset_index(drop=True)


def length(xy, order, closed=True):
    """The length in metres of a walk through the points in the given order, back to the first when closed."""
    path = xy[np.asarray(order)]
    steps = np.hypot(*np.diff(path, axis=0).T).sum()
    return float(steps + (np.hypot(*(path[-1] - path[0])) if closed and len(path) > 1 else 0.0))


def nearest_first(xy, start=0):
    """An order that always walks on to the nearest drain not yet visited."""
    left = set(range(len(xy))) - {start}
    order = [start]
    while left:
        here = xy[order[-1]]
        nxt = min(left, key=lambda j: (float(np.hypot(*(xy[j] - here))), j))
        order.append(nxt)
        left.remove(nxt)
    return order


def untangled(xy, order):
    """The same round trip with its crossings taken out, by reversing a stretch whenever that shortens the walk.

    The first drain stays first. The result is never longer than what came in.
    """
    order = list(order)
    n = len(order)
    if n < 4:
        return order
    improved = True
    while improved:
        improved = False
        for i in range(1, n - 1):
            for j in range(i + 1, n):
                a, b = xy[order[i - 1]], xy[order[i]]
                c, d = xy[order[j]], xy[order[(j + 1) % n]]
                now = np.hypot(*(a - b)) + np.hypot(*(c - d))
                then = np.hypot(*(a - c)) + np.hypot(*(b - d))
                if then < now - 1e-9:
                    order[i:j + 1] = reversed(order[i:j + 1])
                    improved = True
    return order


def plan(candidates, start=None, count=DEFAULT_COUNT):
    """The drains of a loop in walking order.

    The loop takes the `count` sites nearest to the start, begins at the one nearest to it and comes back there.
    Without a start it begins at the site nearest to the middle of all candidates.
    """
    if candidates.empty:
        raise ValueError("No drain fits what was asked for.")
    xy_all = candidates[["east", "north"]].to_numpy()
    if start is None:
        origin = xy_all.mean(axis=0)
    else:
        origin = np.array([float(v) for v in geo.metres(start[1], start[0])])
    reach = np.hypot(*(xy_all - origin).T)
    chosen = candidates.iloc[np.lexsort((candidates["inlet_id"].to_numpy(), reach))[:count]].reset_index(drop=True)
    xy = chosen[["east", "north"]].to_numpy()
    first = int(np.argmin(np.hypot(*(xy - origin).T)))
    order = untangled(xy, nearest_first(xy, first))
    walk = chosen.iloc[order].reset_index(drop=True)
    steps = np.r_[0.0, np.hypot(*np.diff(walk[["east", "north"]].to_numpy(), axis=0).T)]
    walk = walk.assign(stop=np.arange(1, len(walk) + 1), from_previous_m=np.round(steps, 0).astype(int))
    return walk, length(xy, order)


def draw(walk, path, title):
    """The loop on the town's streets, each drain with its number in walking order."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import pyogrio

    from igo import LAYER

    e, n = walk["east"].to_numpy(), walk["north"].to_numpy()
    pad = 60
    fig, ax = plt.subplots(figsize=(11, 11))
    for line in pyogrio.read_dataframe(LAYER, layer="roads").geometry.explode():
        xs, ys = np.asarray(line.coords).T[:2]
        re, rn = geo.metres(*geo.native_to_wgs84(xs, ys))
        if ((re > e.min() - 2 * pad) & (re < e.max() + 2 * pad) & (rn > n.min() - 2 * pad) & (rn < n.max() + 2 * pad)).any():
            ax.plot(re, rn, color="#c9ced4", linewidth=5, solid_capstyle="round", zorder=1)
    ax.plot(np.r_[e, e[0]], np.r_[n, n[0]], color="#e77500", linewidth=1.6, zorder=2)
    ax.scatter(e, n, s=230, color="#0b5d8a", edgecolor="white", linewidth=1.2, zorder=3)
    for r in walk.itertuples(index=False):
        ax.text(r.east, r.north, str(r.stop), color="white", fontsize=8, weight="bold", ha="center", va="center", zorder=4)
    ax.set_xlim(e.min() - pad, e.max() + pad)
    ax.set_ylim(n.min() - pad, n.max() + pad)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
    bar = 100
    x0, y0 = e.min() - pad + 15, n.min() - pad + 15
    ax.plot([x0, x0 + bar], [y0, y0], color="black", linewidth=3)
    ax.text(x0 + bar / 2, y0 + 8, "100 m", ha="center", fontsize=9)
    ax.set_title(title, fontsize=11, loc="left")
    fig.tight_layout()
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=110)
    plt.close(fig)
    return path


def geojson(walk, metres):
    """The loop as GeoJSON, a line and the drains in order, to put on any map."""
    points = [[float(r.lon), float(r.lat)] for r in walk.itertuples(index=False)]
    feats = [{"type": "Feature", "properties": {"kind": "loop", "straight_line_m": round(metres)}, "geometry": {"type": "LineString", "coordinates": points + points[:1]}}]
    for r in walk.itertuples(index=False):
        feats.append({"type": "Feature", "properties": {"stop": int(r.stop), "id": r.inlet_id, "road": r.road_name, "grates": int(r.grates)},
                      "geometry": {"type": "Point", "coordinates": [float(r.lon), float(r.lat)]}})
    return {"type": "FeatureCollection", "features": feats}


def main(argv=None):
    parser = argparse.ArgumentParser(description="A walk for an outing, planned the evening before.")
    parser.add_argument("--zone", help="keep to one play zone, by its id")
    parser.add_argument("--start", help="where the walk begins, as latitude,longitude")
    parser.add_argument("--count", type=int, default=DEFAULT_COUNT, help="how many drains the loop takes")
    parser.add_argument("--road", action="append", help="keep to these roads, may be given more than once")
    parser.add_argument("--all-owners", action="store_true", help="also take the drains that are not in the game, the private ones outside the campus")
    args = parser.parse_args(argv)
    start = tuple(float(v) for v in args.start.split(",")) if args.start else None
    play_zones = zones.read_zones()
    if args.zone and args.zone not in set(play_zones["id"]):
        print(f"There is no zone {args.zone}. The zones are {', '.join(play_zones['id'])}.")
        return 1
    try:
        walk, metres = plan(sites(read_inlets(), play_zones, args.zone, args.road, args.all_owners), start, args.count)
    except ValueError as error:
        print(error)
        return 1
    road = None
    for r in walk.itertuples(index=False):
        if r.road_name != road:
            road = r.road_name
            print(f"\n{road or 'no road name'}")
        rows = "" if r.grates == 1 else f", {r.grates} grates in a row"
        print(f"  {r.stop:3d}  {r.inlet_id}  {r.owner_type}{rows}" + (f", {r.from_previous_m} m on" if r.stop > 1 else ", the start"))
    grates = int(walk["grates"].sum())
    print(f"\n{len(walk)} drains with {grates} grates on {walk['road_name'].replace('', 'no road name').nunique()} roads, "
          f"{metres / 1000:.1f} km round trip in straight lines between drains")
    name = f"loop_{date.today().isoformat()}_{args.zone or 'town'}_{len(walk)}"
    picture = draw(walk, OUT / f"{name}.png", f"{len(walk)} drains, {metres / 1000:.1f} km in straight lines, numbered in walking order")
    (OUT / f"{name}.geojson").write_text(json.dumps(geojson(walk, metres)) + "\n")
    print("drew", picture.relative_to(ROOT), "and wrote the same loop as", (OUT / f"{name}.geojson").relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
