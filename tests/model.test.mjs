// Falak's one self-check: the astronomy against published references.
// Run: TZ=Australia/Melbourne node tests/model.test.mjs
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import vm from "node:vm"
import { fileURLToPath } from "node:url"
import { execFileSync } from "node:child_process"

const dir = path.dirname(fileURLToPath(import.meta.url))
const model = { Math, Date, JSON, parseFloat, isNaN, String, Infinity }
vm.createContext(model)
vm.runInContext(fs.readFileSync(path.join(dir, "..", "Model.js"), "utf8"), model)

assert.equal(Intl.DateTimeFormat().resolvedOptions().timeZone, "Australia/Melbourne", "run with TZ=Australia/Melbourne")

// Melbourne CBD (public coordinates, not this machine's location).
const LAT = -37.8136, LON = 144.9631
const minutes = (hhmm) => { const [h, m] = hhmm.split(":").map(Number); return h * 60 + m }
const localMinutes = (ms) => { const d = new Date(ms); return d.getHours() * 60 + d.getMinutes() + d.getSeconds() / 60 }

// api.aladhan.com, method=1 (Karachi), school=1 (Hanafi), fetched 2026-10-06.
// Covers DST (Oct), the summer solstice and the winter solstice.
const reference = {
  "2026-10-06": { fajr: "05:19", sunrise: "06:49", dhuhr: "13:08", asr: "17:38", maghrib: "19:29", isha: "20:59" },
  "2026-12-21": { fajr: "03:59", sunrise: "05:54", dhuhr: "13:18", asr: "18:27", maghrib: "20:42", isha: "22:37" },
  "2026-06-21": { fajr: "06:01", sunrise: "07:36", dhuhr: "12:22", asr: "15:29", maghrib: "17:08", isha: "18:43" },
}
for (const [date, want] of Object.entries(reference)) {
  const [y, m, d] = date.split("-").map(Number)
  const got = model.prayerTimes(new Date(y, m - 1, d, 12).getTime(), LAT, LON, { method: "Karachi", asr: "hanafi" })
  for (const key of Object.keys(want)) {
    const diff = localMinutes(got[key]) - minutes(want[key])
    assert.ok(Math.abs(diff) <= 1.5, `${date} ${key}: got ${model.hhmm(got[key])}, want ${want[key]} (${diff.toFixed(1)} min)`)
  }
}

// Umm al-Qura Hijri dates (api.aladhan.com gToH), chosen around month starts.
const hijri = {
  "2026-01-01": "12-07-1447", "2026-02-17": "29-08-1447", "2026-02-18": "01-09-1447",
  "2026-03-19": "30-09-1447", "2026-03-20": "01-10-1447", "2026-05-17": "30-11-1447",
  "2026-05-27": "10-12-1447", "2026-06-15": "29-12-1447", "2026-06-16": "01-01-1448",
  "2026-09-12": "01-04-1448", "2026-10-06": "25-04-1448", "2026-10-11": "30-04-1448",
  "2026-10-12": "01-05-1448", "2026-11-10": "30-05-1448", "2026-11-11": "01-06-1448",
  "2027-02-08": "01-09-1448", "2027-03-01": "22-09-1448",
}
let misses = []
for (const [date, want] of Object.entries(hijri)) {
  const [y, m, d] = date.split("-").map(Number)
  const h = model.hijriDate(new Date(y, m - 1, d, 12).getTime(), 0, false)
  const got = `${String(h.day).padStart(2, "0")}-${String(h.month).padStart(2, "0")}-${h.year}`
  if (got !== want) misses.push(`${date}: got ${got}, want ${want}`)
}
assert.deepEqual(misses, [], "hijri mismatches")

// The Islamic day begins at Maghrib: tonight is already the 26th, and the
// evening of the 30th is already the 1st of the next month.
const after = (y, m, d) => { const h = model.hijriDate(new Date(y, m - 1, d, 20).getTime(), 0, true); return `${h.day}-${h.month}-${h.year}` }
assert.equal(after(2026, 10, 6), "26-4-1448")
assert.equal(after(2026, 10, 11), "1-5-1448")

// Qibla from Melbourne: api.aladhan.com/v1/qibla gives 278.8248°.
const q = model.qibla(LAT, LON)
assert.ok(Math.abs(q.bearing - 278.8248) < 0.01, `qibla bearing ${q.bearing}`)
// Distance cross-checked with the spherical law of cosines: 12,740.8 km.
assert.ok(Math.abs(q.km - 12740.76) < 0.1, `qibla distance ${q.km}`)

// Moon: full moon 2026-10-26 04:12 UTC, new moon 2026-10-10 15:50 UTC (published).
assert.ok(model.moonPhase(Date.UTC(2026, 9, 26, 4, 12)).illumination > 0.99)
assert.ok(model.moonPhase(Date.UTC(2026, 9, 10, 15, 50)).illumination < 0.01)

// Next prayer rolls into tomorrow after Isha.
const lateNight = new Date(2026, 9, 6, 23, 30).getTime()
const next = model.nextPrayer(lateNight, LAT, LON, { method: "Karachi", asr: "hanafi" })
assert.equal(next.key, "fajr")
assert.equal(new Date(next.time).getDate(), 7)

assert.equal(model.parseLocation('{"name":"X","latitude":-37.5,"longitude":144.9}').latitude, -37.5)
assert.equal(model.parseLocation("{}"), null)
assert.equal(model.countdown(3 * 3600000 + 5 * 60000), "3h 05m")

