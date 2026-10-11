"""Which inlet a photograph shows.

A phone knows where it was to a few metres, and half of the town's inlets have another inlet within ten metres, so
the nearest inlet is often not the one in the picture. This step proposes and never decides alone. It matches to
sites, because a row of grates along one kerb is one drain in a photograph, and a site is as near as its nearest
grate. A photograph is matched when its nearest site is close and clearly nearer than the runner up. Every other
photograph is written to a list with its candidates and a sheet to look at, and the decision is a line in
data/inlets/overrides.csv, which names an inlet and a reason and never a person. Shots taken in one stop are
matched together, because two fixes of one stop are better than one.

    uv run python -m igo.match            matches every capture and prints the decisions
    uv run python -m igo.match --sheets   also draws a sheet for every stop that needs a decision
"""

import argparse
import sys
from datetime import datetime

import numpy as np
import pandas as pd
from scipy.spatial import cKDTree

from igo import ROOT, geo
from igo.convert import CAPTURES, CONVERTED, PRIVATE, SHEETS
from igo.inlets import INLETS_CSV

MATCH_MAX_M = 15.0          # the nearest inlet must lie within this distance
MATCH_RATIO = 1.5           # and the runner up must be more than this many times farther
STOP_GAP_S = 15.0           # shots closer in time than this
STOP_GAP_M = 5.0            # and closer in space than this belong to one stop, kept tight because two inlets are often ten metres apart
CANDIDATES = 3
NO_INLET = "none"           # the override for a photographed inlet that the town's layer does not hold

OVERRIDES = ROOT / "data" / "inlets" / "overrides.csv"
MISSING = ROOT / "data" / "inlets" / "missing.csv"
MATCHES = PRIVATE / "matches.csv"
AMBIGUOUS = PRIVATE / "ambiguous.csv"
OVERRIDE_COLUMNS = ["photo_id", "inlet_id", "reason"]
MATCH_COLUMNS = ["photo_id", "stop", "inlet_id", "grates", "method", "distance_m", "runner_up_id", "runner_up_m", "ratio", "h_error_m"]
CANDIDATE_COLUMNS = ["stop", "photo_ids", "rank", "inlet_id", "grates", "road_name", "owner_type", "distance_m", "bearing", "off_heading"]


def read_inlets(path=None):
    table = pd.read_csv(path or INLETS_CSV, dtype=str, keep_default_na=False)
    table["lon"] = table["lon"].astype(float)
    table["lat"] = table["lat"].astype(float)
    return table


def read_overrides(path=None):
    path = path or OVERRIDES
    if not path.exists():
        return pd.DataFrame(columns=OVERRIDE_COLUMNS)
    return pd.read_csv(path, dtype=str, keep_default_na=False)


def stops(captures):
    """A stop number for every capture, counting up in the order of capture.

    Consecutive shots belong to one stop when they are close in time and in space. A capture without a time or a
    position is a stop of its own.
    """
    order = sorted(range(len(captures)), key=lambda k: (captures["captured_at"].iloc[k] is None or pd.isna(captures["captured_at"].iloc[k]),
                                                       str(captures["captured_at"].iloc[k]), captures["photo_id"].iloc[k]))
    east, north = geo.metres(captures["lon"].to_numpy(dtype=float), captures["lat"].to_numpy(dtype=float))
    out = np.zeros(len(captures), dtype=int)
    stop = 0
    previous = None
    for k in order:
        at = captures["captured_at"].iloc[k]
        usable = isinstance(at, str) and bool(at) and np.isfinite(east[k])
        if previous is not None and usable and previous[0] is not None:
            seconds = (datetime.fromisoformat(at) - previous[0]).total_seconds()
            metres = float(np.hypot(east[k] - previous[1], north[k] - previous[2]))
            if not (0 <= seconds <= STOP_GAP_S and metres <= STOP_GAP_M):
                stop += 1
        elif previous is not None:
            stop += 1
        out[k] = stop
        previous = (datetime.fromisoformat(at), east[k], north[k]) if usable else (None, None, None)
    return out + 1


def bearing(east, north):
    """The direction of an offset in degrees clockwise from north, from 0 up to 360."""
    return float(np.degrees(np.arctan2(east, north)) % 360)


