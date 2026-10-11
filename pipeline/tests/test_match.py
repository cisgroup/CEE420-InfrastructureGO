"""Which inlet a photograph shows. The captures are made up and placed beside real inlets of the committed table."""

import numpy as np
import pandas as pd
import pytest
from scipy.spatial import cKDTree

from igo import geo, match


@pytest.fixture(scope="module")
def inlets():
    return match.read_inlets()


@pytest.fixture(scope="module")
def sites(inlets):
    """One row per site of a single grate, with its position in metres and the distance to the nearest other site."""
    table = inlets.assign(grates=inlets.groupby("site")["inlet_id"].transform("size"))
    east, north = geo.metres(table["lon"].to_numpy(), table["lat"].to_numpy())
    table = table.assign(east=east, north=north)
    xy = np.c_[east, north]
    distance, index = cKDTree(xy).query(xy, k=3)
    table = table.assign(nearest_m=distance[:, 1], nearest=table["inlet_id"].to_numpy()[index[:, 1]], second_m=distance[:, 2])
    return table[table["grates"] == 1].reset_index(drop=True)


def capture(photo_id, east, north, at="2026-10-17T10:00:00-04:00", heading=90.0):
    lon, lat = geo.lonlat(east, north)
    return dict(photo_id=photo_id, captured_at=at, lon=float(lon), lat=float(lat), h_error_m=3.5, heading=heading)


def frame(*rows):
    return pd.DataFrame(list(rows))


NOBODY = pd.DataFrame(columns=match.OVERRIDE_COLUMNS)


def test_a_fix_beside_a_lone_drain_is_matched(inlets, sites):
    lone = sites[sites["nearest_m"] > 40].iloc[0]
    decisions, candidates = match.match(frame(capture("p00001", lone.east + 5, lone.north)), inlets, NOBODY)
    row = decisions.iloc[0]
    assert row["method"] == "nearest" and row["inlet_id"] == lone.inlet_id and row["distance_m"] == 5.0 and row["grates"] == 1
    assert candidates.empty


def test_a_row_of_grates_is_one_drain(inlets):
    """Beside the three grates on Pardoe Road the nearest three points are one site, so there is nothing to choose."""
    third = inlets[inlets["inlet_id"] == "in1344"].iloc[0]
    east, north = geo.metres(third["lon"], third["lat"])
    decisions, candidates = match.match(frame(capture("p00001", float(east) + 2, float(north) + 1)), inlets, NOBODY)
    row = decisions.iloc[0]
    assert row["method"] == "nearest" and row["inlet_id"] == "in1342" and row["grates"] == 3
    assert row["runner_up_id"] not in ("in1342", "in1343", "in1344") and row["runner_up_m"] > 5
    assert candidates.empty


def pair(sites):
    """Two single grates about ten metres apart with nothing else near, the usual pair on opposite kerbs."""
    alone = sites[(sites["nearest_m"].between(8, 12)) & (sites["second_m"] > 40)]
    a = alone.iloc[0]
    b = sites[sites["inlet_id"] == a.nearest].iloc[0]
    return a, b


def test_between_two_drains_is_ambiguous(inlets, sites):
    a, b = pair(sites)
    decisions, candidates = match.match(frame(capture("p00001", (a.east + b.east) / 2, (a.north + b.north) / 2)), inlets, NOBODY)
    row = decisions.iloc[0]
    assert row["method"] == "ambiguous" and row["inlet_id"] == ""
    assert candidates["rank"].tolist() == [1, 2, 3] and set(candidates["inlet_id"].iloc[:2]) == {a.inlet_id, b.inlet_id}
    assert candidates["distance_m"].iloc[0] == pytest.approx(a.nearest_m / 2, abs=0.11)
    assert set(candidates["photo_ids"]) == {"p00001"}


