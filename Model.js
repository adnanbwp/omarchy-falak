// Falak: the sun, the moon, the five prayers, the qibla and the hijri date,
// computed on this machine. No network, ever. Plain JS so QML imports it and
// node tests it (tests/model.test.mjs).
//
// Sun and moon: the Astronomical Almanac's low-precision formulas (sun ~0.01°,
// moon ~0.3° 1950-2050). Prayer times are found the honest way: sample the
// sun's altitude across the local day and bisect the crossings, so every
// prayer is literally "the moment the sun reaches angle X".

var RAD = Math.PI / 180
var DEG = 180 / Math.PI
var KAABA = { latitude: 21.422487, longitude: 39.826206 }
var SYNODIC_MONTH = 29.530588853

// Fajr and Isha are the sun's depression below the horizon. Isha may instead
// be minutes after Maghrib; Maghrib may be an angle (Shia methods) or minutes
// after sunset; `offsets` are an authority's fixed minute adjustments.
// Sources: api.aladhan.com's computation (tests/fixtures/aladhan-methods.json)
// unless `source` says otherwise. JAKIM and Diyanet are checked against their
// official timetables (tests/fixtures/official.json). `source: "extension"`
// is the Prayer Times & Quran browser extension's definition, not checked
// against the authority.
var METHODS = {
  MWL:       { name: "Muslim World League", fajr: 18, isha: 17 },
  ISNA:      { name: "Islamic Society of North America", fajr: 15, isha: 15 },
  Egypt:     { name: "Egyptian General Authority of Survey", fajr: 19.5, isha: 17.5 },
  Makkah:    { name: "Umm al-Qura, Makkah", fajr: 18.5, ishaMinutes: 90, ishaMinutesRamadan: 120 },
  Karachi:   { name: "University of Islamic Sciences, Karachi", fajr: 18, isha: 18 },
  Tehran:    { name: "Institute of Geophysics, Tehran", fajr: 17.7, isha: 14, maghribAngle: 4.5, midnight: "jafari" },
  Jafari:    { name: "Shia Ithna-Ashari, Leva Institute, Qum", fajr: 16, isha: 14, maghribAngle: 4, midnight: "jafari" },
  Gulf:      { name: "Gulf Region", fajr: 19.5, ishaMinutes: 90 },
  Kuwait:    { name: "Kuwait", fajr: 18, isha: 17.5 },
  Qatar:     { name: "Qatar", fajr: 18, ishaMinutes: 90 },
  Singapore: { name: "Majlis Ugama Islam Singapura", fajr: 20, isha: 18 },
  France:    { name: "Union des Organisations Islamiques de France", fajr: 12, isha: 12 },
  Turkey:    { name: "Diyanet İşleri Başkanlığı, Turkey", fajr: 18, isha: 17, offsets: { sunrise: -7, dhuhr: 5, asr: 4, maghrib: 7, isha: 1 } },
  Russia:    { name: "Spiritual Administration of Muslims of Russia", fajr: 16, isha: 15 },
  Dubai:     { name: "Dubai", fajr: 18.2, isha: 18.2, offsets: { dhuhr: 3, maghrib: 3 } },
  JAKIM:     { name: "Jabatan Kemajuan Islam Malaysia", fajr: 18, isha: 18, offsets: { fajr: 2, dhuhr: 3, asr: 2, maghrib: 2, isha: 1 } },
  Tunisia:   { name: "Tunisia", fajr: 18, isha: 18 },
  Algeria:   { name: "Algeria", fajr: 18, isha: 17 },
  Kemenag:   { name: "Kementerian Agama Republik Indonesia", fajr: 20, isha: 18, offsets: { fajr: 2, sunrise: -3, dhuhr: 3, asr: 2, maghrib: 3, isha: 2 }, source: "extension" },
  Morocco:   { name: "Morocco", fajr: 19, isha: 17, offsets: { dhuhr: 5, maghrib: 5 } },
  Portugal:  { name: "Comunidade Islâmica de Lisboa", fajr: 18, ishaMinutes: 77, offsets: { dhuhr: 5, maghrib: 3 } },
  Jordan:    { name: "Ministry of Awqaf, Jordan", fajr: 18, isha: 18, offsets: { maghrib: 5 } },
  France18:  { name: "France, 18°", fajr: 18, isha: 18, source: "extension" },
  London:    { name: "London Unified Islamic Prayer Timetable (12° approximation)", fajr: 12, isha: 12, source: "extension" },
  Moonsighting: { name: "Moonsighting Committee (seasonal)", fajr: 18, isha: 18, seasonal: true, offsets: { dhuhr: 5, maghrib: 3 } },
  DiyanetEU: { name: "Diyanet offsets with 15° angles (Europe)", fajr: 15, isha: 15, offsets: { sunrise: -9, dhuhr: 5, asr: 5, maghrib: 7, isha: -1 }, source: "extension" }
}