// The pill: countdown before a prayer, "now" for its first twenty minutes.
const werribee = { name: "Werribee", latitude: -37.9, longitude: 144.66 }
const opts = { method: "Karachi", asr: "hanafi" }
const asr = model.prayerTimes(new Date(2026, 9, 6, 12).getTime(), werribee.latitude, werribee.longitude, opts).asr
assert.match(model.pill(asr - 3600000, werribee, opts).label, /Asr 1h 00m$/)
assert.equal(model.pill(asr + 5 * 60000, werribee, opts).active, true)
assert.match(model.pill(asr + 25 * 60000, werribee, opts).label, /Maghrib/)
assert.equal(model.pill(asr, null, opts).label, "󰖔 set location")

// Rasd al-Qibla, published: the sun over the Kaaba ~28 May 09:18 and
// ~15 Jul 09:27 UTC; over its antipode ~28 Nov 21:09 and ~13 Jan 21:29 UTC.
const K = model.KAABA, near = (t, want) => Math.abs(t - want) < 10 * 60000
assert.ok(near(model.nextZenith(Date.UTC(2026, 0, 1), K.latitude, K.longitude), Date.UTC(2026, 4, 28, 9, 18)))
assert.ok(near(model.nextZenith(Date.UTC(2026, 5, 1), K.latitude, K.longitude), Date.UTC(2026, 6, 15, 9, 27)))
assert.ok(near(model.nextZenith(Date.UTC(2026, 9, 6), -K.latitude, K.longitude - 180), Date.UTC(2026, 10, 28, 21, 9)))
assert.ok(near(model.nextZenith(Date.UTC(2026, 11, 1), -K.latitude, K.longitude - 180), Date.UTC(2027, 0, 13, 21, 29)))
// Melbourne sees the antipode one (08:09 local); London sees the Kaaba one.
assert.equal(model.nextRasd(Date.UTC(2026, 9, 6), LAT, LON).kind, "antipode")
assert.equal(model.nextRasd(Date.UTC(2027, 0, 20), 51.5, -0.12).kind, "kaaba")

// Facing the sun at `toward` faces the qibla.
const qs = model.qiblaSun(new Date(2026, 9, 6, 12).getTime(), LAT, LON)
assert.ok(Math.abs(model.sunPosition(qs.toward, LAT, LON).azimuth - model.qibla(LAT, LON).bearing) < 0.05)

// Windows: Duha sits between the sunrise and zenith makruh windows; the last
// third of last night ends at today's Fajr.
const w = model.prayerWindows(new Date(2026, 9, 6, 12).getTime(), LAT, LON, opts)
const today = model.prayerTimes(new Date(2026, 9, 6, 12).getTime(), LAT, LON, opts)
assert.equal(w.duha[0], w.makruh[0][1])
assert.equal(w.duha[1], w.makruh[1][0])
assert.equal(w.lastThird[0][1], today.fajr)

// Melbourne never needs it.
assert.deepEqual({ ...model.prayerTimes(new Date(2026, 11, 21, 12).getTime(), LAT, LON, opts).adjusted }, { fajr: false, isha: false })

// Displayed times are on the safe side: starts round up, sunrise down.
assert.equal(model.prayerClock("maghrib", new Date(2026, 9, 6, 19, 28, 10).getTime()), "19:29")
assert.equal(model.prayerClock("sunrise", new Date(2026, 9, 6, 6, 48, 50).getTime()), "06:48")

// Ramadan 1448 (Umm al-Qura): 1 Ramadan is 8 Feb 2027, Eid al-Fitr 9 Mar.
const at = (iso) => new Date(iso).getTime()
const kal = werribee
const ram = (iso) => model.ramadan(at(iso), kal.latitude, kal.longitude, opts, 0)
assert.equal(ram("2027-02-07T12:00:00+11:00"), null)                     // 30 Sha'ban, by day
assert.equal(ram("2027-02-07T21:00:00+11:00").day, 1)                     // that evening: the first night
assert.equal(ram("2027-02-21T13:00:00+11:00").phase, "fast")
assert.equal(ram("2027-02-21T13:00:00+11:00").length, 29)
for (const iso of ["2027-02-21T13:00:00+11:00", "2027-02-21T23:00:00+11:00", "2027-02-07T21:00:00+11:00"]) {
  const r = ram(iso), eid = new Date(at(iso)); eid.setDate(eid.getDate() + r.eidInDays)
  assert.equal(eid.getDate() + "/" + (eid.getMonth() + 1), "9/3", `eid from ${iso}`)
}
const pillAt = (iso) => model.pill(at(iso), kal, opts, 0)
assert.match(pillAt("2027-02-08T03:00:00+11:00").label, /Suhoor 2h/)
assert.match(pillAt("2027-02-21T13:00:00+11:00").label, /Iftar 7h/)
assert.match(pillAt("2027-02-21T20:15:00+11:00").label, /Iftar now$/)
assert.match(pillAt("2027-02-21T20:40:00+11:00").label, /Isha/)
// The last ten minutes count in seconds, and iftar lands on the minute shown.
const r14 = ram("2027-02-21T13:00:00+11:00")
assert.equal(r14.iftar % 60000, 0)
assert.ok(r14.iftar >= r14.fastEnd)
const late = model.pill(r14.iftar - 272000, kal, opts, 0)
assert.ok(late.fast && /Iftar 4:32$/.test(late.label), late.label)
assert.equal(model.eid(model.hijriDate(at("2027-03-09T12:00:00+11:00"), 0, false)), "Eid al-Fitr")