@pytest.mark.parametrize("share, method", [(0.38, "nearest"), (0.42, "ambiguous")])
def test_the_runner_up_must_be_half_again_as_far(inlets, sites, share, method):
    a, b = pair(sites)
    at = capture("p00001", a.east + share * (b.east - a.east), a.north + share * (b.north - a.north))
    decisions, _ = match.match(frame(at), inlets, NOBODY)
    assert decisions.iloc[0]["method"] == method
    assert decisions.iloc[0]["inlet_id"] == (a.inlet_id if method == "nearest" else "")
    assert decisions.iloc[0]["ratio"] == pytest.approx((1 - share) / share, abs=0.03)


def test_a_fix_far_from_every_drain_is_not_matched(inlets, sites):
    lone = sites[sites["nearest_m"] > 80].iloc[0]
    decisions, candidates = match.match(frame(capture("p00001", lone.east + 30, lone.north)), inlets, NOBODY)
    assert decisions.iloc[0]["method"] == "far" and decisions.iloc[0]["inlet_id"] == "" and decisions.iloc[0]["distance_m"] == 30.0
    assert candidates.iloc[0]["inlet_id"] == lone.inlet_id, "the far drain is still offered, with its distance"


def test_the_edge_of_reach(inlets, sites):
    lone = sites[sites["nearest_m"] > 80].iloc[0]
    inside, _ = match.match(frame(capture("p00001", lone.east + match.MATCH_MAX_M - 0.2, lone.north)), inlets, NOBODY)
    outside, _ = match.match(frame(capture("p00001", lone.east + match.MATCH_MAX_M + 0.2, lone.north)), inlets, NOBODY)
    assert inside.iloc[0]["method"] == "nearest" and outside.iloc[0]["method"] == "far"


def test_a_capture_without_a_position_is_unplaced(inlets):
    row = dict(photo_id="p00001", captured_at="2026-10-17T10:00:00-04:00", lon=np.nan, lat=np.nan, h_error_m=np.nan, heading=np.nan)
    decisions, candidates = match.match(frame(row), inlets, NOBODY)
    assert decisions.iloc[0]["method"] == "unplaced" and decisions.iloc[0]["inlet_id"] == "" and candidates.empty


def test_an_override_decides_and_names_the_site(inlets, sites):
    a, b = pair(sites)
    middle = capture("p00001", (a.east + b.east) / 2, (a.north + b.north) / 2)
    chosen = pd.DataFrame([dict(photo_id="p00001", inlet_id=b.inlet_id, reason="the far kerb")])
    decisions, candidates = match.match(frame(middle), inlets, chosen)
    assert decisions.iloc[0]["method"] == "override" and decisions.iloc[0]["inlet_id"] == b.inlet_id
    assert decisions.iloc[0]["distance_m"] == pytest.approx(a.nearest_m / 2, abs=0.11)
    assert candidates.empty, "a decided stop asks nothing more"
    grate = pd.DataFrame([dict(photo_id="p00001", inlet_id="in1344", reason="the last grate of the row")])
    decisions, _ = match.match(frame(middle), inlets, grate)
    assert decisions.iloc[0]["inlet_id"] == "in1342" and decisions.iloc[0]["grates"] == 3, "any grate of a row names the row"


def test_an_override_can_say_the_drain_is_not_on_the_map(inlets, sites):
    lone = sites[sites["nearest_m"] > 80].iloc[0]
    shot = capture("p00001", lone.east + 30, lone.north)
    none = pd.DataFrame([dict(photo_id="p00001", inlet_id=match.NO_INLET, reason="a drain the layer does not hold")])
    decisions, candidates = match.match(frame(shot), inlets, none)
    assert decisions.iloc[0]["inlet_id"] == "none" and decisions.iloc[0]["method"] == "override" and candidates.empty
    gone = match.missing_inlets(decisions, frame(shot))
    assert list(gone.columns) == ["photo_id", "lon", "lat"], "a missing drain is a place and nothing more, no time"
    assert gone.iloc[0]["lon"] == round(shot["lon"], 5) and gone.iloc[0]["lat"] == round(shot["lat"], 5)


