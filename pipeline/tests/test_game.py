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
    assert {c["species"] for c in cases["species_cases"]} >= {s["id"] for s in game.read(game.SPECIES)["species"]}


def test_a_wrong_expectation_is_reported():
    """The negative control of the replay. A case with a changed expectation must be named."""
    cases = copy.deepcopy(game.read(game.CASES))
    cases["tier_cases"][0]["tier"] = 1
    cases["points_cases"][3]["points"] = 99
    cases["species_cases"][0]["species"] = "leaf_sprite"
    wrong = game.replay(cases)
    assert len(wrong) == 3 and "never reported" in wrong[0]


def test_the_hash_is_the_md5_any_tool_computes():
    """The digest below was printed by the md5 command of macOS for the same text."""
    assert int("4d3bb34d", 16) % 2 == 1
    assert game.hash_index("in0742|2026-11-10|3|base", 2) == 1
    assert game.hash_index("in0742|2026-11-10|3|base", 2**32) == int("4d3bb34d", 16)


def test_the_tier_follows_elapsed_time_between_the_boundaries():
    rules = game.read(game.RULES)
    now = datetime(2026, 11, 10, 20, 0, tzinfo=timezone.utc)
    seen = [game.spawn_tier(now, now - timedelta(hours=h), None, False, rules) for h in range(0, 24 * 20, 6)]
    assert seen == sorted(seen), "an older last report never lowers the tier"
    assert seen[0] == 1 and seen[-1] == 3
    assert seen.index(2) == 3 * 4 and seen.index(3) == 14 * 4


def test_points_grow_with_the_tier_and_the_bonus_skips_resting_drains():
    rules = game.read(game.RULES)
    plain = [game.points(t, False, rules) for t in range(4)]
    great = [game.points(t, True, rules) for t in range(4)]
    assert plain == [2, 10, 20, 30] and great == [2, 15, 25, 35]


def test_a_storm_draws_from_the_storm_pool_and_falls_back_where_it_is_empty():
    species = game.read(game.SPECIES)["species"]
    storm = {s["id"] for s in species if s["pool"] == "storm"}
    base = {s["id"] for s in species if s["pool"] == "base"}
    drawn = {game.species_for(f"in{k:04d}", "2026-11-10", 3, True, species) for k in range(1, 60)}
    assert drawn == storm
    assert {game.species_for(f"in{k:04d}", "2026-11-10", 2, True, species) for k in range(1, 60)} <= base
    assert game.species_for("in0001", "2026-11-10", 0, True, species) is None


def test_every_species_of_a_tier_turns_up():
    species = game.read(game.SPECIES)["species"]
    for tier in (1, 2, 3):
        pool = {s["id"] for s in species if s["tier"] == tier and s["pool"] == "base"}
        drawn = {game.species_for(f"in{k:04d}", "2026-11-10", tier, False, species) for k in range(1, 200)}
        assert drawn == pool


def test_the_species_of_a_drain_changes_with_the_day_but_not_within_it():
    species = game.read(game.SPECIES)["species"]
    days = [f"2026-11-{d:02d}" for d in range(1, 31)]
    over_the_month = {game.species_for("in2167", day, 1, False, species) for day in days}
    assert len(over_the_month) == 2
    assert game.species_for("in2167", "2026-11-10", 1, False, species) == game.species_for("in2167", "2026-11-10", 1, False, species)


@pytest.mark.parametrize("change, expected", [
    (lambda rules, species, gear: species[0].update(name="Water - Strider"), "dash as punctuation"),
    (lambda rules, species, gear: species[1].update(id="water_strider"), "share an id"),
    (lambda rules, species, gear: species[2].update(fact_id="not_a_fact"), "is not in facts.json"),
    (lambda rules, species, gear: species[3].update(model="turtle.usdz"), "without a credit line"),
    (lambda rules, species, gear: [s.update(tier=3) for s in species if s["tier"] == 2], "Tier 2 has no species"),
    (lambda rules, species, gear: rules["tiers"][2].update(points=5), "points must grow"),
    (lambda rules, species, gear: rules["fence"].update(server_max_distance_m=10), "outside the fence"),
    (lambda rules, species, gear: rules["great_catch"].update(ring_scale_max=0.2), "must be reachable"),
    (lambda rules, species, gear: gear["levels"][3].update(points=50), "more points than the one before"),
    (lambda rules, species, gear: gear["levels"][2].update(gear="hard_hat"), "exactly one level"),
])
def test_spoiled_data_files_are_refused(tmp_path, monkeypatch, change, expected):
    """The negative controls of the data check. Each spoiled copy must be refused for its own reason."""
    rules, species_file, gear = game.read(game.RULES), game.read(game.SPECIES), game.read(game.GEAR)
    change(rules, species_file["species"], gear)
    for name, content in (("RULES", rules), ("SPECIES", species_file), ("GEAR", gear)):
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