// The Moonsighting Committee's twilight: minutes from sunrise back to Fajr
// (morning) or from sunset on to Isha (evening, the "general" shafaq), set by
// latitude and the days since the winter solstice rather than by an angle.
// Their published piecewise rule, as Aladhan and adhan-js compute it.
function seasonalTwilight(dayMs, lat, zone, morning) {
  var c = civil(dayMs, zone), y = c.getUTCFullYear()
  var leap = (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0, len = leap ? 366 : 365
  var doy = Math.round((Date.UTC(y, c.getUTCMonth(), c.getUTCDate()) - Date.UTC(y, 0, 1)) / 86400000) + 1
  var dyy = lat >= 0 ? (doy + 10) % len : (doy - (leap ? 173 : 172) + len) % len
  var k = Math.abs(lat) / 55, w = morning ? [28.65, 19.44, 32.74, 48.1] : [25.6, 2.05, -9.21, 6.14]
  var a = 75 + w[0] * k, b = 75 + w[1] * k, cc = 75 + w[2] * k, d = 75 + w[3] * k
  if (dyy < 91) return a + (b - a) / 91 * dyy
  if (dyy < 137) return b + (cc - b) / 46 * (dyy - 91)
  if (dyy < 183) return cc + (d - cc) / 46 * (dyy - 137)
  if (dyy < 229) return d + (cc - d) / 46 * (dyy - 183)
  if (dyy < 275) return cc + (b - cc) / 46 * (dyy - 229)
  return b + (a - b) / 91 * (dyy - 275)
}

// One line describing a method: "18° / 17°", "18.5° / 90 min", "+ minute offsets".
function methodSummary(key) {
  var m = METHODS[key]
  if (!m) return ""
  if (m.seasonal) return "Fajr and Isha by season and latitude, minute offsets"
  var isha = m.ishaMinutes ? m.ishaMinutes + " min" : m.isha + "°"
  return "Fajr " + m.fajr + "°, Isha " + isha + (m.maghribAngle ? ", Maghrib " + m.maghribAngle + "°" : "")
    + (m.offsets ? ", minute offsets" : "") + (m.source === "extension" ? " · as the Prayer Times & Quran extension defines it" : "")
}

// The picker's order: auto, then by name.
function methodKeys() {
  return Object.keys(METHODS).sort(function(a, b) { return METHODS[a].name.localeCompare(METHODS[b].name) })
}

// What most mosques in a country follow, for method "auto". Everywhere else: MWL.
// ponytail: one method per country; regions within a country (Indian Shia,
// UK councils) differ, which is what the method setting is for.
var COUNTRY_METHOD = {
  SA: "Makkah", AE: "Dubai", QA: "Qatar", KW: "Kuwait", BH: "Gulf", OM: "Gulf", YE: "Gulf",
  EG: "Egypt", SD: "Egypt", LY: "Egypt", PK: "Karachi", IN: "Karachi", BD: "Karachi", AF: "Karachi",
  IR: "Tehran", MY: "JAKIM", ID: "Kemenag", SG: "Singapore", BN: "Singapore", TR: "Turkey",
  FR: "France", RU: "Russia", US: "ISNA", CA: "ISNA", MA: "Morocco", DZ: "Algeria", TN: "Tunisia",
  PT: "Portugal", JO: "Jordan"
}
// Where the Hanafi school predominates, for asr "auto".
var HANAFI_COUNTRIES = ["PK", "IN", "BD", "AF", "TR", "UZ", "KZ", "TJ", "KG", "TM"]

// Resolve "auto" method and asr for a country code ("" when unknown).
function resolveOpts(opts, countryCode, zone) {
  opts = opts || {}
  var method = opts.method && opts.method !== "auto" && METHODS[opts.method] ? opts.method : (COUNTRY_METHOD[countryCode] || "MWL")
  var asr = opts.asr === "standard" || opts.asr === "hanafi" ? opts.asr : (HANAFI_COUNTRIES.indexOf(countryCode) >= 0 ? "hanafi" : "standard")
  return { method: method, asr: asr, highLatitude: opts.highLatitude, lang: opts.lang || "en", numerals: opts.numerals || "auto", zone: zone || null,
           elevation: opts.elevation || 0, offsets: opts.offsets || null, auto: { method: !(opts.method && opts.method !== "auto"), asr: !(opts.asr === "standard" || opts.asr === "hanafi") } }
}

var PRAYERS = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"]
var LABELS = { fajr: "Fajr", sunrise: "Sunrise", dhuhr: "Dhuhr", asr: "Asr", maghrib: "Maghrib", isha: "Isha" }
var ARABIC = { fajr: "الفجر", sunrise: "الشروق", dhuhr: "الظهر", asr: "العصر", maghrib: "المغرب", isha: "العشاء" }

var HIJRI_MONTHS = ["Muharram", "Safar", "Rabi' al-Awwal", "Rabi' al-Thani",
  "Jumada al-Ula", "Jumada al-Akhirah", "Rajab", "Sha'ban", "Ramadan",
  "Shawwal", "Dhu al-Qa'dah", "Dhu al-Hijjah"]

function norm360(x) { x = x % 360; return x < 0 ? x + 360 : x }
function sind(x) { return Math.sin(x * RAD) }
function cosd(x) { return Math.cos(x * RAD) }

function julianDay(ms) { return ms / 86400000 + 2440587.5 }

// Right ascension / declination (degrees) of the sun at epoch ms.
function sunEquatorial(ms) {
  var n = julianDay(ms) - 2451545.0
  var L = norm360(280.460 + 0.9856474 * n)
  var g = norm360(357.528 + 0.9856003 * n)
  var lambda = L + 1.915 * sind(g) + 0.020 * sind(2 * g)
  var eps = 23.439 - 0.0000004 * n
  return {
    ra: norm360(Math.atan2(cosd(eps) * sind(lambda), cosd(lambda)) * DEG),
    dec: Math.asin(sind(eps) * sind(lambda)) * DEG,
    lambda: norm360(lambda)
  }
}

// Moon's ecliptic longitude/latitude (degrees) at epoch ms.
function moonEcliptic(ms) {
  var T = (julianDay(ms) - 2451545.0) / 36525
  var lambda = 218.32 + 481267.881 * T
    + 6.29 * sind(135.0 + 477198.87 * T) - 1.27 * sind(259.3 - 413335.36 * T)
    + 0.66 * sind(235.7 + 890534.22 * T) + 0.21 * sind(269.9 + 954397.74 * T)
    - 0.19 * sind(357.5 + 35999.05 * T) - 0.11 * sind(186.5 + 966404.03 * T)
  var beta = 5.13 * sind(93.3 + 483202.02 * T) + 0.28 * sind(228.2 + 960400.89 * T)
    - 0.28 * sind(318.3 + 6003.15 * T) - 0.17 * sind(217.6 - 407332.21 * T)
  return { lambda: norm360(lambda), beta: beta }
}

function eclipticToEquatorial(lambda, beta, ms) {
  var eps = 23.439 - 0.0000004 * (julianDay(ms) - 2451545.0)
  var ra = Math.atan2(sind(lambda) * cosd(eps) - Math.tan(beta * RAD) * sind(eps), cosd(lambda)) * DEG
  var dec = Math.asin(sind(beta) * cosd(eps) + cosd(beta) * sind(eps) * sind(lambda)) * DEG
  return { ra: norm360(ra), dec: dec }
}

// Altitude above the horizon and azimuth (from north, clockwise), degrees.
function horizontal(ra, dec, ms, lat, lon) {
  var n = julianDay(ms) - 2451545.0
  var gmst = norm360(280.46061837 + 360.98564736629 * n)
  var H = norm360(gmst + lon - ra)
  var alt = Math.asin(sind(lat) * sind(dec) + cosd(lat) * cosd(dec) * cosd(H)) * DEG
  var az = norm360(Math.atan2(sind(H), cosd(H) * sind(lat) - Math.tan(dec * RAD) * cosd(lat)) * DEG + 180)
  return { altitude: alt, azimuth: az, hourAngle: H > 180 ? H - 360 : H }
}

function sunPosition(ms, lat, lon) {
  var eq = sunEquatorial(ms)
  var h = horizontal(eq.ra, eq.dec, ms, lat, lon)
  h.declination = eq.dec
  return h
}

// Topocentric moon: altitude corrected for the ~0.95° horizontal parallax.
function moonPosition(ms, lat, lon) {
  var ec = moonEcliptic(ms)
  var eq = eclipticToEquatorial(ec.lambda, ec.beta, ms)
  var h = horizontal(eq.ra, eq.dec, ms, lat, lon)
  h.altitude -= 0.9507 * cosd(h.altitude)
  return h
}

// Phase from the sun-moon elongation. age is days since new moon (approx.).
function moonPhase(ms) {
  var s = sunEquatorial(ms)
  var m = moonEcliptic(ms)
  var d = norm360(m.lambda - s.lambda)
  var psi = Math.acos(cosd(m.beta) * cosd(d)) * DEG
  return {
    elongation: d,
    illumination: (1 - cosd(psi)) / 2,
    waxing: d < 180,
    age: d / 360 * SYNODIC_MONTH,
    name: phaseName(d)
  }
}

function phaseName(d) {
  var names = ["New moon", "Waxing crescent", "First quarter", "Waxing gibbous",
    "Full moon", "Waning gibbous", "Last quarter", "Waning crescent"]
  return names[Math.floor(norm360(d + 22.5) / 45) % 8]
}

// ---- Time zones. A place keeps its own clock: `zone` is {name, base,
// changes: [[utcMs, offsetMs]...]} from parseZone(); absent means this
// machine's clock. Qt's JS has no Intl, so offsets come from zdump.

function zoneOffset(ms, zone) {
  if (!zone) return -new Date(ms).getTimezoneOffset() * 60000
  var o = zone.base
  for (var i = 0; i < zone.changes.length && zone.changes[i][0] <= ms; i++) o = zone.changes[i][1]
  return o
}

// The wall-clock fields at ms, read with getUTC*().
function civil(ms, zone) { return new Date(ms + zoneOffset(ms, zone)) }

// The instant a wall clock in `zone` reads y-m-d h:mi:s (fields may overflow,
// as with Date.UTC). Two passes settle the offset across a DST change.
function zonedTime(y, m, d, h, mi, s, zone) {
  var wall = Date.UTC(y, m, d, h || 0, mi || 0, s || 0)
  return wall - zoneOffset(wall - zoneOffset(wall, zone), zone)
}

// Midnight (00:00 on the place's clock) of the day containing ms.
function localMidnight(ms, zone) {
  var c = civil(ms, zone)
  return zonedTime(c.getUTCFullYear(), c.getUTCMonth(), c.getUTCDate(), 0, 0, 0, zone)
}

function nextLocalMidnight(ms, zone) {
  var c = civil(ms, zone)
  return zonedTime(c.getUTCFullYear(), c.getUTCMonth(), c.getUTCDate() + 1, 0, 0, 0, zone)
}

// Noon on the day `days` after the one containing ms.
function noonOf(ms, days, zone) {
  var c = civil(ms, zone)
  return zonedTime(c.getUTCFullYear(), c.getUTCMonth(), c.getUTCDate() + (days || 0), 12, 0, 0, zone)
}

// The same wall-clock time `days` later.
function shiftDays(ms, days, zone) {
  var c = civil(ms, zone)
  return zonedTime(c.getUTCFullYear(), c.getUTCMonth(), c.getUTCDate() + days, c.getUTCHours(), c.getUTCMinutes(), c.getUTCSeconds(), zone)
}

var WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
var MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

// "Tuesday 6 October 2026"
function dateText(ms, zone) {
  var c = civil(ms, zone)
  return WEEKDAYS[c.getUTCDay()] + " " + c.getUTCDate() + " " + MONTHS[c.getUTCMonth()] + " " + c.getUTCFullYear()
}

// "29 November, 08:08"
function dayTimeText(ms, zone) {
  var c = civil(ms, zone)
  return c.getUTCDate() + " " + MONTHS[c.getUTCMonth()] + ", " + hhmm(ms, zone)
}

// "UTC+3", "UTC+5:30", "UTC−3"
function utcLabel(ms, zone) {
  var o = zoneOffset(ms, zone) / 60000, a = Math.abs(o)
  return "UTC" + (o < 0 ? "−" : "+") + Math.floor(a / 60) + (a % 60 ? ":" + (a % 60 < 10 ? "0" : "") + a % 60 : "")
}

// The command that prints a zone's offset at `fromMs`, then its changes over
// the years around it. argv only: the name never passes through a shell parse.
function zoneCommand(name, fromMs) {
  if (!/^[A-Za-z0-9_+\-]+(\/[A-Za-z0-9_+\-]+)*$/.test(String(name))) return null
  var y = new Date(fromMs).getUTCFullYear()
  return ["sh", "-c", 'TZ=":$1" date -d "@$2" +%z && zdump -V -c "$3,$4" "$1"', "falak-zone", name,
          String(Math.floor(Date.UTC(y - 1, 0, 1) / 1000)), String(y - 1), String(y + 6)]
}

// zoneCommand's output → a zone. null if it is not what zdump prints.
function parseZone(name, text) {
  var lines = String(text || "").split("\n")
  var base = /^([+-])(\d\d)(\d\d)$/.exec(lines[0].trim())
  if (!base) return null
  var months = { Jan: 0, Feb: 1, Mar: 2, Apr: 3, May: 4, Jun: 5, Jul: 6, Aug: 7, Sep: 8, Oct: 9, Nov: 10, Dec: 11 }
  var re = /\s(\w{3})\s+(\d+)\s+(\d\d):(\d\d):(\d\d)\s+(\d{4})\s+UT\s+=.*gmtoff=(-?\d+)/
  var changes = []
  for (var i = 1; i < lines.length; i++) {
    var m = re.exec(lines[i])
    if (!m || months[m[1]] === undefined) continue
    changes.push([Date.UTC(+m[6], months[m[1]], +m[2], +m[3], +m[4], +m[5]), +m[7] * 1000])
  }
  changes.sort(function(a, b) { return a[0] - b[0] })
  return { name: name, base: (base[1] === "-" ? -1 : 1) * (+base[2] * 60 + +base[3]) * 60000, changes: changes }
}

// Bisect f between a and b (f(a), f(b) of opposite sign) to ~1 second.
function bisect(f, a, b) {
  var fa = f(a)
  for (var i = 0; i < 40 && b - a > 1000; i++) {
    var m = (a + b) / 2, fm = f(m)
    if ((fm < 0) === (fa < 0)) { a = m; fa = fm } else b = m
  }
  return (a + b) / 2
}

// The sun's whole day at one place: transit, and every crossing we need.
// Times are epoch ms; a missing crossing (polar day/night) is null.
function sunDay(dayMs, lat, lon, zone) {
  var start = localMidnight(dayMs, zone), end = nextLocalMidnight(dayMs, zone)
  var step = 10 * 60000
  var alt = function(t) { return sunPosition(t, lat, lon).altitude }

  // Transit: the hour angle crosses 0 going upward, once per local day.
  var ha = function(t) { return sunPosition(t, lat, lon).hourAngle }
  var transit = null
  for (var t = start; t < end; t += step) {
    var a = ha(t), b = ha(Math.min(t + step, end))
    if (a < 0 && b >= 0) { transit = bisect(ha, t, Math.min(t + step, end)); break }
  }
  if (transit === null) transit = (start + end) / 2

  function crossing(angle, rising) {
    var f = function(t) { return alt(t) - angle }
    var from = rising ? start : transit, to = rising ? transit : end
    var prev = from, fPrev = f(from)
    for (var t = from + step; ; t += step) {
      var tt = Math.min(t, to), ft = f(tt)
      if (rising ? (fPrev < 0 && ft >= 0) : (fPrev >= 0 && ft < 0)) return bisect(f, prev, tt)
      if (tt >= to) return null
      prev = tt; fPrev = ft
    }
  }

  return { start: start, end: end, transit: transit, noonAltitude: alt(transit), crossing: crossing }
}

// opts: { method: "Karachi", asr: "hanafi"|"standard" }
function prayerTimes(dayMs, lat, lon, opts) {
  opts = opts || {}
  var method = METHODS[opts.method] || METHODS.MWL
  var day = sunDay(dayMs, lat, lon, opts.zone)
  // Asr: an object's shadow equals its noon shadow plus 1 (standard) or 2
  // (Hanafi) times its height. Noon shadow ratio is cot(noon altitude).
  var noonShadow = 1 / Math.tan(day.noonAltitude * RAD)
  var asrAngle = function(factor) { return Math.atan(1 / (factor + noonShadow)) * DEG }
  // Higher up, the horizon dips: the sun rises earlier and sets later.
  var horizon = -0.833 - 0.0347 * Math.sqrt(Math.max(0, opts.elevation || 0))
  var sunset = day.crossing(horizon, false)
  var times = {
    fajr: day.crossing(-method.fajr, true),
    sunrise: day.crossing(horizon, true),
    dhuhr: day.transit,
    asr: day.crossing(asrAngle(opts.asr === "standard" ? 1 : 2), false),
    asrStandard: day.crossing(asrAngle(1), false),
    asrHanafi: day.crossing(asrAngle(2), false),
    sunset: sunset,
    maghrib: method.maghribAngle ? day.crossing(-method.maghribAngle, false) : sunset,
    isha: method.ishaMinutes ? null : day.crossing(-method.isha, false),
    transit: day.transit,
    noonAltitude: day.noonAltitude,
    angles: { fajr: -method.fajr, sunrise: -0.833, maghrib: method.maghribAngle ? -method.maghribAngle : -0.833,
              isha: method.ishaMinutes ? null : -method.isha, asr: asrAngle(opts.asr === "standard" ? 1 : 2) },
    method: method.name,
    midnightRule: method.midnight || "standard",
    adjusted: { fajr: false, isha: false },
    highLatitude: HIGH_LATITUDE[opts.highLatitude] ? opts.highLatitude : "angle"
  }
  var off = method.offsets || {}
  ;["fajr", "sunrise", "dhuhr", "asr", "maghrib"].forEach(function(k) {   // isha below, after any interval
    if (off[k] && times[k] !== null) times[k] += off[k] * 60000
  })
  if (off.asr) {
    if (times.asrStandard !== null) times.asrStandard += off.asr * 60000
    if (times.asrHanafi !== null) times.asrHanafi += off.asr * 60000
  }
  if (method.ishaMinutes && times.maghrib !== null) {
    // Umm al-Qura lengthens the interval in Ramadan.
    var minutes = method.ishaMinutesRamadan && hijriDate(dayMs, 0, false, opts.zone).month === 9 ? method.ishaMinutesRamadan : method.ishaMinutes
    times.isha = times.maghrib + minutes * 60000
  }
  if (method.seasonal) {
    // Counted from sunrise and sunset themselves; no angle, so no high-latitude rule.
    var rise = day.crossing(horizon, true)
    times.fajr = rise === null ? null : rise - Math.round(seasonalTwilight(dayMs, lat, opts.zone, true) * 60) * 1000
    times.isha = sunset === null ? null : sunset + Math.round(seasonalTwilight(dayMs, lat, opts.zone, false) * 60) * 1000
    times.angles.fajr = null; times.angles.isha = null
  }
  if (off.isha && times.isha !== null) times.isha += off.isha * 60000
  if (!method.seasonal) adjustHighLatitude(times, method)
  // The user's own minute offsets, last (to match a local timetable).
  var mine = opts.offsets || {}
  ;["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"].forEach(function(k) {
    if (mine[k] && times[k] !== null) times[k] += mine[k] * 60000
  })
  if (mine.asr) {
    if (times.asrStandard !== null) times.asrStandard += mine.asr * 60000
    if (times.asrHanafi !== null) times.asrHanafi += mine.asr * 60000
  }
  return times
}

// Where the sun never sinks to the Fajr/Isha angle (summer above ~48°), or
// sinks to it absurdly late, the standard fallbacks bound each to a portion
// of the night: an angle-proportional share (angle/60), one seventh, or half.
var HIGH_LATITUDE = {
  angle: { name: "angle-based" },
  seventh: { name: "one-seventh of the night" },
  middle: { name: "middle of the night" },
  none: { name: "none" }
}

function adjustHighLatitude(times, method) {
  var rule = times.highLatitude
  if (rule === "none" || times.sunrise === null || times.maghrib === null) return
  var night = 86400000 - (times.maghrib - times.sunrise)
  var portion = function(angle) {
    if (rule === "seventh") return night / 7
    if (rule === "middle") return night / 2
    return night * angle / 60
  }
  var fajrMax = portion(method.fajr)
  if (times.fajr === null || times.sunrise - times.fajr > fajrMax) {
    times.fajr = times.sunrise - fajrMax
    times.adjusted.fajr = true
  }
  if (!method.ishaMinutes) {
    var ishaMax = portion(method.isha)
    if (times.isha === null || times.isha - times.maghrib > ishaMax) {
      times.isha = times.maghrib + ishaMax
      times.adjusted.isha = true
    }
  }
}

// The next prayer (sunrise counts: it ends Fajr's window) at or after ms,
// looking into tomorrow after Isha.
function nextPrayer(ms, lat, lon, opts) {
  for (var dayOffset = 0; dayOffset < 2; dayOffset++) {
    var day = noonOf(ms, dayOffset, opts && opts.zone)
    var times = prayerTimes(day, lat, lon, opts)
    for (var i = 0; i < PRAYERS.length; i++) {
      var key = PRAYERS[i]
      if (times[key] !== null && times[key] > ms) return { key: key, label: LABELS[key], time: times[key] }
    }
  }
  return null
}

// The prayer whose window we are in right now (null between sunrise and Dhuhr).
function currentPrayer(ms, times) {
  var current = null
  var order = ["fajr", "dhuhr", "asr", "maghrib", "isha"]
  for (var i = 0; i < order.length; i++)
    if (times[order[i]] !== null && times[order[i]] <= ms) current = order[i]
  if (current === "fajr" && times.sunrise !== null && ms >= times.sunrise) return null
  return current
}

// Initial great-circle bearing to the Kaaba (degrees from north) and distance.
function qibla(lat, lon) {
  var dLon = (KAABA.longitude - lon) * RAD
  var p1 = lat * RAD, p2 = KAABA.latitude * RAD
  var bearing = norm360(Math.atan2(Math.sin(dLon), Math.cos(p1) * Math.tan(p2) - Math.sin(p1) * Math.cos(dLon)) * DEG)
  var h = Math.pow(Math.sin((p2 - p1) / 2), 2) + Math.cos(p1) * Math.cos(p2) * Math.pow(Math.sin(dLon / 2), 2)
  return { bearing: bearing, km: 2 * 6371.0088 * Math.asin(Math.sqrt(h)) }
}

function compassPoint(bearing) {
  var points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
  return points[Math.round(norm360(bearing) / 22.5) % 16]
}

// Hijri date. The month and year come from the tabular (Kuwaiti) calendar;
// the day comes from the real moon, using the Umm al-Qura rule: a month
// begins the day after the conjunction when, at Makkah's sunset on the
// conjunction day, the conjunction has happened and the moon is still up.
// Sighting-based calendars can still differ by a day, hence `offset`. The
// Islamic day begins at Maghrib, so pass afterMaghrib to roll over at sunset.
function islamicToJd(y, m, d) {
  return d + Math.ceil(29.5 * (m - 1)) + (y - 1) * 354 + Math.floor((3 + 11 * y) / 30) + 1948439.5 - 1
}

function tabularHijri(jd) {
  var year = Math.floor((30 * (jd - 1948439.5) + 10646) / 10631)
  var month = Math.min(12, Math.ceil((jd - (29 + islamicToJd(year, 1, 1))) / 29.5) + 1)
  return { year: year, month: month, day: jd - islamicToJd(year, month, 1) + 1 }
}

// The conjunction (elongation 0) at or before ms.
function previousConjunction(ms) {
  var t = ms - moonPhase(ms).elongation / 360 * SYNODIC_MONTH * 86400000
  var f = function(x) { var e = moonPhase(x).elongation; return e > 180 ? e - 360 : e }
  t = bisect(f, t - 2 * 86400000, t + 2 * 86400000)
  return t > ms ? previousConjunction(ms - 20 * 86400000) : t
}

// Civil day number (days since 1970-01-01) in Makkah (UTC+3) and locally.
function makkahDayNumber(ms) { return Math.floor((ms + 3 * 3600000) / 86400000) }
function localDayNumber(ms, zone) {
  var c = civil(ms, zone)
  return Math.round(Date.UTC(c.getUTCFullYear(), c.getUTCMonth(), c.getUTCDate()) / 86400000)
}

// Day number on which the lunar month containing the conjunction begins.
function monthStartDay(conjunction) {
  var day = makkahDayNumber(conjunction)
  var sunset = null
  // Makkah sunset on that day: bisect the sun's altitude through the afternoon.
  var noon = day * 86400000 + 9 * 3600000   // 12:00 Makkah time, in UTC ms
  var f = function(t) { return sunPosition(t, KAABA.latitude, KAABA.longitude).altitude + 0.833 }
  sunset = bisect(f, noon, noon + 9 * 3600000)
  var moonUp = moonPosition(sunset, KAABA.latitude, KAABA.longitude).altitude > -0.833
  return day + (conjunction < sunset && moonUp ? 1 : 2)
}

function hijriDate(ms, offset, afterMaghrib, zone) {
  return hijriOfDay(localDayNumber(ms, zone) + (offset || 0) + (afterMaghrib ? 1 : 0))
}

// The hijri date of a civil day number (days since 1970-01-01), with the
// day number its month began on.
function hijriOfDay(today) {
  // Noon of that civil day is a safe probe for the conjunction search.
  var probe = today * 86400000 + 12 * 3600000
  var start = monthStartDay(previousConjunction(probe))
  if (start > today) start = monthStartDay(previousConjunction(probe - 25 * 86400000))
  // Name the month by its middle, where the tabular calendar cannot be wrong.
  var named = tabularHijri(Math.floor(2440587.5 + start + 14) + 0.5)
  return { year: named.year, month: named.month, day: today - start + 1, monthName: HIJRI_MONTHS[named.month - 1], start: start }
}

// ---- The hijri calendar.

// What a day means: events, and whether fasting it is sunnah or forbidden.
// Practices that only some observe say so. weekday: 0 Sunday … 6 Saturday.
function dayNotes(month, day, weekday) {
  var events = [], fast = null, why = []
  var add = function(text) { events.push(text) }
  if (month === 1 && day === 1) add("Islamic New Year")
  if (month === 1 && day === 9) { add("Tasu'a"); fast = "sunnah"; why.push("Tasu'a, with Ashura") }
  if (month === 1 && day === 10) { add("Ashura"); fast = "sunnah"; why.push("Ashura") }
  if (month === 3 && day === 12) add("Mawlid an-Nabi (observed by many)")
  if (month === 7 && day === 27) add("Isra and Mi'raj (commonly observed)")
  if (month === 8 && day === 15) add("Mid-Sha'ban (observed by many)")
  if (month === 9 && day === 1) add("Ramadan begins")
  if (month === 9) { fast = "ramadan"; why.push("Ramadan") }
  if (month === 9 && day >= 21 && day % 2 === 1) add("Odd night of the last ten: the evening before")
  if (month === 10 && day === 1) add("Eid al-Fitr")
  if (month === 10 && day >= 2) { why.push("six days of Shawwal (any six)") }
  if (month === 12 && day <= 9) { why.push("first nine days of Dhu al-Hijjah") }
  if (month === 12 && day === 8) add("Day of Tarwiyah")
  if (month === 12 && day === 9) { add("Day of Arafah"); fast = "sunnah"; why.push("Arafah, for those not on Hajj") }
  if (month === 12 && day === 10) add("Eid al-Adha")
  if (month === 12 && day >= 11 && day <= 13) add("Day of Tashreeq")
  if (day >= 13 && day <= 15 && month !== 9) why.push("a white day (13th to 15th)")
  if (month !== 9 && (weekday === 1 || weekday === 4)) why.push(weekday === 1 ? "Monday" : "Thursday")
  if (fast === null && why.length > 0) fast = "sunnah"
  // The two Eids and the days of Tashreeq: no fasting, whatever else applies.
  if ((month === 10 && day === 1) || (month === 12 && day >= 10 && day <= 13)) { fast = "forbidden"; why = ["no fasting today"] }
  return { events: events, fast: fast, why: why }
}

// The hijri month containing civil day number `dayNum` (offset: local
// sighting), as rows for a calendar: one per day, with its civil date.
function hijriMonthOfDay(dayNum, offset) {
  offset = offset || 0
  var h = hijriOfDay(dayNum + offset)
  var start = h.start - offset
  var length = hijriOfDay(start + 29 + offset).month === h.month ? 30 : 29
  var days = []
  for (var i = 0; i < length; i++) {
    var civilDate = new Date((start + i) * 86400000)
    var weekday = civilDate.getUTCDay()
    days.push({ dayNumber: start + i, day: i + 1, year: civilDate.getUTCFullYear(), month: civilDate.getUTCMonth(),
                date: civilDate.getUTCDate(), weekday: weekday, notes: dayNotes(h.month, i + 1, weekday),
                moon: moonPhase((start + i) * 86400000 + 12 * 3600000) })
  }
  return { year: h.year, month: h.month, monthName: h.monthName, start: start, length: length, days: days }
}

// Civil day number of ms on the place's clock (for the calendar).
function dayNumber(ms, zone) { return localDayNumber(ms, zone) }

// "1h 12m", "12m", "45s"
function countdown(ms) {
  var s = Math.max(0, Math.round(ms / 1000))
  var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60)
  if (h > 0) return h + "h " + (m < 10 ? "0" : "") + m + "m"
  if (m > 0) return m + "m"
  return s + "s"
}