// Every method against api.aladhan.com's own computation (standard Asr).
const fixture = JSON.parse(fs.readFileSync(path.join(dir, "fixtures", "aladhan-methods.json"), "utf8"))
const ids = { 0: "Jafari", 1: "Karachi", 2: "ISNA", 3: "MWL", 4: "Makkah", 5: "Egypt", 7: "Tehran", 8: "Gulf", 9: "Kuwait",
  10: "Qatar", 11: "Singapore", 12: "France", 13: "Turkey", 14: "Russia", 16: "Dubai", 17: "JAKIM", 18: "Tunisia",
  19: "Algeria", 20: "Kemenag", 21: "Morocco", 22: "Portugal", 23: "Jordan" }
const methodMisses = []
// JAKIM and Kemenag deliberately follow other sources (official timetable,
// the extension); Turkey's extra Isha minute comes from Diyanet's own.
const divergesFromAladhan = { JAKIM: "all", Kemenag: "all", Turkey: "isha" }
for (const [id, want] of Object.entries(fixture.methods)) {
  if (divergesFromAladhan[ids[id]] === "all") continue
  const got = model.prayerTimes(new Date(2026, 9, 6, 12).getTime(), LAT, LON, { method: ids[id], asr: "standard" })
  for (const [k, ref] of [["fajr", "Fajr"], ["sunrise", "Sunrise"], ["dhuhr", "Dhuhr"], ["asr", "Asr"], ["maghrib", "Maghrib"], ["isha", "Isha"]]) {
    const diff = localMinutes(got[k]) - minutes(want[ref])
    if (divergesFromAladhan[ids[id]] === k) continue
    if (Math.abs(diff) > 1.5) methodMisses.push(`${ids[id]} ${k}: got ${model.hhmm(got[k])}, want ${want[ref]}`)
  }
}
assert.deepEqual(methodMisses, [], "method mismatches")

// "auto" picks the country's authority and school.
assert.deepEqual([model.resolveOpts({ method: "auto", asr: "auto" }, "TR").method, model.resolveOpts({ method: "auto", asr: "auto" }, "TR").asr], ["Turkey", "hanafi"])
assert.deepEqual([model.resolveOpts({}, "MY").method, model.resolveOpts({}, "MY").asr], ["JAKIM", "standard"])
assert.equal(model.resolveOpts({}, "AU").method, "MWL")
assert.equal(model.resolveOpts({ method: "Karachi", asr: "hanafi" }, "AU").method, "Karachi")

// Offline places.
const db = model.parseCities(fs.readFileSync(path.join(dir, "..", "assets", "cities.json"), "utf8"))
const first = (q) => model.searchCities(db, q, 6)[0]
assert.equal(first("mecca").name, "Makkah")
assert.equal(first("مكة").name, "Makkah")
assert.equal(first("medina").country, "SA")
assert.equal(first("lahore").countryName, "Pakistan")
assert.equal(first("melbourne").region, "Victoria")
assert.equal(model.searchCities(db, "x", 6).length, 0)
assert.equal(model.nearestCity(db, -37.53333, 144.95).country, "AU")
assert.equal(model.nearestCity(db, 41.01, 28.97).country, "TR")

// Language: short strings, native digits for Arabic and Persian.
assert.equal(model.language("auto", "tr_TR"), "tr")
assert.equal(model.language("auto", "de_DE"), "en")
assert.equal(model.language("ur", "en_AU"), "ur")
assert.equal(model.digits("17:39", "ar", "auto"), "١٧:٣٩")
assert.equal(model.digits("17:39", "ur", "auto"), "17:39")
assert.equal(model.digits("17:39", "ur", "native"), "۱۷:۳۹")
assert.equal(model.hijriMonth("tr", 9), "Ramazan")
const ar = { ...opts, lang: "ar" }
assert.match(model.pill(asr - 3600000, werribee, ar).label, /العصر ١h ٠٠m$/)
assert.match(model.pill(asr + 60000, werribee, { ...opts, lang: "tr" }).label, /İkindi şimdi$/)
for (const [lang, table] of Object.entries(model.STRINGS))
  for (const key of Object.keys(model.STRINGS.en)) assert.ok(table[key], `${lang} lacks ${key}`)

