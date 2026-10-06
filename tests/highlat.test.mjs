// High latitudes. Falak computes each day in the machine's timezone, so this
// runs as a desk in Oslo would: TZ=Europe/Oslo node tests/highlat.test.mjs
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import vm from "node:vm"
import { fileURLToPath } from "node:url"

const dir = path.dirname(fileURLToPath(import.meta.url))
const model = { Math, Date, JSON, parseFloat, isNaN, String }
vm.createContext(model)
vm.runInContext(fs.readFileSync(path.join(dir, "..", "Model.js"), "utf8"), model)

assert.equal(Intl.DateTimeFormat().resolvedOptions().timeZone, "Europe/Oslo", "run with TZ=Europe/Oslo")

// High latitude: Oslo, 21 June 2027, where the sun never reaches −18°.
// api.aladhan.com method=3 (MWL), school=1, latitudeAdjustmentMethod 3/2/1.
const oslo = { lat: 59.9139, lon: 10.7522 }, cest = (h, m, dayShift = 0) => Date.UTC(2027, 5, 21 + dayShift, h - 2, m)
const osloRef = {
  angle:   { fajr: cest(2, 21), isha: cest(0, 12, 1) },
  seventh: { fajr: cest(3, 9),  isha: cest(23, 28) },
  middle:  { fajr: cest(1, 19), isha: cest(1, 19, 1) },
}
for (const [rule, want] of Object.entries(osloRef)) {
  const t = model.prayerTimes(Date.UTC(2027, 5, 21, 10), oslo.lat, oslo.lon, { method: "MWL", highLatitude: rule })
  for (const k of ["fajr", "isha"]) assert.ok(Math.abs(t[k] - want[k]) < 1.5 * 60000, `oslo ${rule} ${k}: ${new Date(t[k]).toISOString()}`)
  assert.ok(t.adjusted.fajr && t.adjusted.isha)
}
console.log("falak high latitude: ok")