// Clock time. Prayer starts round up and sunrise (the end of Fajr) rounds
// down, so a displayed time is never one where the prayer, or the fast's
// end at Maghrib, has not yet begun. Plain hhmm(ms) rounds down.
function prayerClock(key, ms, zone) {
  if (ms === null || ms === undefined) return "—"
  return hhmm(key === "sunrise" ? ms : Math.ceil(ms / 60000) * 60000, zone)
}

function hhmm(ms, zone) {
  if (ms === null || ms === undefined) return "—"
  var d = civil(ms, zone), h = d.getUTCHours(), m = d.getUTCMinutes()
  return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
}

// A location: omarchy's weather.json {"name", "latitude", "longitude"}, or
// Falak's own setting, which adds "region", "country" and "tz".
function parseLocation(raw) {
  try {
    var data = JSON.parse(raw || "{}")
    var lat = parseFloat(data.latitude), lon = parseFloat(data.longitude)
    if (isNaN(lat) || isNaN(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) return null
    return { name: String(data.name || ""), region: String(data.region || ""), country: String(data.country || ""),
             tz: String(data.tz || ""), latitude: lat, longitude: lon }
  } catch (e) {
    return null
  }
}

// ---- Ramadan.

// The fast at ms, or null outside Ramadan. phase "fast" runs Fajr to Maghrib
// (target: iftar); "night" counts to the next Fajr (target: suhoor ends).
// Targets sit on the safe side of the minute: iftar rounds up, suhoor's end down.
function ramadan(ms, lat, lon, opts, offset) {
  var today = prayerTimes(ms, lat, lon, opts)
  if (today.fajr === null || today.maghrib === null) return null
  var zone = opts && opts.zone
  var afterMaghrib = ms >= today.maghrib
  var h = hijriDate(ms, offset, afterMaghrib, zone)
  if (h.month !== 9) return null
  var day = 86400000
  var length = hijriDate(shiftDays(ms, 30 - h.day, zone), offset, afterMaghrib, zone).month === 9 ? 30 : 29
  var fajrNext = ms < today.fajr ? today.fajr : prayerTimes(noonOf(ms, 1, zone), lat, lon, opts).fajr
  var fasting = ms >= today.fajr && !afterMaghrib
  var minute = 60000
  return {
    day: h.day,                       // after Maghrib this is already tomorrow's: tonight's night number
    length: length,
    phase: fasting ? "fast" : "night",
    iftar: Math.ceil(today.maghrib / minute) * minute,
    suhoorEnds: Math.floor(fajrNext / minute) * minute,
    fastStart: today.fajr,
    fastEnd: today.maghrib,
    target: fasting ? Math.ceil(today.maghrib / minute) * minute : Math.floor(fajrNext / minute) * minute,
    // Eid is the civil date of hijri day length+1; after Maghrib h is tomorrow's.
    eidInDays: length + 1 - h.day + (afterMaghrib ? 1 : 0)
  }
}

// "4:32" for the last minutes of a countdown.
function clockCountdown(ms) {
  var s = Math.max(0, Math.ceil(ms / 1000))
  var m = Math.floor(s / 60), r = s % 60
  return m + ":" + (r < 10 ? "0" : "") + r
}

// Eid greetings: 1 Shawwal and 10 Dhu al-Hijjah.
function eid(h) {
  if (h.month === 10 && h.day === 1) return "Eid al-Fitr"
  if (h.month === 12 && h.day === 10) return "Eid al-Adha"
  return ""
}

// The bar pill: next prayer and its countdown, or the current prayer for its
// first twenty minutes (active: drawn in the accent).
function pill(now, location, opts, hijriOffset) {
  var lang = (opts && opts.lang) || "en"
  var say = function(text) { return digits(text, lang, opts && opts.numerals) }
  if (!location) return { label: "󰖔 " + t(lang, "setLocation"), glyph: "󰖔", active: false, fast: false }
  var lat = location.latitude, lon = location.longitude
  var today = prayerTimes(now, lat, lon, opts)
  var day = today.sunrise !== null && today.maghrib !== null && now >= today.sunrise && now < today.maghrib
  var glyph = day ? "󰖙" : "󰖔"
  var current = currentPrayer(now, today)
  var r = ramadan(now, lat, lon, opts, hijriOffset || 0)
  var window = current && now - today[current] < 20 * 60000
  if (r && current === "maghrib" && window)
    return { label: glyph + " " + t(lang, "iftar") + " " + t(lang, "now"), glyph: glyph, active: true, fast: false }
  if (window)
    return { label: glyph + " " + prayerLabel(current, now, opts && opts.zone, lang) + " " + t(lang, "now"), glyph: glyph, active: true, fast: false }
  // In Ramadan the fast leads, except between Maghrib and Isha's window.
  if (r && (r.phase === "fast" || current === "isha" || current === null || current === "fajr")) {
    var left = r.target - now
    var soon = left <= 10 * 60000
    var name = t(lang, r.phase === "fast" ? "iftar" : "suhoor")
    return { label: glyph + " " + name + " " + say(soon ? clockCountdown(left) : countdown(left)), glyph: glyph, active: false, fast: soon }
  }
  var next = nextPrayer(now, lat, lon, opts)
  return { label: next ? glyph + " " + prayerLabel(next.key, next.time, opts && opts.zone, lang) + " " + say(countdown(next.time - now)) : glyph, glyph: glyph, active: false, fast: false }
}

// ---- Voluntary-prayer windows for the local day containing dayMs.
// ponytail: makruh and Duha use fixed minutes (15 after sunrise, 5 before
// zenith, 15 before Maghrib); the angle-based variants differ by a few minutes.
function prayerWindows(dayMs, lat, lon, opts) {
  var at = function(offset) { return prayerTimes(noonOf(dayMs, offset, opts && opts.zone), lat, lon, opts) }
  var y = at(-1), t = at(0), n = at(1)
  var min = 60000
  var out = { makruh: [], duha: null, lastThird: [], midnight: [] }
  if (t.sunrise !== null) out.makruh.push([t.sunrise, t.sunrise + 15 * min])
  out.makruh.push([t.transit - 5 * min, t.dhuhr])
  if (t.maghrib !== null) out.makruh.push([t.maghrib - 15 * min, t.maghrib])
  if (t.sunrise !== null) out.duha = [t.sunrise + 15 * min, t.transit - 5 * min]
  // The night runs Maghrib to the next Fajr; two nights touch any one day.
  // Midnight halves sunset to sunrise (sunset to Fajr for the Jafari rule).
  var nights = [[y, t], [t, n]]
  for (var i = 0; i < nights.length; i++) {
    var eve = nights[i][0], morn = nights[i][1]
    if (eve.maghrib === null || morn.fajr === null) continue
    var end = t.midnightRule === "jafari" ? morn.fajr : morn.sunrise
    if (eve.sunset !== null && end !== null) out.midnight.push(eve.sunset + (end - eve.sunset) / 2)
    out.lastThird.push([eve.maghrib + (morn.fajr - eve.maghrib) * 2 / 3, morn.fajr])
  }
  return out
}

// ---- The sun and the qibla.

// When, during the local day, the sun's azimuth equals `bearing` while it is
// up. null if it never does.
function sunAtBearing(dayMs, lat, lon, bearing, zone) {
  var start = localMidnight(dayMs, zone), end = nextLocalMidnight(dayMs, zone), step = 10 * 60000
  var f = function(t) { return ((sunPosition(t, lat, lon).azimuth - bearing + 540) % 360) - 180 }
  for (var t = start; t < end; t += step) {
    var a = f(t), b = f(t + step)
    // A sign change through 0, not the ±180 wrap on the far side.
    if ((a < 0) !== (b < 0) && Math.abs(a - b) < 90) {
      var hit = bisect(f, t, t + step)
      if (sunPosition(hit, lat, lon).altitude > 0) return hit
    }
  }
  return null
}

// Today's two qibla-and-sun moments: facing the sun faces the qibla, and
// (the sun opposite) every shadow points to the qibla.
function qiblaSun(dayMs, lat, lon, zone) {
  var b = qibla(lat, lon).bearing
  return { toward: sunAtBearing(dayMs, lat, lon, b, zone), shadows: sunAtBearing(dayMs, lat, lon, (b + 180) % 360, zone) }
}

// The next moment at or after ms when the sun stands at the zenith of
// (lat, lon): its declination crosses lat, and that place reaches solar noon.
function nextZenith(ms, lat, lon) {
  var f = function(t) { return sunEquatorial(t).dec - lat }
  var day = 86400000
  for (var t = ms; t < ms + 370 * day; t += day) {
    if ((f(t) < 0) === (f(t + day) < 0)) continue
    var crossing = bisect(f, t, t + day)
    // Solar noon there nearest the crossing: the hour angle passes 0.
    var noon = Math.round((crossing - (12 - lon / 15) * 3600000) / day) * day + (12 - lon / 15) * 3600000
    var ha = function(x) { return sunPosition(x, lat, lon).hourAngle }
    var transit = bisect(ha, noon - 3600000, noon + 3600000)
    if (transit >= ms) return transit
  }
  return null
}

// The next Rasd al-Qibla: the sun over the Kaaba (shadows everywhere point
// away from it) or over its antipode (shadows point toward it). Returns the
// next one the sun is up for at (lat, lon), or null within a year.
function nextRasd(ms, lat, lon) {
  var events = []
  var over = nextZenith(ms, KAABA.latitude, KAABA.longitude)
  var anti = nextZenith(ms, -KAABA.latitude, KAABA.longitude - 180)
  if (over !== null) events.push({ time: over, kind: "kaaba" })
  if (anti !== null) events.push({ time: anti, kind: "antipode" })
  // The second of each pair, too, in case the first is below this horizon.
  if (over !== null) { var o2 = nextZenith(over + 5 * 86400000, KAABA.latitude, KAABA.longitude); if (o2 !== null) events.push({ time: o2, kind: "kaaba" }) }
  if (anti !== null) { var a2 = nextZenith(anti + 5 * 86400000, -KAABA.latitude, KAABA.longitude - 180); if (a2 !== null) events.push({ time: a2, kind: "antipode" }) }
  events.sort(function(a, b) { return a.time - b.time })
  for (var i = 0; i < events.length; i++)
    if (sunPosition(events[i].time, lat, lon).altitude > 0) return events[i]
  return null
}

// ---- Places, from assets/cities.json (GeoNames, CC-BY 4.0; see NOTICE.md).
// Rows: [name, region, country, lat, lon, zone index, aliases...], biggest first.

function parseCities(raw) {
  try { return JSON.parse(raw) } catch (e) { return null }
}

// English country names for the picker, without loading the places list.
var COUNTRY_NAMES = { AU: "Australia", SA: "Saudi Arabia", AE: "the UAE", QA: "Qatar", KW: "Kuwait", BH: "Bahrain", OM: "Oman",
  YE: "Yemen", EG: "Egypt", SD: "Sudan", LY: "Libya", PK: "Pakistan", IN: "India", BD: "Bangladesh", AF: "Afghanistan",
  IR: "Iran", MY: "Malaysia", ID: "Indonesia", SG: "Singapore", BN: "Brunei", TR: "Türkiye", FR: "France", RU: "Russia",
  US: "the US", CA: "Canada", MA: "Morocco", DZ: "Algeria", TN: "Tunisia", PT: "Portugal", JO: "Jordan", GB: "the UK" }
function countryName(code) { return COUNTRY_NAMES[code] || code }

function cityLocation(db, row) {
  return { name: row[0], region: row[1], country: row[2], countryName: (db && db.countries[row[2]]) || row[2],
           latitude: row[3], longitude: row[4], tz: (db && db.zones && db.zones[row[5]]) || "" }
}

// Up to `limit` places whose name or any alias starts with the query (any
// script, any case), then ones containing it, biggest first.
function searchCities(db, query, limit) {
  var q = String(query || "").trim().toLowerCase()
  if (!db || q.length < 2) return []
  limit = limit || 6
  var starts = [], contains = []
  for (var i = 0; i < db.cities.length && starts.length < limit; i++) {
    var row = db.cities[i], hit = 0
    for (var j = 0; j < row.length; j++) {
      if (j >= 1 && j <= 5) continue
      var n = String(row[j]).toLowerCase()
      if (n.indexOf(q) === 0) { hit = 2; break }
      if (hit === 0 && n.indexOf(q) > 0) hit = 1
    }
    if (hit === 2) starts.push(cityLocation(db, row))
    else if (hit === 1 && contains.length < limit) contains.push(cityLocation(db, row))
  }
  return starts.concat(contains).slice(0, limit)
}

// The nearest listed place: gives a weather.json location its country.
function nearestCity(db, lat, lon) {
  if (!db) return null
  var best = null, bestD = Infinity, k = Math.cos(lat * RAD)
  for (var i = 0; i < db.cities.length; i++) {
    var r = db.cities[i], dy = r[3] - lat, dx = (r[4] - lon) * k
    var d = dx * dx + dy * dy
    if (d < bestD) { bestD = d; best = r }
  }
  return best ? cityLocation(db, best) : null
}

// ---- Language. Short strings only, the ones a person reads at a glance; the
// explanatory sentences stay English rather than risk a wrong one in a prayer
// app. Keys: the six prayers, then the UI words.
var STRINGS = {
  en: { jumuah: "Jumu'ah", fajr: "Fajr", sunrise: "Sunrise", dhuhr: "Dhuhr", asr: "Asr", maghrib: "Maghrib", isha: "Isha",
        now: "now", iftar: "Iftar", suhoor: "Suhoor", setLocation: "set location", estimated: "estimated",
        ramadan: "Ramadan", eidFitr: "Eid al-Fitr", eidAdha: "Eid al-Adha", wherePray: "Where do you pray?" },
  ar: { jumuah: "الجمعة", fajr: "الفجر", sunrise: "الشروق", dhuhr: "الظهر", asr: "العصر", maghrib: "المغرب", isha: "العشاء",
        now: "الآن", iftar: "الإفطار", suhoor: "السحور", setLocation: "حدّد الموقع", estimated: "تقديري",
        ramadan: "رمضان", eidFitr: "عيد الفطر", eidAdha: "عيد الأضحى", wherePray: "أين تصلّي؟" },
  ur: { jumuah: "جمعہ", fajr: "فجر", sunrise: "طلوعِ آفتاب", dhuhr: "ظہر", asr: "عصر", maghrib: "مغرب", isha: "عشاء",
        now: "ابھی", iftar: "افطار", suhoor: "سحری", setLocation: "مقام منتخب کریں", estimated: "اندازاً",
        ramadan: "رمضان", eidFitr: "عید الفطر", eidAdha: "عید الاضحیٰ", wherePray: "آپ کہاں نماز پڑھتے ہیں؟" },
  fa: { jumuah: "جمعه", fajr: "صبح", sunrise: "طلوع آفتاب", dhuhr: "ظهر", asr: "عصر", maghrib: "مغرب", isha: "عشا",
        now: "اکنون", iftar: "افطار", suhoor: "سحر", setLocation: "تعیین مکان", estimated: "تقریبی",
        ramadan: "رمضان", eidFitr: "عید فطر", eidAdha: "عید قربان", wherePray: "کجا نماز می‌خوانید؟" },
  tr: { jumuah: "Cuma", fajr: "İmsak", sunrise: "Güneş", dhuhr: "Öğle", asr: "İkindi", maghrib: "Akşam", isha: "Yatsı",
        now: "şimdi", iftar: "İftar", suhoor: "Sahur", setLocation: "konum seç", estimated: "tahmini",
        ramadan: "Ramazan", eidFitr: "Ramazan Bayramı", eidAdha: "Kurban Bayramı", wherePray: "Nerede namaz kılıyorsunuz?" },
  ms: { jumuah: "Jumaat", fajr: "Subuh", sunrise: "Syuruk", dhuhr: "Zohor", asr: "Asar", maghrib: "Maghrib", isha: "Isyak",
        now: "sekarang", iftar: "Berbuka", suhoor: "Sahur", setLocation: "tetapkan lokasi", estimated: "anggaran",
        ramadan: "Ramadan", eidFitr: "Aidilfitri", eidAdha: "Aidiladha", wherePray: "Di manakah anda bersolat?" },
  id: { jumuah: "Jumat", fajr: "Subuh", sunrise: "Terbit", dhuhr: "Zuhur", asr: "Asar", maghrib: "Magrib", isha: "Isya",
        now: "sekarang", iftar: "Buka puasa", suhoor: "Sahur", setLocation: "atur lokasi", estimated: "perkiraan",
        ramadan: "Ramadan", eidFitr: "Idulfitri", eidAdha: "Iduladha", wherePray: "Di mana Anda salat?" },
  fr: { jumuah: "Joumou'a", fajr: "Fajr", sunrise: "Lever du soleil", dhuhr: "Dhuhr", asr: "Asr", maghrib: "Maghrib", isha: "Isha",
        now: "maintenant", iftar: "Iftar", suhoor: "Suhour", setLocation: "choisir le lieu", estimated: "estimé",
        ramadan: "Ramadan", eidFitr: "Aïd al-Fitr", eidAdha: "Aïd al-Adha", wherePray: "Où priez-vous ?" },
  bn: { jumuah: "জুমা", fajr: "ফজর", sunrise: "সূর্যোদয়", dhuhr: "যোহর", asr: "আসর", maghrib: "মাগরিব", isha: "এশা",
        now: "এখন", iftar: "ইফতার", suhoor: "সেহরি", setLocation: "অবস্থান ঠিক করুন", estimated: "আনুমানিক",
        ramadan: "রমজান", eidFitr: "ঈদুল ফিতর", eidAdha: "ঈদুল আযহা", wherePray: "আপনি কোথায় নামাজ পড়েন?" }
}
var RTL = ["ar", "ur", "fa"]
var HIJRI_MONTHS_LOCAL = {
  ar: ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة", "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"],
  tr: ["Muharrem", "Safer", "Rebiülevvel", "Rebiülahir", "Cemaziyelevvel", "Cemaziyelahir", "Recep", "Şaban", "Ramazan", "Şevval", "Zilkade", "Zilhicce"],
  ms: ["Muharam", "Safar", "Rabiulawal", "Rabiulakhir", "Jamadilawal", "Jamadilakhir", "Rejab", "Syaaban", "Ramadan", "Syawal", "Zulkaedah", "Zulhijjah"],
  id: ["Muharram", "Safar", "Rabiulawal", "Rabiulakhir", "Jumadilawal", "Jumadilakhir", "Rajab", "Syakban", "Ramadan", "Syawal", "Zulkaidah", "Zulhijah"]
}
HIJRI_MONTHS_LOCAL.ur = HIJRI_MONTHS_LOCAL.ar
HIJRI_MONTHS_LOCAL.fa = HIJRI_MONTHS_LOCAL.ar

// "auto" → the system locale's language when Falak has it, else English.
function language(setting, localeName) {
  var want = setting && setting !== "auto" ? setting : String(localeName || "en").split(/[_-]/)[0]
  return STRINGS[want] ? want : "en"
}
// A prayer's name on the day containing ms: Dhuhr is Jumu'ah on Fridays.
function prayerLabel(key, ms, zone, lang) {
  if (key === "dhuhr" && ms && civil(ms, zone).getUTCDay() === 5) key = "jumuah"
  return t(lang || "en", key)
}

function t(lang, key) { return (STRINGS[lang] || STRINGS.en)[key] || STRINGS.en[key] || key }
function isRtl(lang) { return RTL.indexOf(lang) >= 0 }
function hijriMonth(lang, month) { return (HIJRI_MONTHS_LOCAL[lang] || HIJRI_MONTHS)[month - 1] }

// Native digits: Arabic-Indic for Arabic, Eastern Arabic-Indic for Persian
// and Urdu. numerals: "auto" (native for ar and fa), "native" or "western".
function digits(text, lang, numerals) {
  var native = numerals === "native" || ((!numerals || numerals === "auto") && (lang === "ar" || lang === "fa"))
  if (!native || !isRtl(lang)) return text
  var set = lang === "ar" ? "٠١٢٣٤٥٦٧٨٩" : "۰۱۲۳۴۵۶۷۸۹"
  return String(text).replace(/[0-9]/g, function(d) { return set[+d] })
}

// ---- The new crescent: where it can be seen (Odeh's criterion, as used by
// the Islamic Crescents' Observation Project).

// Moon's horizontal parallax, degrees (Astronomical Almanac low precision).
function moonParallax(ms) {
  var T = (julianDay(ms) - 2451545.0) / 36525
  return 0.9508 + 0.0518 * cosd(134.9 + 477198.85 * T) + 0.0095 * cosd(259.2 - 413335.38 * T)
    + 0.0078 * cosd(235.7 + 890534.23 * T) + 0.0028 * cosd(269.9 + 954397.70 * T)
}

// The evening of civil day `dayNum` (UTC date) at (lat, lon): sunset, moonset,
// Yallop's best time (sunset + 4/9 of the lag), and there Odeh's
// V = ARCV − (7.1651 − 6.3226W + 0.7319W² − 0.1018W³), W the topocentric
// crescent width in arcminutes. Zones: A naked eye (V ≥ 5.65), B optical aid
// and maybe naked eye (≥ 2), C optical aid only (≥ −0.96), D not visible.
// conjunction: the new moon's instant, or null to find the one before sunset.
function crescentAt(dayNum, lat, lon, conjunction) {
  var hour = 3600000
  // Sunset: the transit near local noon, then the hour angle at −0.833°.
  var noon = dayNum * 86400000 + (12 - lon / 15) * hour
  var transit = noon - sunPosition(noon, lat, lon).hourAngle / 15 * hour
  var dec = sunEquatorial(transit).dec
  var cosH = (sind(-0.833) - sind(lat) * sind(dec)) / (cosd(lat) * cosd(dec))
  if (cosH < -1 || cosH > 1) return { zone: "D", reason: "no sunset" }
  var sunset = transit + Math.acos(cosH) * DEG / 15 * hour
  if (conjunction === null || conjunction === undefined) conjunction = previousConjunction(sunset)
  if (conjunction > sunset) return { zone: "D", reason: "before the new moon", sunset: sunset }
  // Moonset: from the moon's hour angle at sunset, at ~14.5°/h.
  // The precise moon (the eclipse theory): Odeh's thresholds turn on fractions
  // of a degree, more than the low-precision moon's 0.3°.
  var pb = preciseBodies(sunset)
  var mt = topocentric(pb.moon.lambda, pb.moon.beta, pb.moon.km, false, pb.eps, pb.gast, lat, lon)
  var m = { altitude: mt.alt, hourAngle: ((pb.gast + lon - mt.ra) % 360 + 540) % 360 - 180 }
  if (m.altitude < 0) return { zone: "D", reason: "moon sets first", sunset: sunset }
  var mEq = { dec: mt.dec }
  var cosHm = (sind(0.125) - sind(lat) * sind(mEq.dec)) / (cosd(lat) * cosd(mEq.dec))
  var Hm0 = cosHm < -1 ? 180 : (cosHm > 1 ? 0 : Math.acos(cosHm) * DEG)
  var lag = Math.max(0, (Hm0 - m.hourAngle) / 14.5 * hour)
  var best = sunset + lag * 4 / 9
  var bb = preciseBodies(best)
  var st = topocentric(bb.sun.lambda, 0, bb.sun.au, true, bb.eps, bb.gast, lat, lon)
  var mb = topocentric(bb.moon.lambda, bb.moon.beta, bb.moon.km, false, bb.eps, bb.gast, lat, lon)
  var s = { altitude: st.alt, azimuth: st.az }, mo = { altitude: mb.alt, azimuth: mb.az }
  var arcv = mo.altitude - s.altitude
  var arcl = Math.acos(sind(s.altitude) * sind(mo.altitude) + cosd(s.altitude) * cosd(mo.altitude) * cosd(mo.azimuth - s.azimuth)) * DEG
  var par = Math.asin(6378.14 / bb.moon.km) * DEG
  var sd = 0.2725 * par * (1 + sind(mo.altitude) * sind(par)) * 60
  var w = sd * (1 - cosd(arcl))
  var v = arcv - (7.1651 - 6.3226 * w + 0.7319 * w * w - 0.1018 * w * w * w)
  return { zone: v >= 5.65 ? "A" : v >= 2 ? "B" : v >= -0.96 ? "C" : "D", v: v, arcv: arcv, w: w,
           sunset: sunset, moonset: sunset + lag, best: best, age: (best - conjunction) / hour }
}

// A world grid of zones for the evening of `dayNum` (cells `step`° square,
// latitudes ±60, where crescent sighting is practical). Rows north to south.
function crescentMap(dayNum, step) {
  step = step || 4
  var conj = previousConjunction((dayNum + 1) * 86400000)
  var rows = []
  for (var lat = 60 - step / 2; lat > -60; lat -= step) {
    var row = ""
    for (var lon = -180 + step / 2; lon < 180; lon += step) row += crescentAt(dayNum, lat, lon, conj).zone
    rows.push(row)
  }
  return { dayNumber: dayNum, step: step, conjunction: conj, rows: rows }
}

// ---- Adhan and reminders. Off until turned on in the panel.

var DEFAULT_ALERTS = {
  enabled: false,
  prayers: { fajr: "adhan", sunrise: "off", dhuhr: "adhan", asr: "adhan", maghrib: "adhan", isha: "adhan" },
  before: 0,          // minutes; 0: no reminder before each prayer
  suhoor: 30,         // in Ramadan, minutes before suhoor ends; 0: none
  eclipses: "notify", // a visible eclipse's start: "notify" or "off"
  kahf: "off",
  iqama: 0,           // minutes before your mosque's iqama (needs a timetable); 0: none
  focus: 0,           // prayer focus: minutes of Do Not Disturb and paused media from each start; 0: off        // Surah al-Kahf reminder: "off", "thursday" (after Maghrib) or "friday" (2 h before Jumu'ah)
  sound: "makkah",
  fajrSound: "fajr-ali-mulla",
  volume: 80,
  dua: true           // the du'a after the adhan: a notification when one plays to the end, and in the panel
}

// The du'a after the adhan (Sahih al-Bukhari 614). The English is our own plain rendering.
var DUA_AFTER_ADHAN = {
  arabic: "اللَّهُمَّ رَبَّ هَذِهِ الدَّعْوَةِ التَّامَّةِ، وَالصَّلَاةِ الْقَائِمَةِ، آتِ مُحَمَّدًا الْوَسِيلَةَ وَالْفَضِيلَةَ، وَابْعَثْهُ مَقَامًا مَحْمُودًا الَّذِي وَعَدْتَهُ",
  english: "O Allah, Lord of this perfect call and of the prayer about to begin, grant Muhammad al-Wasilah and excellence, and raise him to the praised station You promised him.",
  source: "Sahih al-Bukhari 614"
}
// Fajr ones include "as-salatu khayrun min an-nawm"; any can be chosen for either.
var ADHANS = [
  { id: "makkah", name: "Makkah (3:44)" },
  { id: "madinah", name: "Madinah, Muhammad Marwan Qassas (4:10)" },
  { id: "al-aqsa", name: "Masjid al-Aqsa (4:08)" },
  { id: "mishary", name: "Mishary Alafasy (4:18)" },
  { id: "fajr-ali-mulla", name: "Fajr: Ali Ahmed Mulla, Makkah (4:36)" },
  { id: "fajr-madinah", name: "Fajr: Madinah, Muhammad Marwan Qassas (5:04)" },
  { id: "fajr-mishary", name: "Fajr: Mishary Alafasy (3:25)" },
  { id: "aaqib-azeez", name: "Aaqib Azeez (1:27)" },
  { id: "sabah-fakhri", name: "Sabah Fakhri (2:38)" },
  { id: "beautiful-adhan", name: "\"Beautiful adhan\" (2:34)" }
]

// Settings over the defaults, so a partial or old setting still works.
function alertSettings(raw) {
  var a = {}, k
  for (k in DEFAULT_ALERTS) a[k] = DEFAULT_ALERTS[k]
  a.prayers = {}
  for (k in DEFAULT_ALERTS.prayers) a.prayers[k] = DEFAULT_ALERTS.prayers[k]
  if (raw && typeof raw === "object") {
    for (k in raw) if (k !== "prayers" && raw[k] !== undefined && raw[k] !== null) a[k] = raw[k]
    if (raw.prayers) for (k in raw.prayers) a.prayers[k] = raw.prayers[k]
  }
  return a
}

// "2026-10-06" on the place's clock.
function dateKey(ms, zone) {
  var c = civil(ms, zone), m = c.getUTCMonth() + 1, d = c.getUTCDate()
  return c.getUTCFullYear() + "-" + (m < 10 ? "0" : "") + m + "-" + (d < 10 ? "0" : "") + d
}

// What to announce today and tomorrow, from two minutes ago on, in time order:
// { key, time, headline, body, sound (adhan id or ""), kind }. Times are the
// ones the panel shows (starts rounded up, sunrise down).
// eclipses: from nextEclipses(), computed by the caller (it is the costly part).
// iqama: a parsed mosque timetable (parseIqama), for the iqama reminder.
function alertEvents(now, location, opts, rawAlerts, hijriOffset, eclipses, iqama) {
  var a = alertSettings(rawAlerts)
  if (!a.enabled || !location) return []
  var zone = opts && opts.zone, out = [], minute = 60000
  var place = location.name ? " · " + location.name : ""
  for (var d = 0; d < 2; d++) {
    var noon = noonOf(now, d, zone)
    var t = prayerTimes(noon, location.latitude, location.longitude, opts)
    var day = dateKey(noon, zone)
    var inRamadan = hijriDate(noon, hijriOffset || 0, false, zone).month === 9
    for (var i = 0; i < PRAYERS.length; i++) {
      var key = PRAYERS[i], mode = a.prayers[key]
      if (!mode || mode === "off" || t[key] === null) continue
      var at = key === "sunrise" ? Math.floor(t[key] / minute) * minute : Math.ceil(t[key] / minute) * minute
      var name = key === "maghrib" && inRamadan ? "Maghrib · iftar" : prayerLabel(key, noon, zone, "en")
      out.push({ key: day + "-" + key + "-start", time: at, kind: "start",
                 headline: key === "sunrise" ? "Sunrise: the time for Fajr has ended" : name,
                 body: hhmm(at, zone) + place,
                 sound: mode === "adhan" && key !== "sunrise" ? (key === "fajr" ? a.fajrSound : a.sound) : "" })
      if (a.before > 0 && key !== "sunrise")
        out.push({ key: day + "-" + key + "-before", time: at - a.before * minute, kind: "before",
                   headline: name + " in " + a.before + " minutes", body: hhmm(at, zone) + place, sound: "" })
    }
    // Your mosque's iqama, a few minutes ahead.
    if (a.iqama > 0 && iqama) {
      for (var q = 0; q < PRAYERS.length; q++) {
        var qk = PRAYERS[q]
        if (qk === "sunrise") continue
        var at2 = iqamaTime(iqama, qk, noon, zone)
        if (at2 === null) continue
        out.push({ key: day + "-" + qk + "-iqama", time: at2 - a.iqama * minute, kind: "iqama",
                   headline: prayerLabel(qk, noon, zone, "en") + " iqama in " + a.iqama + " minutes", body: hhmm(at2, zone) + place, sound: "" })
      }
    }
    // Surah al-Kahf, read from Thursday's Maghrib to Friday's.
    var weekday = civil(noon, zone).getUTCDay()
    if (a.kahf === "thursday" && weekday === 4 && t.maghrib !== null)
      out.push({ key: day + "-kahf", time: Math.ceil(t.maghrib / minute) * minute + 30 * minute, kind: "kahf",
                 headline: "Surah al-Kahf", body: "Friday has begun: it is sunnah to read al-Kahf before Friday's Maghrib", sound: "" })
    if (a.kahf === "friday" && weekday === 5)
      out.push({ key: day + "-kahf", time: Math.ceil(t.dhuhr / minute) * minute - 2 * 60 * minute, kind: "kahf",
                 headline: "Surah al-Kahf", body: "It is sunnah to read al-Kahf on Friday, before Maghrib", sound: "" })
    if (inRamadan && a.suhoor > 0 && t.fajr !== null) {
      var ends = Math.floor(t.fajr / minute) * minute
      out.push({ key: day + "-suhoor", time: ends - a.suhoor * minute, kind: "suhoor",
                 headline: "Suhoor ends in " + a.suhoor + " minutes", body: hhmm(ends, zone) + place, sound: "" })
    }
  }
  if (a.eclipses === "notify" && eclipses) {
    for (var j = 0; j < eclipses.length; j++) {
      var ec = eclipses[j]
      if (!ec.visible || !ec.start) continue
      var begins = ec.kind === "lunar" && ec.partialStart ? ec.partialStart : ec.start
      var what = ec.type.charAt(0).toUpperCase() + ec.type.slice(1) + " " + ec.kind + " eclipse"
      out.push({ key: dateKey(begins, zone) + "-eclipse-" + ec.kind, time: Math.floor(begins / minute) * minute, kind: "eclipse",
                 headline: what + " begins", body: "Deepest at " + hhmm(ec.max, zone) + " · salat al-" + (ec.kind === "solar" ? "kusuf" : "khusuf") + " is sunnah", sound: "" })
    }
  }
  return out.filter(function(e) { return e.time > now - 2 * minute })
             .sort(function(x, y) { return x.time - y.time })
}

// Events due at `now`: reached, under two minutes late (after a suspend, a
// stale adhan stays silent), and not yet fired by this instance.
function dueAlerts(events, now, fired) {
  return events.filter(function(e) { return e.time <= now && now - e.time < 2 * 60000 && !(fired && fired[e.key]) })
}


// ---- Eclipses. The precise moon: Meeus, Astronomical Algorithms ch. 47
// (ELP-2000/82 truncated, ~10" in longitude), tables as ported by the
// astronomia library (MIT, © 2013 Sonia Keys, 2016 commenthol). The sun:
// Meeus ch. 25. Both in apparent coordinates of date (nutation, aberration),
// on Terrestrial Time.

// TT − UT, seconds. ponytail: a constant near its 2024-2028 value; replace
// with a table if dates far from now matter.
var DELTA_T = 69.2

var MOON_LR = [
  [0,0,1,0,6288774,-20905355],
  [2,0,-1,0,1274027,-3699111],
  [2,0,0,0,658314,-2955968],
  [0,0,2,0,213618,-569925],
  [0,1,0,0,-185116,48888],
  [0,0,0,2,-114332,-3149],
  [2,0,-2,0,58793,246158],
  [2,-1,-1,0,57066,-152138],
  [2,0,1,0,53322,-170733],
  [2,-1,0,0,45758,-204586],
  [0,1,-1,0,-40923,-129620],
  [1,0,0,0,-34720,108743],
  [0,1,1,0,-30383,104755],
  [2,0,0,-2,15327,10321],
  [0,0,1,2,-12528,0],
  [0,0,1,-2,10980,79661],
  [4,0,-1,0,10675,-34782],
  [0,0,3,0,10034,-23210],
  [4,0,-2,0,8548,-21636],
  [2,1,-1,0,-7888,24208],
  [2,1,0,0,-6766,30824],
  [1,0,-1,0,-5163,-8379],
  [1,1,0,0,4987,-16675],
  [2,-1,1,0,4036,-12831],
  [2,0,2,0,3994,-10445],
  [4,0,0,0,3861,-11650],
  [2,0,-3,0,3665,14403],
  [0,1,-2,0,-2689,-7003],
  [2,0,-1,2,-2602,0],
  [2,-1,-2,0,2390,10056],
  [1,0,1,0,-2348,6322],
  [2,-2,0,0,2236,-9884],
  [0,1,2,0,-2120,5751],
  [0,2,0,0,-2069,0],
  [2,-2,-1,0,2048,-4950],
  [2,0,1,-2,-1773,4130],
  [2,0,0,2,-1595,0],
  [4,-1,-1,0,1215,-3958],
  [0,0,2,2,-1110,0],
  [3,0,-1,0,-892,3258],
  [2,1,1,0,-810,2616],
  [4,-1,-2,0,759,-1897],
  [0,2,-1,0,-713,-2117],
  [2,2,-1,0,-700,2354],
  [2,1,-2,0,691,0],
  [2,-1,0,-2,596,0],
  [4,0,1,0,549,-1423],
  [0,0,4,0,537,-1117],
  [4,-1,0,0,520,-1571],
  [1,0,-2,0,-487,-1739],
  [2,1,0,-2,-399,0],
  [0,0,2,-2,-381,-4421],
  [1,1,1,0,351,0],
  [3,0,-2,0,-340,0],
  [4,0,-3,0,330,0],
  [2,-1,2,0,327,0],
  [0,2,1,0,-323,1165],
  [1,1,-1,0,299,0],
  [2,0,3,0,294,0],
  [2,0,-1,-2,0,8752]
]
var MOON_B = [
  [0,0,0,1,5128122],
  [0,0,1,1,280602],
  [0,0,1,-1,277693],
  [2,0,0,-1,173237],
  [2,0,-1,1,55413],
  [2,0,-1,-1,46271],
  [2,0,0,1,32573],
  [0,0,2,1,17198],
  [2,0,1,-1,9266],
  [0,0,2,-1,8822],
  [2,-1,0,-1,8216],
  [2,0,-2,-1,4324],
  [2,0,1,1,4200],
  [2,1,0,-1,-3359],
  [2,-1,-1,1,2463],
  [2,-1,0,1,2211],
  [2,-1,-1,-1,2065],
  [0,1,-1,-1,-1870],
  [4,0,-1,-1,1828],
  [0,1,0,1,-1794],
  [0,0,0,3,-1749],
  [0,1,-1,1,-1565],
  [1,0,0,1,-1491],
  [0,1,1,1,-1475],
  [0,1,1,-1,-1410],
  [0,1,0,-1,-1344],
  [1,0,0,-1,-1335],
  [0,0,3,1,1107],
  [4,0,0,-1,1021],
  [4,0,-1,1,833],
  [0,0,1,-3,777],
  [4,0,-2,1,671],
  [2,0,0,-3,607],
  [2,0,2,-1,596],
  [2,-1,1,-1,491],
  [2,0,-2,1,-451],
  [0,0,3,-1,439],
  [2,0,2,1,422],
  [2,0,-3,-1,421],
  [2,1,-1,1,-366],
  [2,1,0,1,-351],
  [4,0,0,1,331],
  [2,-1,1,1,315],
  [2,-2,0,-1,302],
  [0,0,1,3,-283],
  [2,1,1,-1,-229],
  [1,1,0,-1,223],
  [1,1,0,1,223],
  [0,1,-2,-1,-220],
  [2,1,-1,-1,-220],
  [1,0,1,1,-185],
  [2,-1,-2,-1,181],
  [0,1,2,1,-177],
  [4,0,-2,-1,176],
  [4,-1,-1,-1,166],
  [1,0,1,-1,-164],
  [4,0,1,-1,132],
  [1,0,-1,-1,-119],
  [4,-1,0,-1,115],
  [2,-2,0,1,107]
]

function nutation(T) {
  var om = 125.04452 - 1934.136261 * T, L = 280.4665 + 36000.7698 * T, Lm = 218.3165 + 481267.8813 * T
  return { dpsi: (-17.20 * sind(om) - 1.32 * sind(2 * L) - 0.23 * sind(2 * Lm) + 0.21 * sind(2 * om)) / 3600,
           deps: (9.20 * cosd(om) + 0.57 * cosd(2 * L) + 0.10 * cosd(2 * Lm) - 0.09 * cosd(2 * om)) / 3600 }
}

// Apparent geocentric sun and moon at UT ms: ecliptic λ, β (deg), distances,
// true obliquity, and the Greenwich apparent sidereal time (deg).
function preciseBodies(ms) {
  var T = (julianDay(ms + DELTA_T * 1000) - 2451545.0) / 36525
  var nu = nutation(T)
  var eps = 23.4392911 - 0.0130042 * T + nu.deps
  // Sun (ch. 25).
  var L0 = 280.46646 + 36000.76983 * T + 0.0003032 * T * T
  var M = 357.52911 + 35999.05029 * T - 0.0001537 * T * T
  var e = 0.016708634 - 0.000042037 * T
  var C = (1.914602 - 0.004817 * T) * sind(M) + (0.019993 - 0.000101 * T) * sind(2 * M) + 0.000289 * sind(3 * M)
  var R = 1.000001018 * (1 - e * e) / (1 + e * cosd(M + C))
  var sunLon = norm360(L0 + C + nu.dpsi - 20.4898 / 3600 / R)
  // Moon (ch. 47).
  var Lp = 218.3164477 + 481267.88123421 * T - 0.0015786 * T * T
  var D = 297.8501921 + 445267.1114034 * T - 0.0018819 * T * T
  var Ms = 357.5291092 + 35999.0502909 * T
  var Mm = 134.9633964 + 477198.8675055 * T + 0.0087414 * T * T
  var F = 93.272095 + 483202.0175233 * T - 0.0036539 * T * T
  var a1 = 119.75 + 131.849 * T, a2 = 53.09 + 479264.29 * T, a3 = 313.45 + 481266.484 * T
  var E = 1 - 0.002516 * T - 0.0000074 * T * T
  var sl = 3958 * sind(a1) + 1962 * sind(Lp - F) + 318 * sind(a2), sr = 0
  var sb = -2235 * sind(Lp) + 382 * sind(a3) + 175 * sind(a1 - F) + 175 * sind(a1 + F) + 127 * sind(Lp - Mm) - 115 * sind(Lp + Mm)
  for (var i = 0; i < MOON_LR.length; i++) {
    var r = MOON_LR[i], arg = D * r[0] + Ms * r[1] + Mm * r[2] + F * r[3], k = Math.pow(E, Math.abs(r[1]))
    sl += r[4] * k * sind(arg); sr += r[5] * k * cosd(arg)
  }
  for (var j = 0; j < MOON_B.length; j++) {
    var b = MOON_B[j]
    sb += b[4] * Math.pow(E, Math.abs(b[1])) * sind(D * b[0] + Ms * b[1] + Mm * b[2] + F * b[3])
  }
  var moonDist = 385000.56 + sr / 1000
  var Tu = (julianDay(ms) - 2451545.0) / 36525
  var gast = norm360(280.46061837 + 360.98564736629 * (julianDay(ms) - 2451545.0) + 0.000387933 * Tu * Tu + nu.dpsi * cosd(eps))
  return { eps: eps, gast: gast,
           sun: { lambda: sunLon, beta: 0, au: R },
           moon: { lambda: norm360(Lp + sl / 1e6 + nu.dpsi), beta: sb / 1e6, km: moonDist } }
}

// Topocentric right ascension / declination (deg) of a body at `km` (or AU),
// seen from (lat, lon) at sea level (Meeus ch. 40), plus its altitude.
function topocentric(lambda, beta, dist, isAu, eps, gast, lat, lon) {
  var ra = Math.atan2(sind(lambda) * cosd(eps) - Math.tan(beta * RAD) * sind(eps), cosd(lambda)) * DEG
  var dec = Math.asin(sind(beta) * cosd(eps) + cosd(beta) * sind(eps) * sind(lambda)) * DEG
  var sinPi = isAu ? sind(8.794 / 3600) / dist : 6378.14 / dist
  var u = Math.atan(0.99664719 * Math.tan(lat * RAD))
  var rs = 0.99664719 * Math.sin(u), rc = Math.cos(u)
  var H = gast + lon - ra
  var dra = Math.atan2(-rc * sinPi * sind(H), cosd(dec) - rc * sinPi * cosd(H)) * DEG
  var dec2 = Math.atan2((sind(dec) - rs * sinPi) * cosd(dra), cosd(dec) - rc * sinPi * cosd(H)) * DEG
  var H2 = H - dra
  var alt = Math.asin(sind(lat) * sind(dec2) + cosd(lat) * cosd(dec2) * cosd(H2)) * DEG
  var az = norm360(Math.atan2(sind(H2), cosd(H2) * sind(lat) - Math.tan(dec2 * RAD) * cosd(lat)) * DEG + 180)
  return { ra: ra + dra, dec: dec2, alt: alt, az: az }
}

function separation(ra1, dec1, ra2, dec2) {
  var h = Math.pow(sind((dec2 - dec1) / 2), 2) + cosd(dec1) * cosd(dec2) * Math.pow(sind((ra2 - ra1) / 2), 2)
  return 2 * Math.asin(Math.sqrt(Math.min(1, h))) * DEG
}

// Sun and moon as seen from (lat, lon): separation and radii, degrees.
function solarDisks(ms, lat, lon) {
  var b = preciseBodies(ms)
  var s = topocentric(b.sun.lambda, 0, b.sun.au, true, b.eps, b.gast, lat, lon)
  var m = topocentric(b.moon.lambda, b.moon.beta, b.moon.km, false, b.eps, b.gast, lat, lon)
  var rs = 959.63 / 3600 / b.sun.au
  var rm = 358473400 / b.moon.km / 3600 * (1 + sind(m.alt) * 6378.14 / b.moon.km)
  return { d: separation(s.ra, s.dec, m.ra, m.dec), rs: rs, rm: rm, sunAlt: s.alt }
}

// The local solar eclipse around the new moon `conj` (ms), or null.
// magnitude: the fraction of the sun's diameter covered at maximum.
function solarEclipseAt(conj, lat, lon) {
  if (Math.abs(preciseBodies(conj).moon.beta) > 1.6) return null
  var minute = 60000, step = 2 * minute
  var gap = function(t) { var x = solarDisks(t, lat, lon); return x.d - (x.rs + x.rm) }
  var best = null
  for (var t = conj - 5 * 3600000; t <= conj + 5 * 3600000; t += step) {
    var x = solarDisks(t, lat, lon)
    if (!best || x.d - (x.rs + x.rm) < best.g) best = { t: t, g: x.d - (x.rs + x.rm) }
  }
  if (best.g >= 0) return null
  // Refine the maximum (golden-section on the separation), then the contacts.
  var lo = best.t - step, hi = best.t + step
  for (var k = 0; k < 40; k++) {
    var m1 = lo + (hi - lo) * 0.382, m2 = lo + (hi - lo) * 0.618
    if (solarDisks(m1, lat, lon).d < solarDisks(m2, lat, lon).d) hi = m2; else lo = m1
  }
  var tmax = (lo + hi) / 2, at = solarDisks(tmax, lat, lon)
  var start = bisect(gap, tmax - 4 * 3600000, tmax), end = bisect(gap, tmax, tmax + 4 * 3600000)
  var central = at.d < Math.abs(at.rm - at.rs)
  var cgap = function(t) { var x = solarDisks(t, lat, lon); return x.d - Math.abs(x.rm - x.rs) }
  var out = { kind: "solar", type: !central ? "partial" : (at.rm > at.rs ? "total" : "annular"),
              magnitude: (at.rs + at.rm - at.d) / (2 * at.rs), start: start, max: tmax, end: end, sunAlt: at.sunAlt }
  if (central) { out.centralStart = bisect(cgap, tmax - 20 * minute, tmax); out.centralEnd = bisect(cgap, tmax, tmax + 20 * minute) }
  // Seen only while the sun is up.
  out.visible = solarDisks(start, lat, lon).sunAlt > -0.833 || at.sunAlt > -0.833 || solarDisks(end, lat, lon).sunAlt > -0.833
  return out
}

// The moon against Earth's shadow, geocentric (Danjon's enlargement, 1/85).
function lunarShadow(ms) {
  var b = preciseBodies(ms)
  var pm = Math.asin(6378.14 / b.moon.km) * DEG
  var ps = 8.794 / 3600 / b.sun.au, ss = 959.63 / 3600 / b.sun.au
  var rm = 358473400 / b.moon.km / 3600
  var d = Math.acos(Math.max(-1, Math.min(1, cosd(b.moon.beta) * cosd(b.moon.lambda - b.sun.lambda - 180)))) * DEG
  var k = 1 + 1 / 85
  return { d: d, rm: rm, umbra: k * pm - ss + ps, penumbra: k * pm + ss + ps }
}

// The lunar eclipse at the full moon nearest `ms`, or null. Times are global;
// visible: the moon is above the horizon at (lat, lon) at some point of it.
function lunarEclipseAt(full, lat, lon) {
  var f = function(t) { var x = lunarShadow(t); return x.d }
  var lo = full - 4 * 3600000, hi = full + 4 * 3600000
  for (var k = 0; k < 50; k++) {
    var m1 = lo + (hi - lo) * 0.382, m2 = lo + (hi - lo) * 0.618
    if (f(m1) < f(m2)) hi = m2; else lo = m1
  }
  var tmax = (lo + hi) / 2, x = lunarShadow(tmax)
  var pen = (x.penumbra + x.rm - x.d) / (2 * x.rm), umb = (x.umbra + x.rm - x.d) / (2 * x.rm)
  if (pen <= 0) return null
  var contact = function(radius, sign) {
    var g = function(t) { var y = lunarShadow(t); return y.d - (sign > 0 ? y[radius] + y.rm : y[radius] - y.rm) }
    return [bisect(g, tmax - 5 * 3600000, tmax), bisect(g, tmax, tmax + 5 * 3600000)]
  }
  var out = { kind: "lunar", type: umb >= 1 ? "total" : (umb > 0 ? "partial" : "penumbral"),
              magnitude: umb, penumbralMagnitude: pen, max: tmax }
  var p = contact("penumbra", 1); out.start = p[0]; out.end = p[1]
  if (umb > 0) { var u = contact("umbra", 1); out.partialStart = u[0]; out.partialEnd = u[1] }
  if (umb >= 1) { var t2 = contact("umbra", -1); out.totalStart = t2[0]; out.totalEnd = t2[1] }
  out.visible = false
  for (var t = out.start; t <= out.end; t += 10 * 60000)
    if (moonPosition(t, lat, lon).altitude > 0) { out.visible = true; break }
  return out
}

// The full moon (opposition) nearest `ms`, within two weeks.
function fullMoonNear(ms) {
  var day = 86400000
  var c = previousConjunction(ms + SYNODIC_MONTH / 2 * day)
  var guess = c + SYNODIC_MONTH / 2 * day
  if (Math.abs(guess - ms) > SYNODIC_MONTH / 2 * day) guess -= SYNODIC_MONTH * day
  var fe = function(t) { return moonPhase(t).elongation - 180 }
  return bisect(fe, guess - 2 * day, guess + 2 * day)
}

// The next eclipses (solar and lunar) from `ms`, up to `count`, looking at
// most `months` ahead, each with its local circumstances at (lat, lon).
function nextEclipses(ms, lat, lon, count, months) {
  var out = [], day = 86400000
  var conj = previousConjunction(ms)
  for (var i = 0; i < (months || 24) && out.length < (count || 6); i++) {
    var full = fullMoonNear(conj + SYNODIC_MONTH / 2 * day)
    var s = solarEclipseAt(conj, lat, lon)
    if (s && s.end > ms) { s.global = solarEclipseType(conj); out.push(s) }
    else if (!s && Math.abs(preciseBodies(conj).moon.beta) < 1.6) out.push({ kind: "solar", type: "elsewhere", global: solarEclipseType(conj), max: conj, visible: false })
    var l = lunarEclipseAt(full, lat, lon)
    if (l && l.end > ms && out.length < (count || 6)) out.push(l)
    conj = previousConjunction(conj + 31 * day)
  }
  return out.sort(function(a, b) { return a.max - b.max })
}

// Earth-fixed position of the sun and moon at `ms`, in Earth radii (x to
// longitude 0, z to the north pole).
function earthFixed(ms) {
  var b = preciseBodies(ms), R = 6378.14
  var vec = function(lambda, beta, dist) {
    var ra = Math.atan2(sind(lambda) * cosd(b.eps) - Math.tan(beta * RAD) * sind(b.eps), cosd(lambda)) * DEG
    var dec = Math.asin(sind(beta) * cosd(b.eps) + cosd(beta) * sind(b.eps) * sind(lambda)) * DEG
    var h = ra - b.gast
    return [dist * cosd(dec) * cosd(h), dist * cosd(dec) * sind(h), dist * sind(dec)]
  }
  return { sun: vec(b.sun.lambda, 0, b.sun.au * 149597870.7 / R), moon: vec(b.moon.lambda, b.moon.beta, b.moon.km / R) }
}

var MOON_RADIUS_ER = 1737.4 / 6378.14, SUN_RADIUS_ER = 696000 / 6378.14

// The moon's shadow at `ms`: its axis (u, from the sun through the moon M),
// the cone slopes, how far the axis passes from Earth's centre, and where it
// meets the ground (null if it misses) with the umbra's radius there
// (negative: the antumbra, an annular eclipse). Earth radii.
function shadowAxis(ms) {
  var p = earthFixed(ms), M = p.moon, S = p.sun
  var u = [M[0] - S[0], M[1] - S[1], M[2] - S[2]], dist = Math.sqrt(u[0] * u[0] + u[1] * u[1] + u[2] * u[2])
  u = [u[0] / dist, u[1] / dist, u[2] / dist]
  var mu = M[0] * u[0] + M[1] * u[1] + M[2] * u[2], mm = M[0] * M[0] + M[1] * M[1] + M[2] * M[2]
  var out = { M: M, S: S, u: u, mu: mu, miss: Math.sqrt(Math.max(0, mm - mu * mu)),
              tanP: (SUN_RADIUS_ER + MOON_RADIUS_ER) / dist, tanU: (SUN_RADIUS_ER - MOON_RADIUS_ER) / dist, ground: null, umbra: 0 }
  var disc = mu * mu - mm + 1
  if (disc > 0) {
    var s = -mu - Math.sqrt(disc)
    out.ground = [M[0] + s * u[0], M[1] + s * u[1], M[2] + s * u[2]]
    out.umbra = MOON_RADIUS_ER - s * out.tanU
  }
  return out
}

// What a solar eclipse near the new moon `conj` is for the Earth as a whole:
// "total", "annular" or "partial" (no central path), at its greatest.
function solarEclipseType(conj) {
  var best = null
  for (var t = conj - 4 * 3600000; t <= conj + 4 * 3600000; t += 5 * 60000) {
    var ax = shadowAxis(t)
    if (!best || ax.miss < best.miss) best = ax
  }
  return !best.ground ? "partial" : best.umbra > 0 ? "total" : "annular"
}

// Where on Earth an eclipse is seen. Solar: rows of the deepest magnitude
// per cell ("0" none, "1" < 0.3, "2" < 0.6, "3" deeper) and the central path
// as [lat, lon, width in degrees, total?] points. Lunar: "2" where the moon is up at
// maximum, "1" where it is up for some of the umbral (or penumbral) phase.
// ponytail: a spherical Earth, no refraction, and the path width measured
// across the shadow axis (the ground path is wider where the sun is low):
// good to a cell, which is what a panel map shows.
function eclipseMap(e, step) {
  step = step || 3
  var cells = [], rows = []
  for (var lat = 90 - step / 2; lat > -90; lat -= step) {
    var row = []
    for (var lon = -180 + step / 2; lon < 180; lon += step) row.push([cosd(lat) * cosd(lon), cosd(lat) * sind(lon), sind(lat), 0])
    cells.push(row)
  }
  var dot = function(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2] }
  var out = { kind: e.kind, step: step, rows: rows, path: [] }
  if (e.kind === "lunar") {
    var t0 = e.partialStart || e.start, t1 = e.partialEnd || e.end, moons = []
    for (var k = 0; k <= 8; k++) moons.push(earthFixed(t0 + (t1 - t0) * k / 8).moon)
    var atMax = earthFixed(e.max).moon
    for (var r = 0; r < cells.length; r++) {
      var s = ""
      for (var c = 0; c < cells[r].length; c++) {
        var up = dot(cells[r][c], atMax) > 0 ? 2 : 0
        for (var j = 0; !up && j < moons.length; j++) if (dot(cells[r][c], moons[j]) > 0) up = 1
        s += up
      }
      rows.push(s)
    }
    return out
  }
  var Rm = MOON_RADIUS_ER
  for (var t = e.max - 4 * 3600000; t <= e.max + 4 * 3600000; t += 4 * 60000) {
    var ax = shadowAxis(t), M = ax.M, S = ax.S, u = ax.u, tanP = ax.tanP, tanU = ax.tanU, mu = ax.mu
    if (ax.miss > 1 + Rm - mu * tanP) continue       // the penumbra misses Earth
    var sl = Math.sqrt(dot(S, S)), sunDir = [S[0] / sl, S[1] / sl, S[2] / sl]
    for (var r2 = 0; r2 < cells.length; r2++) for (var c2 = 0; c2 < cells[r2].length; c2++) {
      var P = cells[r2][c2]
      if (dot(P, sunDir) <= 0) continue
      var q = [P[0] - M[0], P[1] - M[1], P[2] - M[2]], z = dot(q, u)
      var d = Math.sqrt(Math.max(0, dot(q, q) - z * z)), lp = Rm + z * tanP, lu = Rm - z * tanU
      if (d < lp) P[3] = Math.max(P[3], Math.min(1, (lp - d) / (lp + lu)))
    }
    // The shadow axis meets the ground: a point of the central path.
    if (ax.ground) out.path.push([Math.asin(ax.ground[2]) * DEG, Math.atan2(ax.ground[1], ax.ground[0]) * DEG, 2 * Math.abs(ax.umbra) * DEG, ax.umbra > 0])
  }
  for (var r3 = 0; r3 < cells.length; r3++) {
    var s3 = ""
    for (var c3 = 0; c3 < cells[r3].length; c3++) { var m = cells[r3][c3][3]; s3 += m <= 0 ? "0" : m < 0.3 ? "1" : m < 0.6 ? "2" : "3" }
    rows.push(s3)
  }
  return out
}