// Places keep their own clock. The machine stays on Melbourne time; each
// place's zone comes from zdump through Model.zoneCommand/parseZone.
const zoneFor = (name, at) => { const cmd = model.zoneCommand(name, at); return model.parseZone(name, execFileSync(cmd[0], cmd.slice(1), { encoding: "utf8" })) }
const zfix = JSON.parse(fs.readFileSync(path.join(dir, "fixtures", "aladhan-zones.json"), "utf8"))
const zoneMisses = []
const wallMinutes = (ms, zone) => { const c = model.civil(ms, zone); return c.getUTCHours() * 60 + c.getUTCMinutes() + c.getUTCSeconds() / 60 }
for (const p of zfix.places) {
  const [d, m, y] = p.date.split("-").map(Number)
  const zone = zoneFor(p.tz, Date.UTC(y, m - 1, d))
  const method = Object.entries(ids).find(([id]) => +id === p.method)[1]
  const noon = model.zonedTime(y, m - 1, d, 12, 0, 0, zone)
  const got = model.prayerTimes(noon, p.lat, p.lon, { method, asr: p.school ? "hanafi" : "standard", zone })
  for (const [k, ref] of [["fajr", "Fajr"], ["sunrise", "Sunrise"], ["dhuhr", "Dhuhr"], ["asr", "Asr"], ["maghrib", "Maghrib"], ["isha", "Isha"]]) {
    const diff = wallMinutes(got[k], zone) - minutes(p.timings[ref])
    // Asr: aladhan refines the sun's declination once per prayer, which drifts
    // with latitude (3 min late at St. John's in October, none at Melbourne).
    // Falak's Asr is checked against the definition below instead.
    const tolerance = k === "asr" ? 3.5 : 1.5
    if (Math.abs(diff) > tolerance) zoneMisses.push(`${p.name} ${k}: got ${model.hhmm(got[k], zone)}, want ${p.timings[ref]}`)
  }
  // At Asr a shadow is longer than at noon by its object's height (twice, Hanafi).
  const cot = (deg) => 1 / Math.tan(deg * Math.PI / 180)
  const grown = cot(model.sunPosition(got.asr, p.lat, p.lon).altitude) - cot(got.noonAltitude)
  // (Not for an authority that adds minutes to Asr, as Diyanet does.)
  if (!(model.METHODS[method].offsets || {}).asr)
    assert.ok(Math.abs(grown - (p.school ? 2 : 1)) < 0.001, `${p.name} asr shadow grew by ${grown}`)
}
assert.deepEqual(zoneMisses, [], "zone mismatches")

// The Moonsighting Committee's seasonal Fajr and Isha, both hemispheres, above 55°N too.
const msfix = JSON.parse(fs.readFileSync(path.join(dir, "fixtures", "aladhan-moonsighting.json"), "utf8"))
const msMisses = []
for (const p of msfix.places) {
  const [d, m, y] = p.date.split("-").map(Number)
  const zone = zoneFor(p.tz, Date.UTC(y, m - 1, d))
  const got = model.prayerTimes(model.zonedTime(y, m - 1, d, 12, 0, 0, zone), p.lat, p.lon, { method: "Moonsighting", zone })
  for (const [k, ref] of [["fajr", "Fajr"], ["sunrise", "Sunrise"], ["isha", "Isha"]])
    if (Math.abs(wallMinutes(got[k], zone) - minutes(p.timings[ref])) > 1.5) msMisses.push(`${p.name} ${p.date} ${k}: got ${model.hhmm(got[k], zone)}, want ${p.timings[ref]}`)
}
assert.deepEqual(msMisses, [], "Moonsighting Committee mismatches")

const riyadh = zoneFor("Asia/Riyadh", Date.UTC(2026, 9, 6))
assert.equal(model.utcLabel(Date.UTC(2026, 9, 6), riyadh), "UTC+3")
assert.equal(model.utcLabel(Date.UTC(2027, 0, 15), zoneFor("America/St_Johns", Date.UTC(2027, 0, 15))), "UTC−3:30")
// Makkah's day: midnight there is 21:00 UTC; the date line and hijri follow it.
const mk = model.localMidnight(Date.UTC(2026, 9, 6, 9), riyadh)
assert.equal(mk, Date.UTC(2026, 9, 5, 21))
assert.equal(model.dateText(Date.UTC(2026, 9, 6, 22), riyadh), "Wednesday 7 October 2026")
assert.equal(model.dayTimeText(Date.UTC(2027, 4, 28, 9, 18), riyadh), "28 May, 12:18")
// Melbourne's own zone through zdump agrees with the machine clock, DST included.
const mel = zoneFor("Australia/Melbourne", Date.UTC(2026, 9, 6))
for (const at of [Date.UTC(2026, 9, 3, 15, 59), Date.UTC(2026, 9, 3, 16, 1), Date.UTC(2027, 3, 3, 15, 59), Date.UTC(2027, 3, 3, 16, 1), Date.UTC(2026, 6, 1)])
  assert.equal(model.zoneOffset(at, mel), model.zoneOffset(at, null), new Date(at).toISOString())
// Ramadan 1448 in Makkah, on Makkah's clock: 1 Ramadan is 8 Feb there too.
const mkR = model.ramadan(model.zonedTime(2027, 1, 8, 13, 0, 0, riyadh), 21.427, 39.826, { method: "Makkah", asr: "standard", zone: riyadh }, 0)
assert.equal(mkR.day, 1)
// Umm al-Qura's 120-minute Isha in Ramadan.
const mkT = model.prayerTimes(model.zonedTime(2027, 1, 20, 12, 0, 0, riyadh), 21.427, 39.826, { method: "Makkah", zone: riyadh })
assert.equal(Math.round((mkT.isha - mkT.maghrib) / 60000), 120)
// Against the authorities' own published timetables: what a user compares with.
const official = JSON.parse(fs.readFileSync(path.join(dir, "fixtures", "official.json"), "utf8"))
const officialMisses = []
for (const p of official.places) {
  const [y, mo, d] = p.date.split("-").map(Number)
  const zone = zoneFor(p.tz, Date.UTC(y, mo - 1, d))
  const got = model.prayerTimes(model.zonedTime(y, mo - 1, d, 12, 0, 0, zone), p.lat, p.lon, { method: p.method, asr: "standard", zone })
  for (const k of Object.keys(p.timings)) {
    const shown = model.prayerClock(k, got[k], zone)
    const off = (minutes(shown) - minutes(p.timings[k]))
    if (Math.abs(off) > 1) officialMisses.push(`${p.name} ${k}: shows ${shown}, official ${p.timings[k]}`)
  }
}
assert.deepEqual(officialMisses, [], "official timetable mismatches")
// Every method can be described in the picker.
for (const key of model.methodKeys()) assert.ok(model.methodSummary(key).startsWith("Fajr "), key)

