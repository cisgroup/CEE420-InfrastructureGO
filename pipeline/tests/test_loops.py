"""The walk of an outing. The drains are the real ones, the walks are checked for what a walk must be."""

import numpy as np
import pytest

from igo import geo, loops, match, zones


@pytest.fixture(scope="module")
def candidates():
    return loops.sites(match.read_inlets(), zones.read_zones(), zone="west")


def test_candidates_are_the_sites_of_the_game(candidates, derived):
    assert len(candidates) == derived.summary["zones"]["west"]["playable_sites"]
    assert (candidates["inlet_id"] == candidates["site"]).all()
    assert set(candidates["owner_type"]) <= {"Municipality", "County", "State", "Other Municipality"}
    row = candidates[candidates["inlet_id"] == "in1342"].iloc[0]
    assert row["grates"] == 3


def test_every_owner_can_be_asked_for(derived):
    everyone = loops.sites(match.read_inlets(), zones.read_zones(), zone="west", all_owners=True)
    assert len(everyone) == derived.summary["zones"]["west"]["sites"]


def test_a_loop_visits_each_of_its_drains_once(candidates):
    walk, metres = loops.plan(candidates, start=(40.356792, -74.672675), count=30)
    assert len(walk) == 30 and walk["inlet_id"].is_unique
    assert walk["stop"].tolist() == list(range(1, 31))
    assert walk["from_previous_m"].iloc[0] == 0 and (walk["from_previous_m"].iloc[1:] > 0).all()
    xy = walk[["east", "north"]].to_numpy()
    assert metres == pytest.approx(loops.length(xy, range(30)), rel=1e-9)
    assert 500 < metres < 4000


def test_the_loop_takes_the_drains_nearest_to_the_start(candidates):
    start = (40.356792, -74.672675)
    walk, _ = loops.plan(candidates, start=start, count=20)
    origin = np.array([float(v) for v in geo.metres(start[1], start[0])])
    reach = np.hypot(*(candidates[["east", "north"]].to_numpy() - origin).T)
    assert set(walk["inlet_id"]) == set(candidates.iloc[np.argsort(reach, kind="stable")[:20]]["inlet_id"])
    first = walk.iloc[0]
    assert np.hypot(first["east"] - origin[0], first["north"] - origin[1]) == pytest.approx(reach.min())


def test_untangling_never_lengthens_a_walk(candidates):
    xy = candidates[["east", "north"]].to_numpy()[:40]
    greedy = loops.nearest_first(xy, 0)
    better = loops.untangled(xy, greedy)
    assert sorted(better) == list(range(40)) and better[0] == greedy[0]
    assert loops.length(xy, better) <= loops.length(xy, greedy) + 1e-9
    rng = np.random.default_rng(5)
    shuffled = [0] + list(rng.permutation(np.arange(1, 40)))
    fixed = loops.untangled(xy, shuffled)
    assert loops.length(xy, fixed) < 0.7 * loops.length(xy, shuffled), "a random order has crossings to take out"


def test_a_square_is_walked_around_and_not_across():
    xy = np.array([[0.0, 0.0], [100.0, 100.0], [100.0, 0.0], [0.0, 100.0]])
    order = loops.untangled(xy, [0, 1, 2, 3])
    assert loops.length(xy, order) == pytest.approx(400.0)
    assert loops.length(xy, [0, 1, 2, 3]) > 400.0


def test_the_same_question_gives_the_same_loop(candidates):
    a, _ = loops.plan(candidates, start=(40.3545, -74.6725), count=25)
    b, _ = loops.plan(candidates.sample(frac=1.0, random_state=3), start=(40.3545, -74.6725), count=25)
    assert a["inlet_id"].tolist() == b["inlet_id"].tolist()


def test_roads_can_be_asked_for_by_name():
    two = loops.sites(match.read_inlets(), zones.read_zones(), roads=["pardoe road", "Wilson Road"])
    assert set(two["road_name"]) == {"Pardoe Road", "Wilson Road"}
    walk, _ = loops.plan(two, count=100)
    assert len(walk) == len(two)


def test_a_loop_shorter_than_asked_takes_what_there_is(candidates):
    walk, _ = loops.plan(candidates.iloc[:3], count=35)
    assert len(walk) == 3
    one, metres = loops.plan(candidates.iloc[:1], count=35)
    assert len(one) == 1 and metres == 0.0


def test_nothing_to_walk_is_said_plainly(candidates):
    with pytest.raises(ValueError, match="No drain fits"):
        loops.plan(candidates.iloc[:0])


def test_the_loop_is_written_for_a_map_and_drawn(candidates, tmp_path):
    walk, metres = loops.plan(candidates, start=(40.356792, -74.672675), count=12)
    shape = loops.geojson(walk, metres)
    line = shape["features"][0]["geometry"]["coordinates"]
    assert len(line) == 13 and line[0] == line[-1], "the line comes back to its start"
    assert [f["properties"]["stop"] for f in shape["features"][1:]] == list(range(1, 13))
    picture = loops.draw(walk, tmp_path / "loop.png", "a loop")
    assert picture.stat().st_size > 20_000