// ---- The sky dome: planets from JPL's approximate Keplerian elements
// (valid 1800-2050, arcminute-level), stars from assets/sky.json. Positions
// are J2000; at a dome's scale the 0.4° of precession since does not show.

// Heliocentric ecliptic (J2000) position of a body, AU.
function heliocentric(el, ms) {
  var T = (julianDay(ms) - 2451545.0) / 36525
  var a = el.a + el.da * T, e = el.e + el.de * T, i = el.i + el.di * T
  var L = el.L + el.dL * T, W = el.W + el.dW * T, N = el.N + el.dN * T
  var w = W - N, M = norm360(L - W)
  if (M > 180) M -= 360
  // Kepler's equation, in degrees as JPL gives it.
  var eDeg = e * DEG, E = M + eDeg * sind(M)
  for (var k = 0; k < 10; k++) E += (M - (E - eDeg * sind(E))) / (1 - e * cosd(E))
  var xp = a * (cosd(E) - e), yp = a * Math.sqrt(1 - e * e) * sind(E)
  return {
    x: (cosd(w) * cosd(N) - sind(w) * sind(N) * cosd(i)) * xp + (-sind(w) * cosd(N) - cosd(w) * sind(N) * cosd(i)) * yp,
    y: (cosd(w) * sind(N) + sind(w) * cosd(N) * cosd(i)) * xp + (-sind(w) * sind(N) + cosd(w) * cosd(N) * cosd(i)) * yp,
    z: sind(w) * sind(i) * xp + cosd(w) * sind(i) * yp
  }
}