// Rejects anything that is not a zone name.
assert.equal(model.zoneCommand("Asia/Riyadh; rm -rf ~", 0), null)
assert.equal(model.parseZone("x", "garbage"), null)

// The hijri calendar. Umm al-Qura 1447/1448 dates (aladhan gToH) and
// what they mean.
const dn = (y, m, d) => Math.round(Date.UTC(y, m - 1, d) / 86400000)
const muharram = model.hijriMonthOfDay(dn(2026, 6, 25), 0)
assert.equal(muharram.month, 1)
assert.equal(muharram.year, 1448)
assert.equal(muharram.start, dn(2026, 6, 16))                    // 1 Muharram 1448
const ashura = muharram.days[9]
assert.equal(ashura.date + "/" + (ashura.month + 1), "25/6")
assert.ok(ashura.notes.events.includes("Ashura") && ashura.notes.fast === "sunnah")
const dhul = model.hijriMonthOfDay(dn(2026, 5, 27), 0)             // 10 Dhu al-Hijjah 1447
assert.equal(dhul.month, 12)
assert.equal(dhul.days[9].date + "/" + (dhul.days[9].month + 1), "27/5")
assert.ok(dhul.days[9].notes.events.includes("Eid al-Adha") && dhul.days[9].notes.fast === "forbidden")
assert.ok(dhul.days[8].notes.events.includes("Day of Arafah"))
assert.equal(dhul.days[12].notes.fast, "forbidden")              // 13th: Tashreeq, not a white day fast
assert.equal(model.hijriMonthOfDay(dn(2026, 10, 6), 0).length, 30) // Rabi' al-Thani 1448: 12 Sep to 11 Oct
assert.equal(model.hijriMonthOfDay(dn(2027, 2, 21), 0).length, 29) // Ramadan 1448
// A white day that is also a Monday lists both reasons.
const rt = model.hijriMonthOfDay(dn(2026, 10, 6), 0)
const white = rt.days.filter((d) => d.day >= 13 && d.day <= 15)
assert.ok(white.every((d) => d.notes.fast === "sunnah" && d.notes.why.some((w) => w.startsWith("a white day"))))
assert.equal(model.dayNotes(4, 3, 1).why.join(), "Monday")
assert.equal(model.dayNotes(4, 3, 3).fast, null)
// The offset moves the whole month.
assert.equal(model.hijriMonthOfDay(dn(2026, 10, 6), 1).start, rt.start - 1)

// The new crescent, Ramadan 1447 (moonsighting.com, ICOP): conjunction
// 17 Feb 2026 12:00 UT; that evening "cannot be seen anywhere in the
// world"; 18 Feb "seen easily from India westward everywhere"; 19 Feb "easily
// in the whole world".
assert.ok(Math.abs(model.previousConjunction(Date.UTC(2026, 1, 18)) - Date.UTC(2026, 1, 17, 12, 0)) < 15 * 60000)
// 17 Feb: ICOP (Odeh's criterion): impossible "across the Arab and Islamic
// world and the Americas". (moonsighting.com's "anywhere" uses Shaukat's own,
// stricter criterion; Odeh's allows optics in the far western Pacific.)
const feb17 = model.crescentMap(dn(2026, 2, 17), 6)
assert.ok(feb17.rows.every((r) => !/A/.test(r)), "17 Feb: nowhere naked-eye")
for (const [name, la, lo] of [["Makkah", 21.42, 39.83], ["Cairo", 30.04, 31.24], ["Karachi", 24.86, 67.01], ["Jakarta", -6.2, 106.85],
                              ["New York", 40.71, -74.01], ["Mexico City", 19.43, -99.13], ["Rio", -22.91, -43.17]])
  assert.equal(model.crescentAt(dn(2026, 2, 17), la, lo).zone, "D", `17 Feb ${name}`)
const easy18 = [["Makkah", 21.42, 39.83], ["Cairo", 30.04, 31.24], ["London", 51.51, -0.13], ["New York", 40.71, -74.01], ["Mumbai", 19.08, 72.88], ["Rabat", 34.02, -6.84]]
for (const [name, la, lo] of easy18) assert.equal(model.crescentAt(dn(2026, 2, 18), la, lo).zone, "A", `18 Feb ${name}`)
for (const [name, la, lo] of [["Melbourne", LAT, LON], ["Jakarta", -6.2, 106.85], ["Tokyo", 35.68, 139.69], ["Karachi", 24.86, 67.01]])
  assert.equal(model.crescentAt(dn(2026, 2, 19), la, lo).zone, "A", `19 Feb ${name}`)