def test_an_override_for_an_inlet_that_does_not_exist_is_refused(inlets, sites):
    lone = sites.iloc[0]
    wrong = pd.DataFrame([dict(photo_id="p00001", inlet_id="in9999", reason="a slip of the finger")])
    with pytest.raises(ValueError, match="in9999"):
        match.match(frame(capture("p00001", lone.east, lone.north)), inlets, wrong)


def test_two_shots_of_one_stop_are_matched_together(inlets, sites):
    """Alone the second shot is ambiguous. With the first shot of the same stop the two fixes settle it."""
    a, b = pair(sites)
    unit = np.array([b.east - a.east, b.north - a.north]) / a.nearest_m
    first = capture("p00001", *(np.array([a.east, a.north]) + 1.0 * unit), at="2026-10-17T10:00:00-04:00")
    second = capture("p00002", *(np.array([a.east, a.north]) + 4.5 * unit), at="2026-10-17T10:00:04-04:00")
    alone, _ = match.match(frame(second), inlets, NOBODY)
    assert alone.iloc[0]["method"] == "ambiguous"
    together, candidates = match.match(frame(first, second), inlets, NOBODY)
    assert together["stop"].tolist() == [1, 1]
    assert together["method"].tolist() == ["nearest", "nearest"] and set(together["inlet_id"]) == {a.inlet_id}
    assert together["distance_m"].iloc[0] == pytest.approx(2.75, abs=0.06), "the distance is the mean over the stop's fixes"
    assert candidates.empty


@pytest.mark.parametrize("seconds, metres, same", [(3, 2.0, True), (14, 4.5, True), (16, 2.0, False), (3, 7.0, False)])
def test_what_counts_as_one_stop(seconds, metres, same):
    first = capture("p00001", 520000.0, 4467000.0, at="2026-10-17T10:00:00-04:00")
    second = capture("p00002", 520000.0 + metres, 4467000.0, at=f"2026-10-17T10:00:{seconds:02d}-04:00")
    got = match.stops(frame(first, second))
    assert bool(got[0] == got[1]) is same
    assert got.min() == 1


def test_stops_follow_the_time_and_not_the_order_of_the_rows():
    a = capture("p00001", 520000.0, 4467000.0, at="2026-10-17T10:00:00-04:00")
    b = capture("p00002", 520000.0 + 1, 4467000.0, at="2026-10-17T10:00:02-04:00")
    c = capture("p00003", 520000.0 + 60, 4467000.0, at="2026-10-17T10:02:00-04:00")
    assert match.stops(frame(c, a, b)).tolist() == [2, 1, 1]
    no_time = dict(a, photo_id="p00004", captured_at=None)
    assert match.stops(frame(a, no_time, b)).tolist() == [1, 2, 1], "a shot without a time is a stop of its own, taken last"


def test_the_direction_to_a_candidate_and_the_cameras_heading(inlets, sites):
    lone = sites[sites["nearest_m"] > 80].iloc[0]
    shot = capture("p00001", lone.east - 30, lone.north, heading=90.0)       # the drain lies due east and the camera faced east
    _, candidates = match.match(frame(shot), inlets, NOBODY)
    assert candidates.iloc[0]["bearing"] == pytest.approx(90, abs=1) and candidates.iloc[0]["off_heading"] == pytest.approx(0, abs=1)
    assert match.off_heading(350.0, 10.0) == 20 and match.off_heading(10.0, 350.0) == 20 and match.off_heading(180.0, 0.0) == 180
    assert match.off_heading(90.0, None) is None and match.off_heading(90.0, float("nan")) is None
    assert match.bearing(0, 1) == 0 and match.bearing(1, 0) == 90 and match.bearing(0, -1) == 180 and match.bearing(-1, 0) == 270


def test_a_sheet_is_drawn_for_an_open_stop(inlets, sites, tmp_path):
    a, b = pair(sites)
    shots = frame(capture("p00001", (a.east + b.east) / 2, (a.north + b.north) / 2))
    _, candidates = match.match(shots, inlets, NOBODY)
    written = match.draw_sheets(shots, inlets, candidates, folder=tmp_path)
    assert [p.name for p in written] == ["match_stop_001.jpg"] and written[0].stat().st_size > 20_000