// Geocentric J2000 right ascension and declination of planet `key`.
function planetRaDec(planets, key, ms) {
  var p = heliocentric(planets[key], ms), earth = heliocentric(planets.ter, ms)
  var x = p.x - earth.x, y = p.y - earth.y, z = p.z - earth.z, eps = 23.43928
  var ye = y * cosd(eps) - z * sind(eps), ze = y * sind(eps) + z * cosd(eps)
  return { ra: norm360(Math.atan2(ye, x) * DEG), dec: Math.atan2(ze, Math.sqrt(x * x + ye * ye)) * DEG,
           au: Math.sqrt(x * x + y * y + z * z) }
}

// Stereographic projection of the sky from the zenith: horizon at radius 1,
// north up and east to the LEFT, as you see it lying on your back facing north.
// Points below the horizon return null unless allowBelow.
function domeXY(altitude, azimuth, allowBelow) {
  if (altitude < 0 && !allowBelow) return null
  var r = Math.tan((90 - altitude) * RAD / 2)
  return { x: -r * sind(azimuth), y: -r * cosd(azimuth) }
}

// ---- Travel: how far the place shown is from home. ~80 km is the common
// reckoning for a journey that shortens prayer; schools differ on it.
var TRAVEL_KM = 80
function travel(location, home) {
  if (!location || !home) return null
  var p1 = location.latitude * RAD, p2 = home.latitude * RAD, dl = (home.longitude - location.longitude) * RAD
  var h = Math.pow(Math.sin((p2 - p1) / 2), 2) + Math.cos(p1) * Math.cos(p2) * Math.pow(Math.sin(dl / 2), 2)
  var km = 2 * 6371.0088 * Math.asin(Math.sqrt(h))
  return { km: km, away: km >= TRAVEL_KM }
}