// Adhan and reminders.
const kalOpts = { method: "MWL", asr: "standard" }
const noonOct6 = new Date(2026, 9, 6, 12).getTime()
assert.equal(model.alertEvents(noonOct6, werribee, kalOpts, {}, 0).length, 0, "off by default")
const evs = model.alertEvents(noonOct6, werribee, kalOpts, { enabled: true, before: 10 }, 0)
const asrStart = evs.find((e) => e.key === "2026-10-06-asr-start")
assert.equal(model.hhmm(asrStart.time), model.prayerClock("asr", model.prayerTimes(noonOct6, werribee.latitude, werribee.longitude, kalOpts).asr))
assert.equal(asrStart.sound, "makkah")
assert.equal(evs.find((e) => e.key === "2026-10-07-fajr-start").sound, "fajr-ali-mulla")
// Every listed recording exists.
for (const a of model.ADHANS) assert.ok(fs.existsSync(path.join(dir, "..", "assets", "adhans", a.id + ".ogg")), a.id)
assert.equal(evs.find((e) => e.key === "2026-10-06-asr-before").time, asrStart.time - 10 * 60000)
assert.ok(!evs.some((e) => e.key.includes("sunrise")), "sunrise off by default")
assert.ok(!evs.some((e) => e.key.startsWith("2026-10-06-fajr")), "this morning's Fajr has passed")
assert.ok(evs.some((e) => e.key === "2026-10-07-fajr-start"), "tomorrow's Fajr is there")
for (let i = 1; i < evs.length; i++) assert.ok(evs[i].time >= evs[i - 1].time, "in time order")
const notifyOnly = model.alertEvents(noonOct6, werribee, kalOpts, { enabled: true, prayers: { asr: "notify", dhuhr: "off" } }, 0)
assert.equal(notifyOnly.find((e) => e.key === "2026-10-06-asr-start").sound, "")
assert.ok(!notifyOnly.some((e) => e.key.includes("dhuhr")))
// Ramadan: iftar named, and the suhoor reminder before Fajr.
const ramEvs = model.alertEvents(new Date(2027, 1, 21, 12).getTime(), werribee, kalOpts, { enabled: true }, 0)
assert.equal(ramEvs.find((e) => e.key === "2027-02-21-maghrib-start").headline, "Maghrib · iftar")
const suhoor = ramEvs.find((e) => e.key === "2027-02-22-suhoor")
assert.equal(suhoor.time, Math.floor(model.prayerTimes(new Date(2027, 1, 22, 12).getTime(), werribee.latitude, werribee.longitude, kalOpts).fajr / 60000) * 60000 - 30 * 60000)
// Due: on time and up to two minutes late; never twice; not after a long suspend.
assert.equal(model.dueAlerts([asrStart], asrStart.time + 30000, {}).length, 1)
assert.equal(model.dueAlerts([asrStart], asrStart.time + 30000, { [asrStart.key]: true }).length, 0)
assert.equal(model.dueAlerts([asrStart], asrStart.time + 3 * 60000, {}).length, 0)
assert.equal(model.dueAlerts([asrStart], asrStart.time - 1000, {}).length, 0)

// Eclipses against NASA's tables.
const nasa = JSON.parse(fs.readFileSync(path.join(dir, "fixtures", "nasa-eclipses.json"), "utf8"))
for (const want of nasa.lunar) {
  const [y, mo, d] = want.date.split("-").map(Number)
  const e = model.lunarEclipseAt(model.fullMoonNear(Date.UTC(y, mo - 1, d, 12)), LAT, LON)
  assert.equal(e.type, want.type, want.date)
  assert.ok(Math.abs(e.magnitude - want.umbral) < 0.012, `${want.date} umbral ${e.magnitude}`)
  const [h, mi, se] = want.maxTD.split(":").map(Number)
  assert.ok(Math.abs(e.max + model.DELTA_T * 1000 - Date.UTC(y, mo - 1, d, h, mi, se)) < 2 * 60000, `${want.date} greatest`)
  if (want.partialMin) assert.ok(Math.abs((e.partialEnd - e.partialStart) / 60000 - want.partialMin) <= 3, `${want.date} partial`)
  if (want.totalMin) assert.ok(Math.abs((e.totalEnd - e.totalStart) / 60000 - want.totalMin) <= 3, `${want.date} total`)
}
for (const want of nasa.solar) {
  const [y, mo, d] = want.date.split("-").map(Number)
  const e = model.solarEclipseAt(model.previousConjunction(Date.UTC(y, mo - 1, d + 1)), want.lat, want.lon)
  assert.equal(e.type, want.type, `${want.name} ${want.date}`)
  assert.ok(e.visible)
}
const luxor = model.solarEclipseAt(model.previousConjunction(Date.UTC(2027, 7, 3)), 25.687, 32.639)
assert.ok(Math.abs((luxor.centralEnd - luxor.centralStart) / 1000 - 383) < 30, "Luxor totality ~6m23s")

