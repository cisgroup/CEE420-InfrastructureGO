// The libraries kept in web/vendor are exactly the files their lines in versions.json describe.

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import { test } from "node:test";

const folder = new URL("../vendor/", import.meta.url);
const versions = JSON.parse(readFileSync(new URL("versions.json", folder), "utf8"));

test("every vendored file has the hash its line states", () => {
  for (const entry of versions.files) {
    const hash = createHash("sha256").update(readFileSync(new URL(entry.file, folder))).digest("hex");
    assert.equal(hash, entry.sha256, `${entry.file} is not the file of version ${entry.version}`);
    assert.ok(entry.licence && entry.source && entry.retrieved && entry.version);
  }
});

test("nothing lies in the folder without a line", () => {
  const listed = new Set([...versions.files.map((f) => f.file), "versions.json", "maplibre-gl.LICENSE.txt"]);
  assert.deepEqual(readdirSync(folder).filter((name) => !listed.has(name)), []);
});

test("the licence text travels with the library", () => {
  const text = readFileSync(new URL("maplibre-gl.LICENSE.txt", folder), "utf8");
  assert.ok(text.includes("MapLibre contributors") && text.includes("Redistribution and use"));
});