// ---- Your mosque's timetable: a CSV dropped in ~/.local/share/falak/mosque.
// Header names the columns (date, fajr/subh, dhuhr/zuhr, asr, maghrib, isha,
// optional jumuah), comma- or semicolon-separated; dates YYYY-MM-DD or
// DD/MM/YYYY; times 24-hour or with am/pm. These are iqama (congregation)
// times. Returns { "2026-10-06": { fajr: "05:45", ... } }, or null.
var IQAMA_COLUMNS = { date: "date", day: "date", fajr: "fajr", subh: "fajr", subuh: "fajr", dhuhr: "dhuhr", zuhr: "dhuhr",
  zuhur: "dhuhr", duhr: "dhuhr", asr: "asr", maghrib: "maghrib", isha: "isha", ishaa: "isha", jumuah: "jumuah",
  "jumu'ah": "jumuah", jummah: "jumuah", juma: "jumuah" }

function iqamaClock(raw) {
  var m = /^\s*(\d{1,2})[:.](\d{2})\s*(am|pm)?\s*$/i.exec(String(raw || ""))
  if (!m) return null
  var h = +m[1], mi = +m[2], ap = (m[3] || "").toLowerCase()
  if (ap === "pm" && h < 12) h += 12
  if (ap === "am" && h === 12) h = 0
  if (h > 23 || mi > 59) return null
  return (h < 10 ? "0" : "") + h + ":" + (mi < 10 ? "0" : "") + mi
}

