"""The rules of the game in Python, the shared cases and the game's data files."""

import copy
import json
from datetime import datetime, timedelta, timezone

import pytest

from igo import facts, game


def test_the_data_files_are_sound():
    assert game.data_problems() == []


def test_the_shared_cases_come_out_as_expected():
    assert game.replay() == []


def test_the_cases_cover_every_tier_and_both_sides_of_each_boundary():
    cases = game.read(game.CASES)
    assert {c["tier"] for c in cases["tier_cases"]} == {0, 1, 2, 3}
    names = " ".join(c["name"] for c in cases["tier_cases"])
    for needed in ("exactly 14 days", "short of 14 days", "exactly 3 days", "short of 3 days", "UTC midnight", "clocks go back", "storm window"):
        assert needed in names, f"no case about {needed}"
    assert len(cases["points_cases"]) == 8


def test_a_wrong_expectation_is_reported():
    """The negative control of the replay. A case with a changed expectation must be named."""
    cases = copy.deepcopy(game.read(game.CASES))
    cases["tier_cases"][0]["tier"] = 1
    cases["points_cases"][3]["points"] = 99
    wrong = game.replay(cases)
    assert len(wrong) == 2 and "never reported" in wrong[0]


def test_the_hash_is_the_md5_any_tool_computes():
    """The digest below was printed by the md5 command of macOS for the same text. The app draws its lots with it."""
    assert game.hash_index("in0742|2026-11-10|3|base", 2) == 1
    assert game.hash_index("in0742|2026-11-10|3|base", 2**32) == int("4d3bb34d", 16)


def test_the_tier_follows_elapsed_time_between_the_boundaries():
    rules = game.read(game.RULES)
    now = datetime(2026, 11, 10, 20, 0, tzinfo=timezone.utc)
    seen = [game.spawn_tier(now, now - timedelta(hours=h), None, False, rules) for h in range(0, 24 * 20, 6)]
    assert seen == sorted(seen), "an older last look never lowers the need"
    assert seen[0] == 1 and seen[-1] == 3
    assert seen.index(2) == 3 * 4 and seen.index(3) == 14 * 4


def test_points_grow_with_the_tier_and_the_bonus_skips_resting_drains():
    rules = game.read(game.RULES)
    plain = [game.points(t, False, rules) for t in range(4)]
    great = [game.points(t, True, rules) for t in range(4)]
    assert plain == [2, 10, 20, 30] and great == [2, 15, 25, 35]


def test_a_keeper_that_is_mostly_away_is_not_a_fair_throw():
    frog = game.read(game.KEEPERS)["keepers"][0]["timing"]
    assert game.sitting_share(frog) > 0.8
    assert game.sitting_share(dict(frog, air_s=3.0)) < 0.6
    assert game.sitting_share(dict(frog, hide_every=1, hide_s=4.0)) < 0.6


def spoil(files, name, change):
    change(files[name])


@pytest.mark.parametrize("name, change, expected", [
    ("KEEPERS", lambda d: d["keepers"][0].update(name="Tree - Frog"), "dash as punctuation"),
    ("KEEPERS", lambda d: d["keepers"].append(dict(d["keepers"][0])), "share an id"),
    ("KEEPERS", lambda d: d["keepers"][0].update(kind="rare"), "must be a common one"),
    ("KEEPERS", lambda d: d["keepers"][0].update(kind="dragon"), "unknown kind"),
    ("KEEPERS", lambda d: d["keepers"][0].update(credit=""), "no credit line"),
    ("KEEPERS", lambda d: d["keepers"][0]["clips"].pop("refuse"), "no movement for refuse"),
    ("KEEPERS", lambda d: d["keepers"][0]["clips"].update(idle="sleep"), "frog_sleep.usdz is not in Resources/Models"),
    ("KEEPERS", lambda d: d["keepers"][0]["timing"].update(air_s=4.0), "too much of the time"),
    ("RULES", lambda d: d["tiers"][2].update(points=5), "points must grow"),
    ("RULES", lambda d: d["fence"].update(server_max_distance_m=10), "outside the fence"),
    ("WORLD", lambda d: d["kinds"].update(common=70), "add up to a hundred"),
    ("WORLD", lambda d: d.update(crate_parts=[0, 3, 2, 1]), "never less at a drain with a higher need"),
    ("WORLD", lambda d: d.update(rungs=[1, 3, 3, 15]), "growing numbers of meetings"),
    ("WORLD", lambda d: d["slip"].update(min_m=10), "wait outside the fence"),
    ("GEAR", lambda d: d["levels"][3].update(points=50), "more points than the one before"),
    ("GEAR", lambda d: d["pieces"][2].update(parts=1), "cost less than the one before"),
    ("GEAR", lambda d: d["pieces"][2].update(opens="wide_veil"), "open the same thing"),
    ("JOBS", lambda d: d["jobs"][0].update(kind="dance"), "unknown kind"),
    ("JOBS", lambda d: d["jobs"].append(dict(d["jobs"][0])), "Two jobs share an id"),
])
def test_spoiled_data_files_are_refused(tmp_path, monkeypatch, name, change, expected):
    """The negative controls of the data check. Each spoiled copy must be refused for its own reason."""
    content = game.read(getattr(game, name))
    change(content)
    path = tmp_path / f"{name.lower()}.json"
    path.write_text(json.dumps(content))
    monkeypatch.setattr(game, name, path)
    assert expected in " ".join(game.data_problems())


def test_fact_cards_are_rendered_from_the_summary():
    assert facts.main(["--check"]) == 0
    summary = json.loads(facts.SUMMARY_JSON.read_text())
    cards = {f["id"]: f for f in json.loads(facts.FACTS_JSON.read_text())["facts"]}
    assert f"{summary['inlets']:,}" in cards["drains_on_the_map"]["text"]
    assert f"{summary['by_owner']['Municipality']:,}" in cards["who_owns_them"]["text"]
    assert all(f["source"] and f["retrieved"] for f in cards.values())


def test_a_changed_summary_makes_the_fact_check_fail(tmp_path, monkeypatch):
    """The negative control of the fact check. Another count in the summary means the committed cards are stale."""
    summary = json.loads(facts.SUMMARY_JSON.read_text())
    summary["inlets"] += 1
    changed = tmp_path / "summary.json"
    changed.write_text(json.dumps(summary))
    monkeypatch.setattr(facts, "SUMMARY_JSON", changed)
    assert facts.main(["--check"]) == 1