// Where on Earth: the central path and each eclipse's own type (NASA SEdecade2021).
const conj27 = model.previousConjunction(Date.UTC(2027, 7, 3))
const map27 = model.eclipseMap({ kind: "solar", max: conj27 }, 3)
const offPath = Math.min(...map27.path.map((p) => Math.hypot(p[0] - 25.687, (p[1] - 32.639) * Math.cos(25.687 * Math.PI / 180))))
assert.ok(offPath < 0.5, `Luxor on the 2027 central line (${offPath.toFixed(2)}°)`)
const width27 = map27.path[Math.floor(map27.path.length / 2)][2] * 111.2
assert.ok(Math.abs(width27 - 258) < 40, `2027 path ~258 km wide (${width27.toFixed(0)})`)
assert.equal(map27.rows[Math.floor((90 - 30) / 3)][Math.floor((31 + 180) / 3)], "3", "Cairo deep in the 2027 shadow")
assert.equal(map27.rows[Math.floor((90 + 33.9) / 3)][Math.floor((18.4 + 180) / 3)], "0", "Cape Town outside it")
for (const [y, mo, d, type] of [[2026, 8, 12, "total"], [2027, 2, 6, "annular"], [2027, 8, 2, "total"], [2028, 1, 26, "annular"], [2028, 7, 22, "total"], [2029, 1, 14, "partial"], [2029, 6, 12, "partial"]])
  assert.equal(model.solarEclipseType(model.previousConjunction(Date.UTC(y, mo - 1, d + 1))), type, `${y}-${mo}-${d} ${type}`)
const lmap = model.eclipseMap(model.lunarEclipseAt(model.fullMoonNear(Date.UTC(2026, 2, 3, 12)), LAT, LON), 3)
assert.equal(lmap.rows[Math.floor((90 + 37.8) / 3)][Math.floor((145 + 180) / 3)], "2", "3 Mar 2026: the moon up over Melbourne")
assert.equal(lmap.rows[Math.floor((90 - 51.5) / 3)][Math.floor(180 / 3)], "0", "and not over London")

// The du'a after the adhan: on by default, off when turned off, and the text is Bukhari 614's.
assert.equal(model.alertSettings({}).dua, true)
assert.equal(model.alertSettings({ dua: false }).dua, false)
assert.match(model.DUA_AFTER_ADHAN.arabic, /^اللَّهُمَّ رَبَّ هَذِهِ الدَّعْوَةِ التَّامَّةِ/)
assert.equal(model.DUA_AFTER_ADHAN.source, "Sahih al-Bukhari 614")

// The eclipse alert: the 3 March 2026 total lunar eclipse, seen from Melbourne.
const mar3 = model.lunarEclipseAt(model.fullMoonNear(Date.UTC(2026, 2, 3, 12)), LAT, LON)
const eclEvs = model.alertEvents(mar3.partialStart - 3600000, { name: "Melbourne", latitude: LAT, longitude: LON }, kalOpts, { enabled: true }, 0, [mar3])
const begins = eclEvs.find((e) => e.kind === "eclipse")
assert.equal(begins.headline, "Total lunar eclipse begins")
assert.equal(begins.time, Math.floor(mar3.partialStart / 60000) * 60000)
assert.ok(!model.alertEvents(mar3.partialStart - 3600000, { name: "M", latitude: LAT, longitude: LON }, kalOpts, { enabled: true, eclipses: "off" }, 0, [mar3]).some((e) => e.kind === "eclipse"))

// Planets against JPL Horizons (astrometric J2000, geocentre, 2026-10-06 00:00 UT).
const sky = JSON.parse(fs.readFileSync(path.join(dir, "..", "assets", "sky.json"), "utf8"))
const horizons = { mer: [213.52881, -15.91729], ven: [213.04527, -21.17444], mar: [126.80882, 20.27526],
  jup: [142.70211, 15.36134], sat: [10.99453, 1.77749], ura: [63.14442, 20.98709], nep: [2.71450, -0.37177] }
for (const [key, [ra, dec]] of Object.entries(horizons)) {
  const got = model.planetRaDec(sky.planets, key, Date.UTC(2026, 9, 6))
  const sep = model.separation(got.ra, got.dec, ra, dec)
  assert.ok(sep < 0.1, `${key} is ${sep.toFixed(3)} deg from Horizons`)
}
// The dome: zenith at the centre, the horizon on the unit circle, east on the left.
assert.deepEqual([model.domeXY(90, 0).x, model.domeXY(90, 0).y].map(Math.abs), [0, 0])
assert.ok(Math.abs(model.domeXY(0, 90).x + 1) < 1e-9, "east on the left")
assert.ok(Math.abs(model.domeXY(0, 0).y + 1) < 1e-9, "north at the top")
assert.equal(model.domeXY(-5, 0), null)