def off_heading(direction, heading):
    """How far a direction lies from the camera's heading, from 0 to 180 degrees, or None without a heading."""
    if heading is None or not np.isfinite(heading):
        return None
    return round(abs((direction - heading + 180) % 360 - 180), 0)


def match(captures, inlets, overrides=None):
    """A decision for every capture and the candidates of every stop that needs one.

    Returns two frames. The first has one row per capture with the site, named by its first inlet, and the method,
    which is nearest, override, ambiguous, far when no site lies within reach, or unplaced when the capture has no
    position. The second lists, for every stop that is ambiguous or far, its nearest sites with their distance,
    their direction from the phone and how far that direction lies from the way the camera faced.
    """
    overrides = read_overrides() if overrides is None else overrides
    site_of = dict(zip(inlets["inlet_id"], inlets["site"]))
    unknown = sorted(set(overrides["inlet_id"]) - set(site_of) - {NO_INLET})
    if unknown:
        raise ValueError(f"data/inlets/overrides.csv names inlets that do not exist, {', '.join(unknown)}")
    forced = {photo: site_of.get(inlet, NO_INLET) for photo, inlet in zip(overrides["photo_id"], overrides["inlet_id"])}
    captures = captures.reset_index(drop=True)
    captures = captures.assign(stop=stops(captures))
    inlet_e, inlet_n = geo.metres(inlets["lon"].to_numpy(), inlets["lat"].to_numpy())
    tree = cKDTree(np.c_[inlet_e, inlet_n])
    east, north = geo.metres(captures["lon"].to_numpy(dtype=float), captures["lat"].to_numpy(dtype=float))
    site = inlets["site"].to_numpy()
    grates = inlets.groupby("site")["inlet_id"].size().to_dict()
    head = inlets.set_index("inlet_id")
    rows, candidates = [], []
    for stop, members in captures.groupby("stop", sort=True):
        index = members.index.to_numpy()
        placed = index[np.isfinite(east[index])]
        decided = dict(inlet_id="", grates=None, method="unplaced", distance_m=None, runner_up_id="", runner_up_m=None, ratio=None)
        if len(placed):
            near = sorted({j for k in placed for j in tree.query([east[k], north[k]], k=min(CANDIDATES * 3 + 2, len(inlets)))[1]})
            mean = {j: float(np.mean(np.hypot(east[placed] - inlet_e[j], north[placed] - inlet_n[j]))) for j in near}
            nearest_grate = {}
            for j in near:                               # a site is as near as its nearest grate
                if site[j] not in nearest_grate or mean[j] < mean[nearest_grate[site[j]]]:
                    nearest_grate[site[j]] = j
            ranked = sorted(nearest_grate, key=lambda s: (mean[nearest_grate[s]], s))[:CANDIDATES]
            distance = {s: mean[nearest_grate[s]] for s in ranked}
            first = ranked[0]
            second = ranked[1] if len(ranked) > 1 else None
            ratio = distance[second] / distance[first] if second is not None and distance[first] > 0 else float("inf")
            decided.update(distance_m=round(distance[first], 1), runner_up_id=second or "",
                           runner_up_m=round(distance[second], 1) if second is not None else None, ratio=round(ratio, 2) if np.isfinite(ratio) else None)
            if distance[first] > MATCH_MAX_M:
                decided.update(method="far")
            elif ratio > MATCH_RATIO:
                decided.update(inlet_id=first, grates=grates[first], method="nearest")
            else:
                decided.update(method="ambiguous")
            if decided["method"] in ("ambiguous", "far"):
                centre_e, centre_n = float(east[placed].mean()), float(north[placed].mean())
                heading = members["heading"].astype(float).iloc[0] if "heading" in members else None
                for rank, s in enumerate(ranked, start=1):
                    j = nearest_grate[s]
                    direction = bearing(inlet_e[j] - centre_e, inlet_n[j] - centre_n)
                    candidates.append(dict(stop=int(stop), photo_ids=" ".join(members["photo_id"]), rank=rank, inlet_id=s, grates=grates[s],
                                           road_name=head.at[s, "road_name"], owner_type=head.at[s, "owner_type"], distance_m=round(distance[s], 1),
                                           bearing=round(direction, 0), off_heading=off_heading(direction, heading)))
        for k in index:
            row = dict(decided, photo_id=captures["photo_id"].iloc[k], stop=int(stop), h_error_m=captures["h_error_m"].iloc[k] if "h_error_m" in captures else None)
            chosen = forced.get(row["photo_id"])
            if chosen is not None:
                reach = None
                if chosen != NO_INLET and np.isfinite(east[k]):
                    of_site = np.flatnonzero(site == chosen)
                    reach = round(float(np.hypot(east[k] - inlet_e[of_site], north[k] - inlet_n[of_site]).min()), 1)
                row.update(inlet_id=chosen, grates=grates.get(chosen), method="override", runner_up_id="", runner_up_m=None, ratio=None, distance_m=reach)
            rows.append(row)
    decisions = pd.DataFrame(rows, columns=MATCH_COLUMNS)
    still_open = set(decisions.loc[decisions["method"].isin(["ambiguous", "far"]), "stop"])
    open_candidates = pd.DataFrame([c for c in candidates if c["stop"] in still_open], columns=CANDIDATE_COLUMNS)
    return decisions, open_candidates


