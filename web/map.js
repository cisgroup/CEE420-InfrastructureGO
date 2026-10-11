// The town's map. This file is the part that touches the page and the map library. Everything that is plain
// reasoning lives in logic.js, where node tests it.
//
// The address can carry three aids for looking at the page. day=2026-10-12 shows the zones as they are on that
// day, at=40.3568,-74.6727 opens the map there, and basemap=none draws without the street map, which is also
// what happens by itself when the street map cannot be reached.

import { boundsOf, creditLine, describeDrain, isDay, labelPoint, prepared, todayInNewYork, zoneCounts, zonesById } from "./logic.js";

const BASEMAP = "https://tiles.openfreemap.org/styles/positron";
const PLAIN = { version: 8, sources: {}, layers: [{ id: "paper", type: "background", paint: { "background-color": "#f3f5f7" } }] };
const params = new URLSearchParams(location.search);
const day = isDay(params.get("day")) ? params.get("day") : todayInNewYork();
const status = document.getElementById("status");

function say(text, problem = false) {
  status.textContent = text;
  status.classList.toggle("problem", problem);
}

async function json(path) {
  const response = await fetch(path);
  if (!response.ok) throw new Error(`${path} answered ${response.status}`);
  return response.json();
}

/** The street map's style, or a plain sheet when it cannot be had within a few seconds. */
async function basemap() {
  if (params.get("basemap") === "none") return { style: PLAIN, plain: true };
  try {
    const response = await fetch(BASEMAP, { signal: AbortSignal.timeout(6000) });
    if (!response.ok) throw new Error(`the street map answered ${response.status}`);
    return { style: await response.json(), plain: false };
  } catch (error) {
    console.warn("The street map could not be loaded, drawing without it.", error);
    return { style: PLAIN, plain: true };
  }
}

function fillPanel(inlets, zones) {
  const rows = zoneCounts(inlets, zones, day);
  const body = document.querySelector("#zones tbody");
  body.replaceChildren(...rows.map((row) => {
    const tr = document.createElement("tr");
    tr.classList.toggle("closed", !row.active);
    const cells = [row.active ? row.name : `${row.name}, opens ${row.activeFrom}`, row.catchable.toLocaleString("en-US"), row.drains.toLocaleString("en-US")];
    cells.forEach((text, k) => {
      const td = document.createElement("td");
      td.textContent = text;
      if (k > 0) td.className = "number";
      tr.append(td);
    });
    return tr;
  }));
  const catchable = rows.reduce((sum, row) => sum + row.catchable, 0);
  say(`On ${day}, ${catchable.toLocaleString("en-US")} drains can be caught in ${rows.filter((row) => row.active).length} zones.`);
  document.getElementById("zones").hidden = false;
  document.getElementById("legend").hidden = false;
  document.getElementById("credit").textContent = creditLine(inlets);
}

function popupContent(properties, zones) {
  const text = describeDrain(properties, zones, day);
  const box = document.createElement("div");
  box.className = "drain";
  const title = document.createElement("h2");
  title.textContent = text.title;
  const id = document.createElement("p");
  id.className = "id";
  id.textContent = text.id;
  box.append(title, id, ...text.lines.map((line) => {
    const p = document.createElement("p");
    p.textContent = line;
    return p;
  }));
  return box;
}

function addLayers(map, inlets, zones) {
  map.addSource("zones", { type: "geojson", data: zones });
  map.addSource("inlets", { type: "geojson", data: prepared(inlets, zones, day) });
  map.addLayer({ id: "zone-fill", type: "fill", source: "zones", paint: { "fill-color": "#e77500", "fill-opacity": 0.07 } });
  map.addLayer({ id: "zone-line", type: "line", source: "zones", paint: { "line-color": "#e77500", "line-width": 2.2, "line-opacity": 0.9 } });
  const inZone = ["!=", ["get", "zone"], ""];
  map.addLayer({
    id: "grates", type: "circle", source: "inlets", minzoom: 16.5, filter: ["!", ["get", "head"]],
    paint: { "circle-radius": 3, "circle-color": "#ffffff", "circle-stroke-color": "#5b6875", "circle-stroke-width": 1 },
  });
  map.addLayer({
    id: "drains", type: "circle", source: "inlets", filter: ["get", "head"],
    paint: {
      "circle-radius": ["interpolate", ["linear"], ["zoom"], 11, ["case", ["get", "catchable"], 2.2, 1.2], 15, ["case", ["get", "catchable"], 5, inZone, 4, 2.6], 18, ["case", ["get", "catchable"], 9, inZone, 7, 5]],
      "circle-color": ["case", ["get", "catchable"], "#0b5d8a", inZone, "#ffffff", "#b9c2cb"],
      "circle-stroke-color": ["case", ["get", "catchable"], "#ffffff", inZone, "#8b98a5", "#ffffff"],
      "circle-stroke-width": ["case", ["get", "catchable"], 1.2, inZone, 1.8, 0.4],
    },
  });
  for (const zone of zones.features) {
    const label = document.createElement("div");
    label.className = "zone-name";
    label.textContent = zone.properties.name;
    new maplibregl.Marker({ element: label }).setLngLat(labelPoint(zone)).addTo(map);
  }
  const byId = zonesById(zones);
  for (const layer of ["drains", "grates"]) {
    map.on("click", layer, (event) => {
      const feature = event.features[0];
      new maplibregl.Popup({ closeButton: false, offset: 10 }).setLngLat(feature.geometry.coordinates).setDOMContent(popupContent(feature.properties, byId)).addTo(map);
    });
    map.on("mouseenter", layer, () => { map.getCanvas().style.cursor = "pointer"; });
    map.on("mouseleave", layer, () => { map.getCanvas().style.cursor = ""; });
  }
}

async function start() {
  const [inlets, zones, base] = await Promise.all([json("data/inlets.geojson"), json("data/zones.geojson"), basemap()]);
  const map = new maplibregl.Map({ container: "map", style: base.style, bounds: boundsOf(zones), fitBoundsOptions: { padding: { top: 40, bottom: 60, left: 380, right: 40 } }, attributionControl: { compact: true } });
  map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");
  map.addControl(new maplibregl.ScaleControl({ unit: "metric" }), "bottom-right");
  const at = (params.get("at") || "").split(",").map(Number);
  if (at.length === 2 && at.every(Number.isFinite)) map.jumpTo({ center: [at[1], at[0]], zoom: 18 });
  map.on("load", () => {
    addLayers(map, inlets, zones);
    fillPanel(inlets, zones);
    if (base.plain) document.getElementById("credit").textContent += " The street map could not be loaded, so the drains are drawn without it.";
    window.igo = { map, day, drains: inlets.features.length, ready: true };       // for looking at the page from the console
  });
}

start().catch((error) => {
  console.error(error);
  say("The map could not be drawn. The drains file did not load.", true);
});
