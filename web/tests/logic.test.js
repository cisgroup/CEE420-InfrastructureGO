// The reasoning of the town's map, checked against the very files the page loads and against the counts the
// pipeline wrote, so that the page, the app and the pipeline cannot count differently.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import * as logic from "../logic.js";

const read = (path) => JSON.parse(readFileSync(new URL(path, import.meta.url), "utf8"));
const inlets = read("../data/inlets.geojson");
const zones = read("../data/zones.geojson");
const summary = read("../../data/inlets/summary.json");

test("the day is the one in New York", () => {
  assert.equal(logic.todayInNewYork(new Date("2026-11-11T04:59:59Z")), "2026-11-10");
  assert.equal(logic.todayInNewYork(new Date("2026-11-11T05:00:00Z")), "2026-11-11");
  assert.equal(logic.todayInNewYork(new Date("2026-07-04T03:59:59Z")), "2026-07-03");
  assert.match(logic.todayInNewYork(), /^\d{4}-\d{2}-\d{2}$/);
});

test("a day must be written yyyy-mm-dd and exist", () => {
  assert.equal(logic.isDay("2026-10-12"), true);
  for (const wrong of ["2026-13-01", "2026-02-30", "12.10.2026", "", null, 20261012, "2026-10-12T00:00:00"]) assert.equal(logic.isDay(wrong), false);
});

test("a zone is on from its first day to its last", () => {
  const zone = { active_from: "2026-10-12", active_to: "2026-12-07" };
  assert.deepEqual(["2026-10-11", "2026-10-12", "2026-12-07", "2026-12-08"].map((d) => logic.zoneIsActive(zone, d)), [false, true, true, false]);
  assert.equal(logic.zoneIsActive({ active_from: "2026-10-12", active_to: null }, "2031-01-01"), true);
});

test("the page counts drains the way the pipeline did", () => {
  const rows = logic.zoneCounts(inlets, zones, "2026-10-12");
  assert.deepEqual(rows.map((r) => r.id), Object.keys(summary.zones));
  for (const row of rows) {
    assert.equal(row.inlets, summary.zones[row.id].inlets, `inlets in ${row.id}`);
    assert.equal(row.drains, summary.zones[row.id].sites, `sites in ${row.id}`);
    assert.equal(row.catchable, summary.zones[row.id].playable_sites, `catchable sites in ${row.id}`);
    assert.equal(row.active, true);
  }
  assert.equal(inlets.features.length, summary.inlets);
});

test("nothing can be caught the day before the zones open", () => {
  const rows = logic.zoneCounts(inlets, zones, "2026-10-11");
  assert.ok(rows.every((r) => r.catchable === 0 && r.active === false && r.drains > 0));
});

test("the prepared features carry what the map paints by", () => {
  const ready = logic.prepared(inlets, zones, "2026-10-12");
  assert.equal(ready.features.length, inlets.features.length);
  assert.equal(ready.features.filter((f) => f.properties.head).length, summary.sites);
  assert.equal(ready.features.filter((f) => f.properties.head && f.properties.catchable).length, summary.playable_sites);
  assert.equal(ready.features.filter((f) => f.properties.catchable).length, summary.playable);
  const row = ready.features.filter((f) => f.properties.site === "in1342");
  assert.deepEqual(row.map((f) => [f.properties.id, f.properties.head, f.properties.grates]), [["in1342", true, 3], ["in1343", false, 3], ["in1344", false, 3]]);
  assert.equal(inlets.features[0].properties.head, undefined, "the loaded file is left as it was");
});

test("private drains are in the game on campus and nowhere else", () => {
  const byId = logic.zonesById(zones);
  const some = (zone, owner) => inlets.features.find((f) => f.properties.zone === zone && f.properties.owner === owner).properties;
  assert.equal(logic.canBeCaught(some("campus", "Private"), byId, "2026-11-10"), true);
  assert.equal(logic.canBeCaught(some("downtown", "Private"), byId, "2026-11-10"), false);
  assert.equal(logic.canBeCaught(some("downtown", "Municipality"), byId, "2026-11-10"), true);
  assert.equal(logic.canBeCaught(some("", "Municipality"), byId, "2026-11-10"), false);
});

test("the popup speaks in plain sentences without a dash", () => {
  const byId = logic.zonesById(zones);
  const ready = logic.prepared(inlets, zones, "2026-10-12");
  const find = (id) => ready.features.find((f) => f.properties.id === id).properties;
  const row = logic.describeDrain(find("in1342"), byId, "2026-10-12");
  assert.equal(row.title, "Pardoe Road");
  assert.equal(row.id, "in1342");
  assert.equal(row.lines[0], "Three grates in a row, one drain in the game.");
  assert.ok(row.lines.includes("Owned by the town."));
  assert.equal(row.lines.at(-1), "Can be caught, in the zone Western streets.");
  const early = logic.describeDrain(find("in1342"), byId, "2026-10-01");
  assert.equal(early.lines.at(-1), "In the zone Western streets, which opens on 2026-10-12.");
  const outside = logic.describeDrain(find("in0001"), byId, "2026-10-12");
  assert.equal(outside.lines.at(-1), "Outside the play zones.");
  const privateDowntown = ready.features.find((f) => f.properties.zone === "downtown" && f.properties.owner === "Private").properties;
  assert.match(logic.describeDrain(privateDowntown, byId, "2026-10-12").lines.at(-1), /drains of this owner are not in the game there/);
  for (const f of ready.features) {
    const text = logic.describeDrain(f.properties, byId, "2026-10-12");
    assert.doesNotMatch([text.title, ...text.lines].join(" "), /[‒-―]| - /, `a dash in the popup of ${f.properties.id}`);
    assert.ok(text.lines.every((line) => line.endsWith(".")), `a line of ${f.properties.id} is not a sentence`);
  }
});

test("the town's category values lose their dash", () => {
  assert.equal(logic.plain("Type B or C - Combination Inlet"), "Type B or C, Combination Inlet");
  assert.equal(logic.plain(""), "");
  assert.equal(logic.plain(undefined), "");
});

test("the credit line is what the file says about itself", () => {
  const line = logic.creditLine(inlets);
  assert.ok(line.includes("Municipality of Princeton") && line.includes("2026-09-11") && line.includes("OPRA"));
});

test("the first view holds every zone and each name sits inside the view", () => {
  const [west, south, east, north] = logic.boundsOf(zones);
  assert.ok(west < -74.68 && east > -74.645 && south < 40.338 && north > 40.362);
  for (const zone of zones.features) {
    const [lon, lat] = logic.labelPoint(zone);
    assert.ok(lon > west && lon < east && lat > south && lat < north);
  }
});
