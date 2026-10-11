// The part of the town's map that is plain reasoning, kept apart from the map library so that node can test it.
// Every function takes data and returns data. Nothing here touches the page.

/** The calendar day in New York for an instant, as yyyy-mm-dd, the day the whole game counts by. */
export function todayInNewYork(now = new Date()) {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone: "America/New_York", year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(now);
  const get = (type) => parts.find((p) => p.type === type).value;
  return `${get("year")}-${get("month")}-${get("day")}`;
}

/** Whether a text is a calendar day written yyyy-mm-dd that exists. */
export function isDay(text) {
  if (typeof text !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(text)) return false;
  const d = new Date(`${text}T12:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === text;
}

/** Whether a zone is switched on on a day. */
export function zoneIsActive(zone, day) {
  return zone.active_from <= day && (zone.active_to == null || day <= zone.active_to);
}

/** The zones of the zones file by id, as plain objects with their properties. */
export function zonesById(zonesGeojson) {
  return new Map(zonesGeojson.features.map((f) => [f.properties.id, f.properties]));
}

/** Whether a drain can be caught on a day. Its zone must be switched on and admit its owner. */
export function canBeCaught(drain, zones, day) {
  const zone = zones.get(drain.zone);
  return Boolean(zone) && zoneIsActive(zone, day) && zone.owners.includes(drain.owner);
}

/** How many grates each site has. A site is a row of grates along one kerb, named after its first inlet. */
export function gratesBySite(features) {
  const counts = new Map();
  for (const f of features) counts.set(f.properties.site, (counts.get(f.properties.site) || 0) + 1);
  return counts;
}

/**
 * The inlet features with what the map paints by. head says whether the inlet is the one its site is named after,
 * grates how many grates the site has, catchable whether the game is switched on for it on the day.
 */
export function prepared(inletsGeojson, zonesGeojson, day) {
  const zones = zonesById(zonesGeojson);
  const grates = gratesBySite(inletsGeojson.features);
  return {
    ...inletsGeojson,
    features: inletsGeojson.features.map((f) => ({
      ...f,
      properties: {
        ...f.properties,
        head: f.properties.id === f.properties.site,
        grates: grates.get(f.properties.site),
        catchable: canBeCaught(f.properties, zones, day),
      },
    })),
  };
}

/** One row per zone for the panel, with the drains counted by site. */
export function zoneCounts(inletsGeojson, zonesGeojson, day) {
  const zones = zonesById(zonesGeojson);
  return zonesGeojson.features.map((z) => {
    const inside = inletsGeojson.features.filter((f) => f.properties.zone === z.properties.id);
    const heads = inside.filter((f) => f.properties.id === f.properties.site);
    return {
      id: z.properties.id,
      name: z.properties.name,
      active: zoneIsActive(z.properties, day),
      activeFrom: z.properties.active_from,
      inlets: inside.length,
      drains: heads.length,
      catchable: heads.filter((f) => canBeCaught(f.properties, zones, day)).length,
    };
  });
}

const OWNERS = {
  Municipality: "Owned by the town.",
  County: "Owned by the county.",
  State: "Owned by the State.",
  "Other Municipality": "Owned by a neighbouring town.",
  Private: "Privately owned.",
};

const NUMBER_WORDS = ["no", "one", "two", "three", "four", "five", "six"];

/** The town's category values use a dash as punctuation. The page's own text does not, so it is taken out. */
export function plain(value) {
  return String(value || "").replace(/\s+-\s+/g, ", ").trim();
}

/** What the popup of a drain says, as a title and plain sentences. */
export function describeDrain(drain, zones, day) {
  const lines = [];
  const grates = drain.grates || 1;
  if (grates > 1) lines.push(`${NUMBER_WORDS[grates] ? NUMBER_WORDS[grates][0].toUpperCase() + NUMBER_WORDS[grates].slice(1) : grates} grates in a row, one drain in the game.`);
  if (drain.type) lines.push(`${plain(drain.type)}.`);
  if (drain.grate) lines.push(`Grate, as the town lists it, ${plain(drain.grate)}.`);
  lines.push(OWNERS[drain.owner] || "Owner unknown.");
  const zone = zones.get(drain.zone);
  if (!zone) lines.push("Outside the play zones.");
  else if (!zoneIsActive(zone, day)) lines.push(`In the zone ${zone.name}, which opens on ${zone.active_from}.`);
  else if (!zone.owners.includes(drain.owner)) lines.push(`In the zone ${zone.name}, but drains of this owner are not in the game there.`);
  else lines.push(`Can be caught, in the zone ${zone.name}.`);
  return { title: drain.road || "No road name", id: drain.site || drain.id, lines };
}

/** The line that credits the town's layer, put together from what the file itself says. */
export function creditLine(inletsGeojson) {
  return `Drains from ${inletsGeojson.source}, snapshot of ${inletsGeojson.retrieved}. ${inletsGeojson.licence}.`;
}

/** The middle of a zone's outer ring, good enough to place its name. */
export function labelPoint(zoneFeature) {
  const ring = zoneFeature.geometry.type === "Polygon" ? zoneFeature.geometry.coordinates[0] : zoneFeature.geometry.coordinates[0][0];
  const points = ring.slice(0, -1);
  return [points.reduce((s, p) => s + p[0], 0) / points.length, points.reduce((s, p) => s + p[1], 0) / points.length];
}

/** The box around every zone as west, south, east, north, for the first view of the map. */
export function boundsOf(zonesGeojson) {
  let west = Infinity, south = Infinity, east = -Infinity, north = -Infinity;
  for (const f of zonesGeojson.features) {
    const polygons = f.geometry.type === "Polygon" ? [f.geometry.coordinates] : f.geometry.coordinates;
    for (const polygon of polygons) for (const [lon, lat] of polygon[0]) {
      west = Math.min(west, lon); east = Math.max(east, lon); south = Math.min(south, lat); north = Math.max(north, lat);
    }
  }
  return [west, south, east, north];
}