def missing_inlets(decisions, captures):
    """The positions of photographed inlets that the layer does not hold, a finding for the town. Rounded to five
    decimals, about a metre, and without a time, so that the row says where a drain is and not when anyone stood there."""
    none = decisions[decisions["inlet_id"] == NO_INLET].merge(captures[["photo_id", "lon", "lat"]], on="photo_id")
    return pd.DataFrame({"photo_id": none["photo_id"], "lon": none["lon"].astype(float).round(5), "lat": none["lat"].astype(float).round(5)})


def draw_sheets(captures, inlets, candidates, folder=None, span_m=60.0):
    """One sheet per open stop with its photographs beside a small map of the candidates. Returns the paths."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import pyogrio
    from PIL import Image

    from igo import LAYER

    folder = folder or SHEETS
    folder.mkdir(parents=True, exist_ok=True)
    roads = []
    for line in pyogrio.read_dataframe(LAYER, layer="roads").geometry.explode():
        xs, ys = np.asarray(line.coords).T[:2]
        roads.append(geo.metres(*geo.native_to_wgs84(xs, ys)))
    inlet_e, inlet_n = geo.metres(inlets["lon"].to_numpy(), inlets["lat"].to_numpy())
    captures = captures.assign(stop=stops(captures.reset_index(drop=True)))
    written = []
    for stop, rows in candidates.groupby("stop", sort=True):
        shots = captures[captures["stop"] == stop]
        east, north = geo.metres(shots["lon"].to_numpy(dtype=float), shots["lat"].to_numpy(dtype=float))
        ce, cn = float(east.mean()), float(north.mean())
        fig, axes = plt.subplots(1, len(shots) + 1, figsize=(4.4 * len(shots) + 7.2, 7.4), gridspec_kw=dict(width_ratios=[1] * len(shots) + [1.55]))
        for ax, shot in zip(axes[:-1], shots.itertuples(index=False)):
            picture = CONVERTED / f"{shot.photo_id}.jpg"
            if picture.exists():
                with Image.open(picture) as image:
                    image.thumbnail((900, 900))
                    ax.imshow(image)
            heading = "no heading" if pd.isna(shot.heading) else f"camera faced {shot.heading:.0f} degrees"
            ax.set_title(f"{shot.photo_id}\n{heading}, fix good to {shot.h_error_m} m", fontsize=9)
            ax.set_axis_off()
        ax = axes[-1]
        half = span_m / 2
        for re, rn in roads:
            if ((np.abs(re - ce) < span_m * 2) & (np.abs(rn - cn) < span_m * 2)).any():
                ax.plot(re - ce, rn - cn, color="#bbbbbb", linewidth=6, solid_capstyle="round", zorder=1)
        near = (np.abs(inlet_e - ce) < half) & (np.abs(inlet_n - cn) < half)
        ax.scatter(inlet_e[near] - ce, inlet_n[near] - cn, s=60, color="white", edgecolor="#444444", zorder=3)
        for r in rows.itertuples(index=False):
            for j in np.flatnonzero(inlets["site"].to_numpy() == r.inlet_id):       # every grate of the site carries its number
                if abs(inlet_e[j] - ce) > half or abs(inlet_n[j] - cn) > half:
                    continue                                                        # too far for this map, the list above still names it
                ax.scatter([inlet_e[j] - ce], [inlet_n[j] - cn], s=300, color="#e77500", edgecolor="black", zorder=4)
                ax.text(inlet_e[j] - ce, inlet_n[j] - cn, str(r.rank), ha="center", va="center", fontsize=10, weight="bold", zorder=5, clip_on=True)
        for e, n, shot in zip(east, north, shots.itertuples(index=False)):
            if not pd.isna(shot.h_error_m):
                ax.add_patch(plt.Circle((e - ce, n - cn), float(shot.h_error_m), color="#1f77b4", alpha=0.15, zorder=2))
            ax.scatter([e - ce], [n - cn], s=40, color="#1f77b4", zorder=6)
            if not pd.isna(shot.heading):
                rad = np.radians(float(shot.heading))
                ax.annotate("", xy=(e - ce + 7 * np.sin(rad), n - cn + 7 * np.cos(rad)), xytext=(e - ce, n - cn),
                            arrowprops=dict(arrowstyle="->", color="#1f77b4", linewidth=1.8), zorder=6)
        ax.set_xlim(-half, half)
        ax.set_ylim(-half, half)
        ax.set_aspect("equal")
        ax.set_xlabel("metres east of the phone")
        ax.set_ylabel("metres north of the phone")
        lines = [f"{r.rank}  {r.inlet_id}  {r.road_name or 'no road name'}, {r.owner_type}, {'one grate' if r.grates == 1 else f'{r.grates} grates in a row'}, {r.distance_m} m"
                 + ("" if r.off_heading is None or pd.isna(r.off_heading) else f", {r.off_heading:.0f} degrees off the heading")
                 + (", not on this map" if r.distance_m > half else "") for r in rows.itertuples(index=False)]
        ax.set_title("\n".join(lines), fontsize=8.5, loc="left")
        fig.suptitle(f"Stop {int(stop)}. Which drain is in the picture? North is up, the blue dot is the phone with its accuracy, the arrow is the way the camera faced.",
                     fontsize=10.5, x=0.012, y=0.985, ha="left")
        fig.subplots_adjust(left=0.012, right=0.985, top=0.86, bottom=0.08, wspace=0.12)
        path = folder / f"match_stop_{int(stop):03d}.jpg"
        fig.savefig(path, dpi=110)
        plt.close(fig)
        written.append(path)
    return written


def main(argv=None):
    parser = argparse.ArgumentParser(description="Which inlet a photograph shows.")
    parser.add_argument("--sheets", action="store_true", help="draw a sheet for every stop that needs a decision")
    args = parser.parse_args(argv)
    if not CAPTURES.exists():
        print("data/private/captures.csv does not exist, run make convert first")
        return 1
    captures = pd.read_csv(CAPTURES, dtype={"photo_id": str, "captured_at": str})
    inlets = read_inlets()
    decisions, candidates = match(captures, inlets)
    decisions.to_csv(MATCHES, index=False, lineterminator="\n")
    candidates.to_csv(AMBIGUOUS, index=False, lineterminator="\n")
    gone = missing_inlets(decisions, captures)
    if len(gone) or MISSING.exists():
        gone.to_csv(MISSING, index=False, lineterminator="\n")
    roads = inlets.set_index("inlet_id")["road_name"]
    for r in decisions.itertuples(index=False):
        where = f"{r.inlet_id} on {roads.get(r.inlet_id, '') or 'no road name'}" if r.inlet_id and r.inlet_id != NO_INLET else "no inlet yet"
        where += f", {int(r.grates)} grates in a row" if not pd.isna(r.grates) and r.grates > 1 else ""
        detail = "" if pd.isna(r.distance_m) else f", {r.distance_m} m" + ("" if pd.isna(r.runner_up_m) else f", then {r.runner_up_m} m")
        print(f"{r.photo_id}  stop {r.stop:3d}  {r.method:9s}  {where}{detail}")
    counts = decisions["method"].value_counts().to_dict()
    print(", ".join(f"{v} {k}" for k, v in counts.items()), f"of {len(decisions)} captures")
    open_stops = sorted(candidates["stop"].unique()) if len(candidates) else []
    if open_stops:
        print(f"{len(open_stops)} stops need a decision in data/inlets/overrides.csv, their candidates are in data/private/ambiguous.csv")
    if args.sheets and open_stops:
        for path in draw_sheets(captures, inlets, candidates):
            print("drew", path.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