function parseIqama(text) {
  var lines = String(text || "").split(/\r?\n/).filter(function(l) { return l.trim() !== "" })
  if (lines.length < 2) return null
  var sep = lines[0].indexOf(";") >= 0 && lines[0].indexOf(",") < 0 ? ";" : ","
  var head = lines[0].split(sep).map(function(h) { return IQAMA_COLUMNS[h.trim().toLowerCase().replace(/[^a-z']/g, "")] || "" })
  if (head.indexOf("date") < 0) return null
  var out = {}, n = 0
  for (var i = 1; i < lines.length; i++) {
    var cells = lines[i].split(sep), row = {}, date = null
    for (var c = 0; c < head.length; c++) {
      var v = (cells[c] || "").trim()
      if (head[c] === "date") {
        var iso = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(v), dmy = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(v)
        if (iso) date = iso[1] + "-" + ("0" + iso[2]).slice(-2) + "-" + ("0" + iso[3]).slice(-2)
        else if (dmy) date = dmy[3] + "-" + ("0" + dmy[2]).slice(-2) + "-" + ("0" + dmy[1]).slice(-2)
      } else if (head[c]) {
        var clock = iqamaClock(v)
        if (clock) row[head[c]] = clock
      }
    }
    if (date) { out[date] = row; n++ }
  }
  return n ? out : null
}

// The iqama of `key` on the day containing ms, as epoch ms, or null.
function iqamaTime(table, key, ms, zone) {
  if (!table) return null
  var day = table[dateKey(ms, zone)]
  var clock = day && (key === "dhuhr" && civil(ms, zone).getUTCDay() === 5 && day.jumuah ? day.jumuah : day[key])
  if (!clock) return null
  var c = civil(ms, zone), hm = clock.split(":")
  return zonedTime(c.getUTCFullYear(), c.getUTCMonth(), c.getUTCDate(), +hm[0], +hm[1], 0, zone)
}

// ---- The private prayer journal: { "2026-10-06": ["fajr", "dhuhr"], ... },
// kept only in ~/.local/share/falak/journal.json. No streaks, no scores.
var JOURNAL_PRAYERS = ["fajr", "dhuhr", "asr", "maghrib", "isha"]
function journalToggle(journal, day, key) {
  var out = {}, k
  for (k in (journal || {})) out[k] = journal[k].slice()
  var list = out[day] || []
  var i = list.indexOf(key)
  if (i >= 0) list.splice(i, 1); else list.push(key)
  list.sort(function(a, b) { return JOURNAL_PRAYERS.indexOf(a) - JOURNAL_PRAYERS.indexOf(b) })
  if (list.length) out[day] = list; else delete out[day]
  return out
}
function parseJournal(raw) {
  try {
    var j = JSON.parse(raw || "{}"), out = {}
    for (var d in j) if (/^\d{4}-\d{2}-\d{2}$/.test(d) && Array.isArray(j[d]))
      out[d] = j[d].filter(function(k) { return JOURNAL_PRAYERS.indexOf(k) >= 0 })
    return out
  } catch (e) { return {} }
}

// ---- The coming year's sacred days as an iCalendar file (all-day events).
function icsSacredDays(fromDay, hijriOffset) {
  var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Falak//Omarchy//EN", "CALSCALE:GREGORIAN"]
  var stamp = function(dayNum) { var d = new Date(dayNum * 86400000); return d.getUTCFullYear() + ("0" + (d.getUTCMonth() + 1)).slice(-2) + ("0" + d.getUTCDate()).slice(-2) }
  var day = fromDay, end = fromDay + 365
  while (day < end) {
    var m = hijriMonthOfDay(day, hijriOffset || 0)
    for (var i = 0; i < m.days.length; i++) {
      var dd = m.days[i]
      if (dd.dayNumber < fromDay || dd.dayNumber >= end) continue
      for (var k = 0; k < dd.notes.events.length; k++) {
        var ev = dd.notes.events[k]
        lines.push("BEGIN:VEVENT", "UID:falak-" + stamp(dd.dayNumber) + "-" + k + "@omarchy",
                   "DTSTAMP:" + stamp(fromDay) + "T000000Z",
                   "DTSTART;VALUE=DATE:" + stamp(dd.dayNumber), "DTEND;VALUE=DATE:" + stamp(dd.dayNumber + 1),
                   "SUMMARY:" + ev.replace(/[,;]/g, "\\$&") + " (" + dd.day + " " + m.monthName.replace(/[,;]/g, "\\$&") + " " + m.year + ")", "END:VEVENT")
      }
    }
    day = m.start + m.length
  }
  lines.push("END:VCALENDAR")
  return lines.join("\r\n") + "\r\n"
}