// Jumu'ah: Friday's Dhuhr, in the pill and the alerts; al-Kahf reminders.
const fri = new Date(2026, 9, 9, 10).getTime()   // Friday 9 October 2026, before Dhuhr
assert.match(model.pill(fri, werribee, kalOpts, 0).label, /Jumu'ah /)
assert.match(model.pill(new Date(2026, 9, 8, 10).getTime(), werribee, kalOpts, 0).label, /Dhuhr /)
assert.equal(model.prayerLabel("dhuhr", fri, null, "ar"), "الجمعة")
const friEvs = model.alertEvents(fri, werribee, kalOpts, { enabled: true, kahf: "friday" }, 0)
assert.equal(friEvs.find((e) => e.key === "2026-10-09-dhuhr-start").headline, "Jumu'ah")
const kahf = friEvs.find((e) => e.kind === "kahf")
assert.equal(kahf.time, friEvs.find((e) => e.key === "2026-10-09-dhuhr-start").time - 2 * 3600000)
const thuEvs = model.alertEvents(new Date(2026, 9, 8, 12).getTime(), werribee, kalOpts, { enabled: true, kahf: "thursday" }, 0)
assert.equal(thuEvs.find((e) => e.kind === "kahf").key, "2026-10-08-kahf")
assert.ok(!model.alertEvents(fri, werribee, kalOpts, { enabled: true }, 0).some((e) => e.kind === "kahf"), "al-Kahf off by default")

// Elevation: 1000 m lowers the horizon by ~1.1°, so sunrise is a few minutes earlier.
const sea = model.prayerTimes(noonOct6, werribee.latitude, werribee.longitude, kalOpts)
const high = model.prayerTimes(noonOct6, werribee.latitude, werribee.longitude, { ...kalOpts, elevation: 1000 })
assert.ok(sea.sunrise - high.sunrise > 4 * 60000 && sea.sunrise - high.sunrise < 7 * 60000, "sunrise earlier at 1000 m")
assert.ok(high.maghrib - sea.maghrib > 4 * 60000, "Maghrib later at 1000 m")
assert.equal(high.fajr, sea.fajr, "Fajr is an angle below the horizon, not affected")
// Own offsets apply last, per prayer.
const tuned = model.prayerTimes(noonOct6, werribee.latitude, werribee.longitude, { ...kalOpts, offsets: { fajr: 2, isha: -3 } })
assert.equal(tuned.fajr - sea.fajr, 2 * 60000)
assert.equal(tuned.isha - sea.isha, -3 * 60000)
assert.equal(tuned.dhuhr, sea.dhuhr)
assert.equal(model.resolveOpts({ elevation: 300, offsets: { asr: 1 } }, "AU").elevation, 300)

// Travel: Werribee to Melbourne CBD is ~27 km (home); to Makkah, away.
assert.equal(model.travel(werribee, { latitude: LAT, longitude: LON }).away, false)
assert.ok(model.travel({ latitude: 21.42, longitude: 39.83 }, werribee).km > 12000)
assert.equal(model.travel(werribee, null), null)

// A mosque timetable (semicolon CSV, d/m/y dates, am/pm times).
const iq = model.parseIqama(fs.readFileSync(path.join(dir, "fixtures", "mosque.csv"), "utf8"))
assert.equal(iq["2026-10-06"].fajr, "05:45")
assert.equal(iq["2026-10-06"].dhuhr, "13:30")
assert.equal(iq["2026-10-06"].isha, "21:00")
assert.equal(model.hhmm(model.iqamaTime(iq, "asr", new Date(2026, 9, 6, 12).getTime(), null)), "17:00")
assert.equal(model.hhmm(model.iqamaTime(iq, "dhuhr", new Date(2026, 9, 9, 12).getTime(), null)), "13:15", "Jumu'ah on Friday")
assert.equal(model.iqamaTime(iq, "fajr", new Date(2026, 9, 7, 12).getTime(), null), null, "no row, no iqama")
assert.equal(model.parseIqama("Date,Fajr\n2026-10-06,05:10")["2026-10-06"].fajr, "05:10")
assert.equal(model.parseIqama("no header here\nx"), null)
assert.equal(model.iqamaClock("12:15 am"), "00:15")

const iqEvs = model.alertEvents(new Date(2026, 9, 6, 12).getTime(), werribee, kalOpts, { enabled: true, iqama: 10 }, 0, null, iq)
assert.equal(model.hhmm(iqEvs.find((e) => e.key === "2026-10-06-asr-iqama").time), "16:50")

// The verses: fetched, never typed; no basmala or section mark leaks in.
const verses = JSON.parse(fs.readFileSync(path.join(dir, "..", "assets", "verses.json"), "utf8"))
assert.ok(verses.length >= 50)
for (const [ref, surah, ar, en] of verses) {
  assert.ok(ar && en && surah, ref)
  assert.ok(!ar.startsWith("بِسْمِ") && !ar.includes("۞"), `${ref} carries a basmala or section mark`)
}
assert.ok(verses.some(([ref, , ar]) => ref === "21:33" && ar.includes("فَلَكٍ")), "21:33, the falak")

assert.equal(model.alertSettings(null).focus, 0, "prayer focus off by default")

// The journal: toggles, keeps order, drops empty days, ignores junk.
let jr = model.journalToggle({}, "2026-10-06", "asr")
jr = model.journalToggle(jr, "2026-10-06", "fajr")
assert.equal(jr["2026-10-06"].join(), "fajr,asr")
jr = model.journalToggle(jr, "2026-10-06", "asr"); jr = model.journalToggle(jr, "2026-10-06", "fajr")
assert.equal(jr["2026-10-06"], undefined)
assert.equal(JSON.stringify(model.parseJournal('{"2026-10-06":["isha","nope"],"x":[1]}')), '{"2026-10-06":["isha"]}')
assert.equal(JSON.stringify(model.parseJournal("not json")), "{}")

// The year's sacred days as iCalendar: Eid al-Adha 1447 on 27 May 2026.
const ics = model.icsSacredDays(dn(2026, 0, 1), 0)
assert.ok(ics.startsWith("BEGIN:VCALENDAR\r\n") && ics.endsWith("END:VCALENDAR\r\n"))
assert.ok(ics.includes("DTSTART;VALUE=DATE:20260527\r\nDTEND;VALUE=DATE:20260528\r\nSUMMARY:Eid al-Adha (10 Dhu al-Hijjah 1447)"))
assert.ok(ics.includes("SUMMARY:Ashura (10 Muharram 1448)"))
assert.equal((ics.match(/BEGIN:VEVENT/g) || []).length, (ics.match(/END:VEVENT/g) || []).length)

console.log("falak model: ok")
