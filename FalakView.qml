import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Everything the panel shows, as a plain Item: no window, no bar, no IPC.
// FalakPanel.qml puts it in a KeyboardPanel; dev/ renders it headless.
// The centrepiece is the sun's altitude through the day: every prayer is the
// moment that curve crosses a line.
Item {
  id: root

  property double now: Date.now()
  property var location: null
  property var opts: ({ method: "Karachi", asr: "hanafi" })
  property int hijriOffset: 0
  property string family: Style.font.family
  // Open (or being rendered): only then do the year playback and repaints run.
  property bool active: true
  // The places list (assets/cities.json, parsed), when loaded; and whether
  // the location is Falak's own or follows the weather widget's.
  property var cities: null
  property bool ownLocation: false

  // ---- Choosing a place. The view only asks; FalakPanel saves the answer.
  signal locationPicked(var place)    // null: follow the weather widget again
  // Editing ended (place picked, method chosen, calendar or crescent closed):
  // FalakPanel takes the keyboard back, or a hidden field keeps it.
  signal keysReleased()
  onEditingChanged: if (!editing) keysReleased()
  signal citiesWanted()
  property bool searching: false
  property string query: ""
  property int selected: 0
  readonly property var results: searching ? Model.searchCities(cities, query, 6) : []
  // One of the views that replace the sun's day (each owns the keyboard).
  readonly property bool overlayOpen: choosingMethod || calendarOpen || crescentOpen || alertsOpen || eclipsesOpen || helpOpen || tasbihOpen || adjustOpen || teachOpen || journalOpen
  readonly property bool editing: searching || overlayOpen || !location

  // ---- Choosing a method and Asr school. The view asks; FalakPanel saves.
  signal settingPicked(string key, var value)
  property string country: ""
  property bool choosingMethod: false
  property int methodIndex: 0
  readonly property var methodRows: ["auto"].concat(Model.methodKeys())
  readonly property bool showSky: !!location && !overlayOpen

  // ---- Tasbih after prayer: 33 subhan Allah, 33 al-hamdu lillah, 34 Allahu akbar.
  property bool tasbihOpen: false
  property int tasbihCount: 0
  readonly property var tasbihSteps: [["سبحان الله", "Subhan Allah", 33], ["الحمد لله", "Al-hamdu lillah", 33], ["الله أكبر", "Allahu akbar", 34]]
  readonly property int tasbihStep: tasbihCount < 33 ? 0 : tasbihCount < 66 ? 1 : tasbihCount < 100 ? 2 : 3
  readonly property int tasbihInStep: tasbihStep === 0 ? tasbihCount : tasbihStep === 1 ? tasbihCount - 33 : tasbihStep === 2 ? tasbihCount - 66 : 34
  function startTasbih() { closeOverlays(); tasbihOpen = true; Qt.callLater(function() { tasbihKeys.forceActiveFocus() }) }
  function tasbihTap() {
    if (tasbihCount >= 100) return
    tasbihCount += 1
    if (tasbihCount === 33 || tasbihCount === 66 || tasbihCount === 100) tasbihPulse.restart()
  }

  // ---- Adjustments: height above sea level, minute offsets, home.
  property bool adjustOpen: false
  property var adjust: ({ elevation: 0, offsets: {} })
  property var home: null
  // The day's verse: one of assets/verses.json, by the date shown.
  property var verses: null
  readonly property var verse: verses && verses.length ? verses[((Model.dayNumber(viewNoon, zone) % verses.length) + verses.length) % verses.length] : null
  property var iqama: null
  property string mosqueFile: ""
  signal mosqueFolderRequested()
  readonly property var trip: Model.travel(location, home)
  readonly property var adjustRows: {
    var mins = []
    for (var m = -10; m <= 10; m++) mins.push([m, (m > 0 ? "+" : "") + m + " min"])
    var heights = [0, 25, 50, 100, 150, 200, 250, 300, 400, 500, 750, 1000, 1500, 2000, 2500, 3000].map(function(h) { return [h, h + " m"] })
    var rows = [{ field: "elevation", label: "Height above sea level", options: heights, cycle: true, hint: "sunrise and Maghrib" }]
    ;["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"].forEach(function(k) {
      rows.push({ field: "offsets." + k, label: Model.LABELS[k] + " offset", options: mins, cycle: true })
    })
    rows.push({ field: "mosque", label: "Mosque timetable: " + (mosqueFile ? mosqueFile : "none (add a CSV)"),
                actions: [["Open the folder", "mosquefolder"]] })
    rows.push({ field: "home", label: "Home: " + (home ? home.name : "not set"),
                actions: location ? [["Make " + location.name + " home", "sethome"]].concat(home ? [["Clear", "clearhome"]] : []) : [] })
    return rows
  }
  function adjustValue(field) {
    var p = field.split(".")
    if (p[0] === "offsets") return (adjust.offsets && adjust.offsets[p[1]]) || 0
    return adjust[field] || 0
  }
  function setAdjust(field, value) {
    var next = { elevation: adjust.elevation || 0, offsets: {} }
    for (var k in (adjust.offsets || {})) next.offsets[k] = adjust.offsets[k]
    var p = field.split(".")
    if (p[0] === "offsets") next.offsets[p[1]] = value
    else next[field] = value
    adjust = next
    settingPicked("adjust", next)
  }
  function startAdjust() { closeOverlays(); adjustOpen = true; Qt.callLater(function() { adjustList.takeKeys() }) }

  // ---- Why the times move: five steps, the stick and its shadow at the centre.
  property bool teachOpen: false
  property int teachStep: 0
  property real gnomonFraction: 0.5      // 0: Dhuhr, 1: Maghrib, for the shadow drawing
  property bool gnomonPlaying: false
  readonly property var teachSteps: [
    ["Every prayer is the sun", "Each prayer time is a moment the sun reaches a certain place in the sky. The curve in the panel is the sun's height through the day; every dot on it is a prayer. Change the place or the date and the curve changes, so the times do too."],
    ["Fajr and Isha: the sky's own light", "Before sunrise and after sunset the sky glows because sunlight still reaches the air above you. Fajr begins when the sun is about 18° below the horizon (your method decides the exact angle), and Isha when the glow is gone at the other end of the night."],
    ["Dhuhr: the sun at its highest", "Just after the sun crosses the meridian, the highest point of its arc. At that moment every shadow is at its shortest and points away from the sun's side of the sky: south of the equator, shadows point south."],
    ["Asr: when shadows grow", "Watch the stick below. At noon its shadow is shortest. Asr begins when the shadow has grown by the stick's own length beyond that (the Shafi'i, Maliki and Hanbali reckoning), or by twice its length (the Hanafi). Space plays the afternoon."],
    ["Maghrib, and why it all drifts", "Maghrib is sunset. Through the year the sun's path climbs and sinks with the seasons (it moves 47° between the solstices), so the whole curve moves: long summer days, short winter ones, and every prayer time with them. Space in the main view plays the year."]
  ]
  function startTeach() { closeOverlays(); teachStep = 0; teachOpen = true; Qt.callLater(function() { teachKeys.forceActiveFocus() }) }
  Timer {
    interval: 40
    running: root.gnomonPlaying && root.teachOpen
    repeat: true
    onTriggered: { root.gnomonFraction += 0.006; if (root.gnomonFraction >= 1) { root.gnomonFraction = 1; root.gnomonPlaying = false } }
  }

  // ---- The private prayer journal. Off until turned on; stored only on this machine.
  property bool journalOn: false
  property var journal: ({})
  signal journalSaved(var journal)
  signal icsRequested(string text, string fileName)
  signal journalErased()
  property bool journalOpen: false
  property int journalRow: 0
  property int journalBack: 0           // days before today being marked (0..6)
  property bool eraseArmed: false
  readonly property double journalNoon: Model.noonOf(now, -journalBack, zone)
  readonly property string journalDay: Model.dateKey(journalNoon, zone)
  function startJournal() { closeOverlays(); journalRow = 0; journalBack = 0; eraseArmed = false; journalOpen = true; Qt.callLater(function() { journalKeys.forceActiveFocus() }) }
  function journalToggle(key) {
    if (!journalOn) return
    journal = Model.journalToggle(journal, journalDay, key)
    journalSaved(journal)
  }

  // ---- Every key, in one place ("?"), so the footer can stay short.
  property bool helpOpen: false
  function startHelp() { closeOverlays(); helpOpen = true; Qt.callLater(function() { helpKeys.forceActiveFocus() }) }
  function closeOverlays() {
    stopSearch()
    choosingMethod = false; calendarOpen = false; crescentOpen = false; alertsOpen = false; eclipsesOpen = false; helpOpen = false
    tasbihOpen = false; adjustOpen = false; teachOpen = false; journalOpen = false
  }
  readonly property var keyHelp: [
    ["←/→", "a day back or forward"], ["↑/↓", "a month back or forward"], ["space", "play the year"], ["t", "back to today"],
    ["c", "the hijri calendar"], ["n", "where the new crescent can be seen"], ["e", "eclipses"], ["s", "the sky, full screen"],
    ["a", "adhan, reminders and alerts"], ["p", "choose a place"], ["m", "calculation method and Asr school"],
    ["w", "why the times move: a short guided tour"], ["r", "your private prayer journal (off until you turn it on)"], ["d", "tasbih: 33, 33, 34 after prayer"], ["o", "adjust: height, minute offsets, home"], ["?", "this list"], ["esc", "back, or close the panel"]
  ]

  // ---- Eclipses: the next six, seen from here. Computed when opened (~0.2 s).
  property bool eclipsesOpen: false
  property var eclipses: []
  // The chosen one (↑/↓) and where on Earth it is seen (~0.1 s each).
  property int eclipseIndex: 0
  readonly property var eclipseMap: eclipsesOpen && eclipses[eclipseIndex] ? Model.eclipseMap(eclipses[eclipseIndex], 3) : null
  function startEclipses() {
    stopSearch(); choosingMethod = false; calendarOpen = false; crescentOpen = false; alertsOpen = false
    landWanted()
    eclipses = location ? Model.nextEclipses(now, lat, lon, 6, 30) : []
    eclipseIndex = 0
    eclipsesOpen = true
    Qt.callLater(function() { eclipseKeys.forceActiveFocus() })
  }
  function eclipseTitle(e) {
    var cap = function(w) { return w.charAt(0).toUpperCase() + w.slice(1) }
    if (e.kind === "lunar") return cap(e.type) + " lunar eclipse"
    // Solar: what the Earth gets, and what this place gets when it differs.
    if (e.type === "elsewhere") return cap(e.global) + " solar eclipse, seen elsewhere on Earth"
    if (!e.visible || e.type === e.global) return cap(e.global) + " solar eclipse"
    return cap(e.global) + " solar eclipse, " + e.type + " here"
  }
  function eclipseText(e) {
    var hm = function(t) { return Model.hhmm(t, root.zone) }
    if (e.type === "elsewhere") return "The moon passes in front of the sun, but not from " + (location ? location.name : "here") + "."
    if (!e.visible) return e.kind === "solar" ? "Not visible here: the sun is down." : "Not visible here: the moon is below the horizon."
    if (e.kind === "lunar") {
      if (e.type === "penumbral") return "Visible here, but faint: the moon only dims slightly. " + hm(e.start) + " to " + hm(e.end) + ", deepest at " + hm(e.max) + "."
      var t = "Visible here. The shadow's bite begins at " + hm(e.partialStart)
      if (e.type === "total") t += "; the moon is fully in shadow " + hm(e.totalStart) + " to " + hm(e.totalEnd) + " (" + Math.round((e.totalEnd - e.totalStart) / 60000) + " min)"
      else t += "; at most " + Math.round(e.magnitude * 100) + "% of its width in shadow, at " + hm(e.max)
      return t + "; it ends at " + hm(e.partialEnd) + "."
    }
    var t2 = "Visible here, " + hm(e.start) + " to " + hm(e.end) + ". At " + hm(e.max) + " the moon covers "
      + Math.round(e.magnitude * 100) + "% of the sun's width, the sun " + Math.round(e.sunAlt) + "° up."
    if (e.type === "total" || e.type === "annular")
      t2 += " " + (e.type === "total" ? "Totality" : "The ring of fire") + ": " + Math.round((e.centralEnd - e.centralStart) / 1000) + " seconds from " + hm(e.centralStart) + "."
    return t2
  }

  // ---- Adhan and reminders: every control lives here, no terminal needed.
  //      The view edits a copy of the settings; FalakPanel saves and schedules.
  property var alerts: Model.alertSettings(null)
  property var nextAlert: null
  signal previewRequested(string sound)
  signal stopRequested()
  signal testRequested()
  signal adhanFolderRequested()
  property var userAdhans: []
  property bool alertsOpen: false
  property alias alertRow: alertsList.current
  readonly property var alertRows: {
    var mode = [["off", "Off"], ["notify", "Notify"], ["adhan", "Adhan"]]
    var adhans = Model.ADHANS.map(function(a) { return [a.id, a.name] })
      .concat(userAdhans.map(function(n) { return ["user:" + n, n.replace(/\.[^.]+$/, "") + " (yours)"] }))
    return [
      { field: "enabled", label: "Announce prayers", options: [[false, "Off"], [true, "On"]] },
      { field: "prayers.fajr", label: "Fajr", options: mode },
      { field: "prayers.sunrise", label: "Sunrise (Fajr ends)", options: mode.slice(0, 2) },
      { field: "prayers.dhuhr", label: "Dhuhr", options: mode },
      { field: "prayers.asr", label: "Asr", options: mode },
      { field: "prayers.maghrib", label: "Maghrib", options: mode },
      { field: "prayers.isha", label: "Isha", options: mode },
      { field: "before", label: "Reminder before each", options: [[0, "Off"], [5, "5 min"], [10, "10 min"], [15, "15 min"], [30, "30 min"]] },
      { field: "suhoor", label: "Ramadan: suhoor ends in", options: [[0, "Off"], [15, "15 min"], [30, "30 min"], [45, "45 min"], [60, "60 min"]] },
      { field: "eclipses", label: "Eclipses (visible here)", options: [["off", "Off"], ["notify", "Notify"]] },
      { field: "kahf", label: "Surah al-Kahf", options: [["off", "Off"], ["thursday", "Thu evening"], ["friday", "Friday"]] },
      { field: "iqama", label: "Before your mosque's iqama", options: [[0, "Off"], [5, "5 min"], [10, "10 min"], [15, "15 min"]] },
      { field: "focus", label: "Prayer focus", options: [[0, "Off"], [10, "10 min"], [15, "15 min"], [20, "20 min"], [30, "30 min"]] },
      { field: "sound", label: "Adhan", options: adhans, cycle: true, hint: "space: listen" },
      { field: "fajrSound", label: "Fajr adhan", options: adhans, cycle: true, hint: "space: listen" },
      { field: "volume", label: "Volume", options: [[25, "25%"], [50, "50%"], [75, "75%"], [80, "80%"], [100, "100%"]] },
      { field: "dua", label: "Du'a after the adhan", options: [[false, "Off"], [true, "On"]] },
      { field: "test", label: "Test now", actions: [["Fire a test alert", "test"], ["Stop sound", "stop"]] },
      { field: "folder", label: "Your own recordings", actions: [["Open my adhans folder", "folder"]] }
    ]
  }
  function alertValue(field) {
    var parts = field.split(".")
    return parts.length === 2 ? alerts[parts[0]][parts[1]] : alerts[field]
  }
  function setAlert(field, value) {
    var next = Model.alertSettings(alerts), parts = field.split(".")
    if (parts.length === 2) next[parts[0]][parts[1]] = value
    else next[field] = value
    alerts = next
    settingPicked("alerts", next)
  }
  function startAlerts() {
    stopSearch(); choosingMethod = false; calendarOpen = false; crescentOpen = false; eclipsesOpen = false
    alertRow = 0
    alertsOpen = true
    Qt.callLater(function() { alertsList.takeKeys() })
  }

  // ---- The new crescent: where on Earth it can be seen, evening by evening.
  property bool crescentOpen: false
  property int crescentEvening: 0          // 0: the evening of the new moon's day (UTC), then +1, +2
  property var land: null                  // assets/land.json, loaded on first use
  signal landWanted()
  // The coming new moon, or one in the last three days.
  readonly property double crescentConj: {
    var c = Model.previousConjunction(now)
    return now - c > 3 * 86400000 ? Model.previousConjunction(c + 31 * 86400000) : c
  }
  readonly property int crescentDay: Math.floor(crescentConj / 86400000) + crescentEvening
  readonly property var crescentMap: crescentOpen ? Model.crescentMap(crescentDay, 5) : null
  readonly property var crescentHere: crescentOpen && location ? Model.crescentAt(crescentDay, lat, lon, crescentConj) : null
  readonly property var crescentMonth: Model.hijriOfDay(Math.floor(crescentConj / 86400000) + 3)
  function startCrescent() {
    stopSearch(); choosingMethod = false; calendarOpen = false; alertsOpen = false; eclipsesOpen = false
    landWanted()
    crescentEvening = 0
    crescentOpen = true
    Qt.callLater(function() { crescentKeys.forceActiveFocus() })
  }
  onCrescentMapChanged: crescentCanvas.requestPaint()
  onLandChanged: { crescentCanvas.requestPaint(); eclipseCanvas.requestPaint() }

  // ---- The hijri calendar: a month grid on the place's own days.
  property bool calendarOpen: false
  property int calDay: 0
  readonly property int todayNumber: Model.dayNumber(now, zone)
  readonly property var calMonth: calendarOpen ? Model.hijriMonthOfDay(calDay, hijriOffset) : null
  readonly property var calSelected: calMonth ? calMonth.days[calDay - calMonth.start] : null
  // Leading blanks so the first day sits under its weekday (locale's week start).
  readonly property int weekStart: Qt.locale().firstDayOfWeek % 7
  readonly property var calCells: {
    if (!calMonth) return []
    var cells = [], blanks = (calMonth.days[0].weekday - weekStart + 7) % 7
    for (var i = 0; i < blanks; i++) cells.push(null)
    return cells.concat(calMonth.days)
  }
  function startCalendar() {
    stopSearch()
    choosingMethod = false
    crescentOpen = false
    alertsOpen = false
    eclipsesOpen = false
    calDay = Model.dayNumber(viewMs, zone)
    calendarOpen = true
    Qt.callLater(function() { calendarKeys.forceActiveFocus() })
  }
  // Same day of the hijri month, one month along (clamped to its length).
  function calMonthStep(dir) {
    if (!calMonth) return
    var day = calDay - calMonth.start
    var target = dir > 0 ? calMonth.start + calMonth.length : calMonth.start - 1
    var next = Model.hijriMonthOfDay(target, hijriOffset)
    calDay = next.start + Math.min(day, next.length - 1)
  }
  function openCalendarDay() {
    calendarOpen = false
    playing = false
    dayOffset = calDay - todayNumber
  }
  readonly property var monthsShort: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  function startMethods() {
    stopSearch()
    methodIndex = opts && opts.auto && opts.auto.method ? 0 : Math.max(0, methodRows.indexOf(opts.method))
    choosingMethod = true
    Qt.callLater(function() { methodList.forceActiveFocus() })
  }
  function pickMethod(key) {
    choosingMethod = false
    settingPicked("method", key)
  }
  function pickAsr(value) { settingPicked("asr", value) }
  readonly property string asrChoice: opts && opts.auto && opts.auto.asr ? "auto" : (opts ? opts.asr : "auto")

  function startSearch(text) {
    citiesWanted()
    searching = true
    query = text || ""
    selected = 0
    Qt.callLater(function() { placeField.text = root.query; placeField.forceActiveFocus() })
  }
  // Clears the field too: hidden, it would still take the next letter typed.
  function stopSearch() { searching = false; query = ""; placeField.text = "" }
  // With no place yet, the panel opens straight into the search field.
  onActiveChanged: if (active && !location) Qt.callLater(function() { placeField.forceActiveFocus() })
  function pick(place) {
    stopSearch()
    locationPicked(place)
  }

  implicitHeight: body.implicitHeight

  // Language: names and short words follow it; Arabic, Urdu and Persian
  // mirror the layout (the sun's chart keeps time running left to right).
  readonly property string lang: opts && opts.lang ? opts.lang : "en"
  function num(text) { return Model.digits(text, lang, opts && opts.numerals) }
  LayoutMirroring.enabled: Model.isRtl(lang)
  LayoutMirroring.childrenInherit: true

  readonly property real lat: location ? location.latitude : 0
  readonly property real lon: location ? location.longitude : 0
  readonly property var today: location ? Model.prayerTimes(now, lat, lon, opts) : null
  readonly property var next: location ? Model.nextPrayer(now, lat, lon, opts) : null

  // ---- The viewed day (the panel can walk away from today).
  property int dayOffset: 0
  property bool playing: false
  // The place's own clock (null: this machine's). Every day boundary and
  // every time shown reads it, so Makkah shows Makkah's day and Makkah's time.
  readonly property var zone: opts && opts.zone ? opts.zone : null
  readonly property double viewMs: Model.shiftDays(now, dayOffset, zone)
  // " time, UTC+3" when the place's clock is not this machine's.
  readonly property string zoneNote: zone && Model.zoneOffset(now, zone) !== Model.zoneOffset(now, null)
    ? " time, " + Model.utcLabel(now, zone) : ""
  readonly property bool viewingToday: dayOffset === 0
  // Noon of the viewed day: changes once a day, so the day's sums (times,
  // curve, windows) are not redone every second while the panel is open.
  readonly property double viewNoon: Model.noonOf(viewMs, 0, zone)
  readonly property var viewTimes: location ? Model.prayerTimes(viewNoon, lat, lon, opts) : null
  readonly property var hijri: location ? Model.hijriDate(viewMs, hijriOffset, viewingToday && today && today.maghrib !== null && now >= today.maghrib, zone) : null
  readonly property var phase: Model.moonPhase(viewMs)
  readonly property var qibla: location ? Model.qibla(lat, lon) : null
  readonly property var sunNow: location ? Model.sunPosition(now, lat, lon) : null
  readonly property var ramadan: location ? Model.ramadan(viewMs, lat, lon, opts, hijriOffset) : null
  readonly property string eid: hijri ? Model.eid(hijri) : ""
  // The half hour after iftar, today only: the dua.
  readonly property bool iftarHour: viewingToday && !!ramadan && ramadan.phase === "night"
    && now >= ramadan.fastEnd && now - ramadan.fastEnd < 30 * 60000
  // The first ten minutes of a prayer, today only: the du'a after the adhan.
  readonly property bool afterAdhan: {
    if (!viewingToday || !today || iftarHour || (alerts && alerts.dua === false)) return false
    var keys = ["fajr", "dhuhr", "asr", "maghrib", "isha"]
    for (var i = 0; i < keys.length; i++)
      if (today[keys[i]] !== null && now >= today[keys[i]] && now - today[keys[i]] < 10 * 60000) return true
    return false
  }
  readonly property var windows: location ? Model.prayerWindows(viewNoon, lat, lon, opts) : null
  readonly property var qiblaSun: location ? Model.qiblaSun(viewNoon, lat, lon, zone) : null
  // Once a day, not once a second: the year-long search is the costliest sum here.
  readonly property double dayKey: Model.localMidnight(now, zone)
  readonly property var rasd: location ? Model.nextRasd(dayKey, lat, lon) : null

  // What the hovered moment falls in, for the readout.
  function windowAt(t) {
    if (!windows) return ""
    var inside = function(w) { return w && t >= w[0] && t < w[1] }
    for (var i = 0; i < windows.makruh.length; i++)
      if (inside(windows.makruh[i])) return ["Makruh: no voluntary prayer while the sun rises", "Makruh: no voluntary prayer at the zenith", "Makruh: no voluntary prayer while the sun sets"][i]
    if (inside(windows.duha)) return "Duha"
    for (var j = 0; j < windows.lastThird.length; j++)
      if (inside(windows.lastThird[j])) return "The last third of the night"
    return ""
  }

  // The sun and moon across the viewed day, sampled every 5 minutes.
  readonly property var curve: {
    if (!location) return null
    var start = Model.localMidnight(viewNoon, zone), end = Model.nextLocalMidnight(viewNoon, zone)
    var sun = [], moon = []
    for (var t = start; t <= end; t += 5 * 60000) {
      sun.push(Model.sunPosition(t, lat, lon).altitude)
      moon.push(Model.moonPosition(t, lat, lon).altitude)
    }
    return { start: start, end: end, sun: sun, moon: moon }
  }
  onCurveChanged: skyCanvas.requestPaint()
  onPhaseChanged: moonCanvas.requestPaint()

  // Space: play the year, a day every 40 ms, and watch the curve breathe.
  // With the bar's animations off, a week every 400 ms instead.
  property bool reducedMotion: false
  Timer {
    interval: root.reducedMotion ? 400 : 40
    running: root.playing && root.active
    repeat: true
    onTriggered: {
      root.dayOffset += root.reducedMotion ? 7 : 1
      if (root.dayOffset >= 365) { root.dayOffset = 0; root.playing = false }
    }
  }

  function walk(days) {
    root.playing = false
    root.dayOffset += days
  }

  // Hover readout over the curve: -1 when the pointer is elsewhere.
  property real hoverFraction: -1

  readonly property color fg: Color.popups.text
  readonly property color dim: Util.alpha(fg, 0.55)
  readonly property color faint: Util.alpha(fg, 0.14)
  readonly property color accent: Color.accent

  // Canvas wants CSS colours; a QML colour with alpha stringifies as #aarrggbb.
  function css(c) {
    c = Qt.color(c)
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + c.a + ")"
  }

  readonly property var rows: ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"]
  // The Asr of the school not in use, shown under the Asr column.
  readonly property string otherAsr: !viewTimes ? "" : num(opts.asr === "standard"
    ? "Hanafi " + Model.hhmm(viewTimes.asrHanafi, zone) : "Standard " + Model.hhmm(viewTimes.asrStandard, zone))

  function viewDateText() {
    return Model.dateText(viewMs, zone)
  }

  // Whoever has the keyboard now. A click anywhere not otherwise taken hands it
  // back, so a view that lost the keyboard (a click away, the other monitor)
  // never leaves the panel deaf: the panel's own keys are off while one is open.
  function refocus() {
    if (searching || !location) placeField.forceActiveFocus()
    else if (choosingMethod) methodList.forceActiveFocus()
    else if (calendarOpen) calendarKeys.forceActiveFocus()
    else if (crescentOpen) crescentKeys.forceActiveFocus()
    else if (eclipsesOpen) eclipseKeys.forceActiveFocus()
    else if (alertsOpen) alertsList.takeKeys()
    else if (adjustOpen) adjustList.takeKeys()
    else if (helpOpen) helpKeys.forceActiveFocus()
    else if (tasbihOpen) tasbihKeys.forceActiveFocus()
    else if (teachOpen) teachKeys.forceActiveFocus()
    else if (journalOpen) journalKeys.forceActiveFocus()
    else keysReleased()
  }
  MouseArea { anchors.fill: parent; onClicked: root.refocus() }

  Column {
    id: body
    width: parent.width
    spacing: Style.space(14)

    // ---- Where do you pray? Offline search over the places list.
    Column {
      visible: root.searching || !root.location
      width: parent.width
      spacing: Style.space(8)
      Component.onCompleted: if (!root.location) root.citiesWanted()

      Text {
        visible: !root.location
        text: Model.t(root.lang, "wherePray")
        color: root.fg
        font.family: root.family
        font.pixelSize: Style.font.heading
        font.bold: true
      }
      Text {
        visible: !root.location
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Type a city. Falak works out the prayer times, the qibla and the local method from there, on this machine."
        color: root.dim
        font.family: root.family
        font.pixelSize: Style.font.bodySmall
      }
      TextField {
        id: placeField
        objectName: "falakPlaceField"
        width: parent.width
        placeholderText: root.cities ? "City, in any script: Lahore, لاهور, Istanbul…" : "Loading places…"
        foreground: root.fg
        font.family: root.family
        onTextChanged: { root.query = text; root.selected = 0; if (!root.searching && text !== "") root.startSearch(text) }
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { if (root.location) root.stopSearch(); else placeField.text = ""; event.accepted = true }
          else if (event.key === Qt.Key_Down) { root.selected = Math.min(root.selected + 1, root.results.length - 1); event.accepted = true }
          else if (event.key === Qt.Key_Up) { root.selected = Math.max(root.selected - 1, 0); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.results.length > 0) root.pick(root.results[root.selected])
            event.accepted = true
          }
        }
      }
      Repeater {
        model: root.results
        Rectangle {
          required property var modelData
          required property int index
          width: parent.width
          height: placeRow.implicitHeight + Style.space(10)
          radius: Style.cornerRadius
          color: index === root.selected ? Style.hoverFillFor(root.fg, root.accent) : "transparent"
          Row {
            id: placeRow
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)
            Text {
              text: modelData.name
              color: index === root.selected ? root.accent : root.fg
              font.family: root.family
              font.pixelSize: Style.font.body
            }
            Text {
              anchors.baseline: parent.children[0].baseline
              text: (modelData.region ? modelData.region + ", " : "") + modelData.countryName
              color: root.dim
              font.family: root.family
              font.pixelSize: Style.font.bodySmall
            }
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: root.selected = index
            onClicked: root.pick(modelData)
          }
        }
      }
      Text {
        visible: root.ownLocation && root.searching
        text: "Or follow the weather widget's location"
        color: root.accent
        font.family: root.family
        font.pixelSize: Style.font.bodySmall
        font.underline: followArea.containsMouse
        MouseArea { id: followArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pick(null) }
      }
    }

    // ---- Header: hijri date and the moon.
    Item {
      visible: !!root.location
      width: parent.width
      height: Math.max(dateColumn.implicitHeight, moonRow.implicitHeight)

      Column {
        id: dateColumn
        anchors.left: parent.left
        width: parent.width - moonRow.width - Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)
        Text {
          text: root.hijri ? root.num(root.hijri.day + " " + Model.hijriMonth(root.lang, root.hijri.month) + " " + root.hijri.year) : ""
          color: root.fg
          font.family: root.family
          font.pixelSize: Style.font.display
          font.bold: true
        }
        Text {
          visible: root.eid !== ""
          text: Model.t(root.lang, root.eid === "Eid al-Fitr" ? "eidFitr" : "eidAdha") + "  ·  عيد مبارك"
          color: root.accent
          font.family: root.family
          font.pixelSize: Style.font.title
        }
        Text {
          // Browsing another day: the offset matters more than the place.
          // Click it to choose another place.
          TapHandler { onTapped: root.startSearch("") }
          HoverHandler { cursorShape: Qt.PointingHandCursor }
          text: root.viewDateText() + "  ·  " + (root.viewingToday ? ((root.location ? root.location.name : "") + root.zoneNote).replace(/ /g, "\u00a0")
            : (root.dayOffset > 0 ? "+" : "") + root.dayOffset + " days")
          width: parent.width
          // Wraps rather than elides: a long weekday plus "Kuala Lumpur time,
          // UTC+8" must not lose the offset.
          wrapMode: Text.Wrap
          color: root.viewingToday ? root.dim : root.accent
          font.family: root.family
          font.pixelSize: Style.font.body
        }
      }

      Row {
        id: moonRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(10)
        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text {
            anchors.right: parent.right
            text: root.phase.name
            color: root.fg
            font.family: root.family
            font.pixelSize: Style.font.body
          }
          Text {
            anchors.right: parent.right
            text: Math.round(root.phase.illumination * 100) + "% lit · day " + Math.floor(root.phase.age + 1) + " of the moon"
            color: root.dim
            font.family: root.family
            font.pixelSize: Style.font.bodySmall
          }
        }
        Canvas {
          id: moonCanvas
          Accessible.role: Accessible.Graphic
          Accessible.name: root.phase.name + ", " + Math.round(root.phase.illumination * 100) + "% lit"
          width: Style.space(40)
          height: width
          anchors.verticalCenter: parent.verticalCenter
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var r = width / 2 - 1, cx = width / 2, cy = height / 2
            ctx.fillStyle = root.css(root.faint)
            ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.fill()
            // Lit limb on the right for a waxing moon seen from the north;
            // the southern hemisphere sees it mirrored.
            var side = (root.phase.waxing ? 1 : -1) * (root.lat < 0 ? -1 : 1)
            var e = 1 - 2 * root.phase.illumination
            ctx.fillStyle = root.css(root.fg)
            ctx.beginPath()
            for (var i = 0; i <= 48; i++) {
              var a = -Math.PI / 2 + Math.PI * i / 48
              ctx.lineTo(cx + side * r * Math.cos(a), cy + r * Math.sin(a))
            }
            for (var j = 0; j <= 48; j++) {
              var b = Math.PI / 2 - Math.PI * j / 48
              ctx.lineTo(cx + side * e * r * Math.cos(b), cy + r * Math.sin(b))
            }
            ctx.closePath()
            ctx.fill()
          }
        }
      }
    }

    // ---- Away from home: a reminder that the traveller's concessions apply.
    Rectangle {
      visible: root.showSky && !!root.trip && root.trip.away
      width: parent.width
      height: tripText.implicitHeight + Style.space(12)
      radius: Style.cornerRadius
      color: Util.alpha(root.accent, 0.08)
      border.width: 1
      border.color: Util.alpha(root.accent, 0.4)
      Text {
        id: tripText
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: Style.space(10); anchors.rightMargin: Style.space(10)
        wrapMode: Text.WordWrap
        color: root.fg
        font.family: root.family
        font.pixelSize: Style.font.bodySmall
        text: !root.trip ? "" : "Travelling: " + Math.round(root.trip.km).toLocaleString(Qt.locale(), "f", 0) + " km from home ("
          + root.home.name + "). A traveller may shorten the four-rak'ah prayers to two (qasr); most schools also allow"
          + " joining Dhuhr with Asr and Maghrib with Isha (jam'), the Hanafi school only at Arafah and Muzdalifah."
          + " A reminder, not a ruling: follow your school."
      }
    }

    // ---- Another day (from the calendar, or walked to): say which, and what it holds.
    Rectangle {
      visible: root.showSky && !root.viewingToday
      width: parent.width
      height: otherDay.implicitHeight + Style.space(12)
      radius: Style.cornerRadius
      color: Util.alpha(root.accent, 0.12)
      border.width: 1
      border.color: Util.alpha(root.accent, 0.5)
      Text {
        id: otherDay
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        wrapMode: Text.WordWrap
        color: root.fg
        font.family: root.family
        font.pixelSize: Style.font.body
        text: {
          if (!root.hijri) return ""
          var n = Model.dayNotes(root.hijri.month, root.hijri.day, Model.civil(root.viewMs, root.zone).getUTCDay())
          var bits = [Model.dateText(root.viewMs, root.zone)]
          bits = bits.concat(n.events)
          if (n.fast === "sunnah") bits.push("Sunnah to fast")
          else if (n.fast === "forbidden") bits.push("No fasting")
          else if (n.fast === "ramadan") bits.push("Ramadan fast")
          return bits.join("  ·  ") + "\nt: back to today  ·  c: the calendar"
        }
      }
    }

    // ---- Ramadan: the day of the month, the fast, the last ten nights.
    Column {
      visible: !!root.ramadan && !root.overlayOpen
      width: parent.width
      spacing: Style.space(8)

      Item {
        width: parent.width
        height: ramadanTitle.implicitHeight
        Text {
          id: ramadanTitle
          anchors.left: parent.left
          text: !root.ramadan ? "" : root.lang === "en"
            ? "Ramadan  ·  " + (root.ramadan.phase === "night" ? "night " : "day ") + root.ramadan.day + " of " + root.ramadan.length
            : Model.t(root.lang, "ramadan") + "  ·  " + root.num(root.ramadan.day + "/" + root.ramadan.length)
          color: root.accent
          font.family: root.family
          font.pixelSize: Style.font.heading
          font.bold: true
        }
        Text {
          anchors.right: parent.right
          anchors.baseline: ramadanTitle.baseline
          text: root.ramadan ? "Eid al-Fitr in " + root.ramadan.eidInDays + (root.ramadan.eidInDays === 1 ? " day" : " days") : ""
          color: root.dim
          font.family: root.family
          font.pixelSize: Style.font.body
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        color: root.fg
        font.family: root.family
        font.pixelSize: Style.font.body
        text: {
          var r = root.ramadan
          if (!r) return ""
          var fast = Model.countdown(r.fastEnd - r.fastStart)
          if (r.phase === "fast")
            return "Fasting " + fast + " today  ·  iftar at " + Model.hhmm(r.iftar, root.zone)
              + (root.viewingToday ? ", in " + Model.countdown(r.iftar - root.now) : "")
          return "Suhoor ends at " + Model.hhmm(r.suhoorEnds, root.zone)
            + (root.viewingToday ? ", in " + Model.countdown(r.suhoorEnds - root.now) : "")
            + (r.day >= 21 && r.day % 2 === 1 ? "  ·  an odd night of the last ten" : "")
        }
      }

      // The last ten nights: odd ones ringed, tonight filled.
      Row {
        visible: !!root.ramadan && root.ramadan.day >= 20
        spacing: Style.space(10)
        Text {
          text: "Last ten nights"
          color: root.dim
          font.family: root.family
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
        Repeater {
          model: root.ramadan ? root.ramadan.length - 20 : 0
          Column {
            required property int index
            readonly property int night: 21 + index
            readonly property bool tonight: root.ramadan && root.ramadan.phase === "night" && root.ramadan.day === night
            spacing: Style.space(2)
            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(12); height: width; radius: width / 2
              color: tonight ? root.accent : "transparent"
              border.width: night % 2 === 1 ? 1.5 : 1
              border.color: night % 2 === 1 ? root.accent : root.faint
              opacity: root.ramadan && night < root.ramadan.day ? 0.45 : 1
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: night
              color: night % 2 === 1 ? root.fg : root.dim
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      // The iftar dua, for the half hour after Maghrib.
      Column {
        visible: root.iftarHour
        width: parent.width
        spacing: Style.space(3)
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "ذَهَبَ الظَّمَأُ وَابْتَلَّتِ الْعُرُوقُ وَثَبَتَ الْأَجْرُ إِنْ شَاءَ اللَّهُ"
          color: root.fg
          font.family: "Noto Naskh Arabic"
          font.pixelSize: Style.font.heading
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: "Thirst has gone, the veins are moist, and the reward is certain, if Allah wills. (Abu Dawud 2357)"
          color: root.dim
          font.family: root.family
          font.pixelSize: Style.font.caption
        }
      }
    }

    // The du'a after the adhan, for a prayer's first ten minutes.
    Column {
      visible: root.afterAdhan && !root.overlayOpen
      width: parent.width
      spacing: Style.space(3)
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: Model.DUA_AFTER_ADHAN.arabic
        color: root.fg
        font.family: "Noto Naskh Arabic"
        font.pixelSize: Style.font.heading
      }
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: Model.DUA_AFTER_ADHAN.english + " (" + Model.DUA_AFTER_ADHAN.source + ")"
        color: root.dim
        font.family: root.family
        font.pixelSize: Style.font.caption
      }
    }

    // ---- Calculation method and Asr school.
    Column {
      visible: root.choosingMethod
      width: parent.width
      spacing: Style.space(8)

      Text {
        text: "Calculation method"
        color: root.fg
        font.family: root.family
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      ListView {
        id: methodList
        width: parent.width
        height: Style.space(44) * 8
        clip: true
        model: root.methodRows
        currentIndex: root.methodIndex
        highlightMoveDuration: 0
        boundsBehavior: Flickable.StopAtBounds
        // Keeps the current choice in the middle of the list.
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: height / 2 - Style.space(22)
        preferredHighlightEnd: height / 2 + Style.space(22)
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { root.choosingMethod = false; event.accepted = true }
          else if (event.key === Qt.Key_Down || event.text === "j") { root.methodIndex = Math.min(root.methodIndex + 1, root.methodRows.length - 1); event.accepted = true }
          else if (event.key === Qt.Key_Up || event.text === "k") { root.methodIndex = Math.max(root.methodIndex - 1, 0); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.pickMethod(root.methodRows[root.methodIndex]); event.accepted = true }
          else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            var order = ["auto", "standard", "hanafi"]
            var i = (order.indexOf(root.asrChoice) + (event.key === Qt.Key_Right ? 1 : 2)) % 3
            root.pickAsr(order[i]); event.accepted = true
          }
        }
        delegate: Rectangle {
          required property string modelData
          required property int index
          readonly property bool chosen: modelData === "auto" ? !!(root.opts.auto && root.opts.auto.method)
            : !(root.opts.auto && root.opts.auto.method) && root.opts.method === modelData
          width: ListView.view.width
          height: Style.space(44)
          radius: Style.cornerRadius
          color: index === root.methodIndex ? Style.hoverFillFor(root.fg, root.accent) : "transparent"
          Column {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              width: parent.width
              elide: Text.ElideRight
              text: (chosen ? "✓ " : "") + (modelData === "auto"
                ? "Auto: what " + (root.country ? Model.countryName(root.country) : "this country") + " uses, " + Model.METHODS[Model.COUNTRY_METHOD[root.country] || "MWL"].name
                : Model.METHODS[modelData].name)
              color: chosen || index === root.methodIndex ? root.accent : root.fg
              font.family: root.family
              font.pixelSize: Style.font.body
            }
            Text {
              width: parent.width
              elide: Text.ElideRight
              text: Model.methodSummary(modelData === "auto" ? (Model.COUNTRY_METHOD[root.country] || "MWL") : modelData)
              color: root.dim
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: root.methodIndex = index
            onClicked: root.pickMethod(modelData)
          }
        }
      }

      // Asr school: chips, also ←/→.
      Row {
        spacing: Style.space(8)
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Asr"
          color: root.dim
          font.family: root.family
          font.pixelSize: Style.font.body
        }
        Repeater {
          model: [["auto", "Auto"], ["standard", "Standard (Shafi'i, Maliki, Hanbali)"], ["hanafi", "Hanafi"]]
          Rectangle {
            required property var modelData
            readonly property bool on: root.asrChoice === modelData[0]
            width: chipText.implicitWidth + Style.space(16)
            height: chipText.implicitHeight + Style.space(8)
            radius: height / 2
            color: on ? Util.alpha(root.accent, 0.18) : "transparent"
            border.width: 1
            border.color: on ? root.accent : root.faint
            Text {
              id: chipText
              anchors.centerIn: parent
              text: modelData[1]
              color: parent.on ? root.accent : root.fg
              font.family: root.family
              font.pixelSize: Style.font.bodySmall
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.pickAsr(modelData[0]) }
          }
        }
      }
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "↑/↓ choose  ·  enter: use it  ·  ←/→ Asr  ·  esc: back"
        color: root.dim
        font.family: root.family
        font.pixelSize: Style.font.caption
      }
    }

    // ---- Adjustments.
    Column {
      visible: root.adjustOpen
      width: parent.width
      spacing: Style.space(4)
      Text { text: "Adjustments"; color: root.fg; font.family: root.family; font.pixelSize: Style.font.heading; font.bold: true; bottomPadding: Style.space(6) }
      SettingsList {
        id: adjustList
        width: parent.width
        rows: root.adjustRows
        valueOf: root.adjustValue
        family: root.family
        onPicked: function(field, value) { root.setAdjust(field, value) }
        onActionRun: function(field, id) {
          if (id === "mosquefolder") root.mosqueFolderRequested()
          else if (id === "sethome") { root.home = root.location; root.settingPicked("home", root.location) }
          else if (id === "clearhome") { root.home = null; root.settingPicked("home", null) }
        }
        onClosed: root.adjustOpen = false
      }
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        topPadding: Style.space(4)
        text: "Offsets apply after the method's own, to match the timetable you follow. Height lowers the horizon, so the sun rises earlier and sets later; Fajr and Isha, being angles below the horizon, do not move. Home is used for travel: away from it, Falak reminds you that qasr applies. A mosque timetable is a CSV in ~/.local/share/falak/mosque with a header such as Date,Fajr,Dhuhr,Asr,Maghrib,Isha,Jumuah and one row per day of iqama times; the newest file is used."
        color: root.dim; font.family: root.family; font.pixelSize: Style.font.caption
      }
      Text { text: "↑/↓ choose  ·  ←/→ change  ·  enter: the row's button  ·  esc: back"; color: root.dim; font.family: root.family; font.pixelSize: Style.font.caption }
    }

    // ---- Why the times move.
    Item {
      id: teachKeys
      visible: root.teachOpen
      width: parent.width
      height: teachColumn.implicitHeight
      Keys.onPressed: function(event) {
        var k = event.key
        if (k === Qt.Key_Escape) root.teachOpen = false
        else if (k === Qt.Key_Right || event.text === "l") root.teachStep = Math.min(root.teachSteps.length - 1, root.teachStep + 1)
        else if (k === Qt.Key_Left || event.text === "h") root.teachStep = Math.max(0, root.teachStep - 1)
        else if (k === Qt.Key_Space) { if (root.gnomonFraction >= 1) root.gnomonFraction = 0; root.gnomonPlaying = !root.gnomonPlaying }
        else return
        event.accepted = true
      }
      Column {
        id: teachColumn
        width: parent.width
        spacing: Style.space(10)
        Text {
          text: (root.teachStep + 1) + " of " + root.teachSteps.length + "  ·  " + root.teachSteps[root.teachStep][0]
          color: root.fg; font.family: root.family; font.pixelSize: Style.font.heading; font.bold: true
        }
        Text {
          width: parent.width; wrapMode: Text.WordWrap
          text: root.teachSteps[root.teachStep][1]
          color: root.fg; font.family: root.family; font.pixelSize: Style.font.body
        }
        // The stick and its shadow, on this place's afternoon.
        Canvas {
          id: gnomon
          visible: root.teachStep === 3 && !!root.viewTimes
          width: parent.width; height: Style.space(150)
          property real f: root.gnomonFraction
          onFChanged: requestPaint()
          onVisibleChanged: requestPaint()
          onPaint: {
            var ctx = getContext("2d"); ctx.reset()
            var t = root.viewTimes
            if (!t || t.maghrib === null) return
            var when = t.transit + (t.maghrib - t.transit) * f
            var alt = Model.sunPosition(when, root.lat, root.lon).altitude
            var H = 60, base = height - 24, x0 = 70
            var cot = function(a) { return 1 / Math.tan(Math.max(a, 1) * Math.PI / 180) }
            var noon = H * cot(t.noonAltitude), len = Math.min(width - x0 - 20, H * cot(alt))
            // Ground, stick, shadow.
            ctx.strokeStyle = root.css(root.faint); ctx.lineWidth = 1
            ctx.beginPath(); ctx.moveTo(20, base); ctx.lineTo(width - 10, base); ctx.stroke()
            ctx.fillStyle = root.css(Util.alpha(root.fg, 0.35))
            ctx.fillRect(x0, base - 3, len, 6)
            ctx.strokeStyle = root.css(root.fg); ctx.lineWidth = 4
            ctx.beginPath(); ctx.moveTo(x0, base); ctx.lineTo(x0, base - H); ctx.stroke()
            // Marks: noon's shadow, Asr standard (+1×), Asr Hanafi (+2×).
            var marks = [[noon, "noon"], [noon + H, "Asr"], [noon + 2 * H, "Asr (Hanafi)"]]
            ctx.font = Style.font.caption + "px \"" + root.family + "\""; ctx.textAlign = "center"
            for (var i = 0; i < marks.length; i++) {
              var mx = x0 + marks[i][0]
              if (mx > width - 10) continue
              var reached = len >= marks[i][0] - 0.5
              ctx.fillStyle = root.css(reached ? root.accent : root.dim)
              ctx.fillRect(mx - 1, base - 10, 2, 20)
              ctx.fillText(marks[i][1], mx, base + 20)
            }
            // The sun's direction, and the clock.
            ctx.strokeStyle = root.css(Util.alpha(root.accent, 0.5)); ctx.lineWidth = 1
            ctx.beginPath(); ctx.moveTo(x0, base - H); ctx.lineTo(x0 - 50 * Math.cos(alt * Math.PI / 180), base - H - 50 * Math.sin(alt * Math.PI / 180)); ctx.stroke()
            ctx.fillStyle = root.css(root.accent)
            ctx.beginPath(); ctx.arc(x0 - 50 * Math.cos(alt * Math.PI / 180), base - H - 50 * Math.sin(alt * Math.PI / 180), 6, 0, 2 * Math.PI); ctx.fill()
            ctx.textAlign = "left"; ctx.fillStyle = root.css(root.fg)
            ctx.fillText(Model.hhmm(when, root.zone) + "  ·  sun " + alt.toFixed(1) + "° up  ·  shadow " + (len / H).toFixed(2) + " × the stick", 20, 14)
          }
        }
        Text {
          text: "←/→ step" + (root.teachStep === 3 ? "  ·  space: play the afternoon" : "") + "  ·  esc: back"
          color: root.dim; font.family: root.family; font.pixelSize: Style.font.caption
        }
      }
    }

    // ---- The journal.
    Item {
      id: journalKeys
      visible: root.journalOpen
      width: parent.width
      height: journalColumn.implicitHeight
      Keys.onPressed: function(event) {
        var k = event.key, t = event.text
        if (k === Qt.Key_Escape) root.journalOpen = false
        else if (!root.journalOn && (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space)) root.settingPicked("journal", "on")
        else if (k === Qt.Key_Up || t === "k") root.journalRow = Math.max(0, root.journalRow - 1)
        else if (k === Qt.Key_Down || t === "j") root.journalRow = Math.min(4, root.journalRow + 1)
        else if (k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter) root.journalToggle(Model.JOURNAL_PRAYERS[root.journalRow])
        else if (t === "[" || k === Qt.Key_Left) root.journalBack = Math.min(6, root.journalBack + 1)
        else if (t === "]" || k === Qt.Key_Right) root.journalBack = Math.max(0, root.journalBack - 1)
        else return
        event.accepted = true
      }
      Column {
        id: journalColumn
        width: parent.width
        spacing: Style.space(8)
        Text { text: "Prayer journal"; color: root.fg; font.family: root.family; font.pixelSize: Style.font.heading; font.bold: true }
        Text {
          visible: !root.journalOn
          width: parent.width; wrapMode: Text.WordWrap
          text: "A private record of the prayers you have prayed, kept only on this machine (~/.local/share/falak/journal.json). No streaks and no scores, just a quiet tick. It stays off until you turn it on: press Enter."
          color: root.fg; font.family: root.family; font.pixelSize: Style.font.body
        }
        Text {
          visible: root.journalOn
          text: Model.dateText(root.journalNoon, root.zone) + (root.journalBack === 0 ? "  ·  today" : "")
          color: root.journalBack === 0 ? root.dim : root.accent; font.family: root.family; font.pixelSize: Style.font.body
        }
        Repeater {
          model: root.journalOn ? Model.JOURNAL_PRAYERS : []
          Rectangle {
            required property string modelData
            required property int index
            readonly property bool done: (root.journal[root.journalDay] || []).indexOf(modelData) >= 0
            width: parent.width; height: Style.space(30); radius: Style.cornerRadius
            color: index === root.journalRow ? Style.hoverFillFor(root.fg, root.accent) : "transparent"
            Text {
              anchors.left: parent.left; anchors.leftMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter
              text: (parent.done ? "✓  " : "○  ") + Model.prayerLabel(modelData, root.journalNoon, root.zone, root.lang)
              color: parent.done ? root.accent : root.fg; font.family: root.family; font.pixelSize: Style.font.body
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.journalRow = index; root.journalToggle(modelData); journalKeys.forceActiveFocus() } }
          }
        }
        // This month, one column of five dots per day.
        Row {
          visible: root.journalOn
          spacing: 3
          Repeater {
            model: {
              if (!root.journalOn) return []
              var c = Model.civil(root.now, root.zone), days = []
              for (var d = 1; d <= c.getUTCDate(); d++)
                days.push(c.getUTCFullYear() + "-" + ("0" + (c.getUTCMonth() + 1)).slice(-2) + "-" + ("0" + d).slice(-2))
              return days
            }
            Column {
              id: dayDots
              required property string modelData
              spacing: 2
              Repeater {
                model: Model.JOURNAL_PRAYERS
                Rectangle {
                  required property string modelData
                  width: 7; height: 7; radius: 3.5
                  color: (root.journal[dayDots.modelData] || []).indexOf(modelData) >= 0 ? root.accent : root.faint
                }
              }
            }
          }
        }
        Row {
          visible: root.journalOn
          spacing: Style.space(10)
          Rectangle {
            width: eraseText.implicitWidth + Style.space(14); height: eraseText.implicitHeight + Style.space(6); radius: height / 2
            color: "transparent"; border.width: 1; border.color: root.eraseArmed ? Color.urgent : root.faint
            Text { id: eraseText; anchors.centerIn: parent; text: root.eraseArmed ? "Press again to erase the whole journal" : "Erase the journal"; color: root.eraseArmed ? Color.urgent : root.dim; font.family: root.family; font.pixelSize: Style.font.caption }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (root.eraseArmed) { root.journal = ({}); root.journalErased(); root.eraseArmed = false } else root.eraseArmed = true } }
          }
          Rectangle {
            width: offText.implicitWidth + Style.space(14); height: offText.implicitHeight + Style.space(6); radius: height / 2
            color: "transparent"; border.width: 1; border.color: root.faint
            Text { id: offText; anchors.centerIn: parent; text: "Turn the journal off"; color: root.dim; font.family: root.family; font.pixelSize: Style.font.caption }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.settingPicked("journal", "off") }
          }
        }
        Text {
          text: root.journalOn ? "↑/↓ choose  ·  space: tick  ·  ←/→ an earlier day (up to a week)  ·  esc: back" : "enter: turn it on  ·  esc: back"
          color: root.dim; font.family: root.family; font.pixelSize: Style.font.caption
        }
      }
    }

    // ---- Tasbih.
    Item {
      id: tasbihKeys
      visible: root.tasbihOpen
      width: parent.width
      height: tasbihColumn.implicitHeight
      Keys.onPressed: function(event) {
        var k = event.key
        if (k === Qt.Key_Escape) root.tasbihOpen = false
        else if (k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter) root.tasbihTap()
        else if (event.text === "r") root.tasbihCount = 0
        else return
        event.accepted = true
      }
      MouseArea { anchors.fill: parent; onClicked: { root.tasbihTap(); tasbihKeys.forceActiveFocus() } }
      Column {
        id: tasbihColumn
        width: parent.width
        spacing: Style.space(10)
        Text { text: "Tasbih"; color: root.fg; font.family: root.family; font.pixelSize: Style.font.heading; font.bold: true }
        Item {
          width: parent.width
          height: Style.space(170)
          // Three rings fill as each phrase completes.
          Canvas {
            id: tasbihRing
            anchors.centerIn: parent
            width: Style.space(170); height: width
            property int count: root.tasbihCount
            onCountChanged: requestPaint()
            onPaint: {
              var ctx = getContext("2d"); ctx.reset()
              var c = width / 2
              for (var i = 0; i < 3; i++) {
                var r = c - 6 - i * 14, total = root.tasbihSteps[i][2]
                var done = i < root.tasbihStep ? total : i === root.tasbihStep ? root.tasbihInStep : 0
                ctx.lineWidth = 8; ctx.strokeStyle = root.css(root.faint)
                ctx.beginPath(); ctx.arc(c, c, r, 0, 2 * Math.PI); ctx.stroke()
                if (done > 0) {
                  ctx.strokeStyle = root.css(Util.alpha(root.accent, 1 - i * 0.22))
                  ctx.beginPath(); ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * done / total); ctx.stroke()
                }
              }
            }
          }
          Column {
            anchors.centerIn: parent
            spacing: 2
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.num(root.tasbihStep < 3 ? root.tasbihInStep : 100)
              color: root.fg; font.family: root.family; font.pixelSize: 40; font.bold: true
              scale: 1
              SequentialAnimation on scale {
                id: tasbihPulse
                running: false
                NumberAnimation { to: 1.25; duration: 140; easing.type: Easing.OutQuad }
                NumberAnimation { to: 1; duration: 260; easing.type: Easing.InOutQuad }
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.tasbihStep < 3 ? "of " + root.tasbihSteps[root.tasbihStep][2] : "complete"
              color: root.dim; font.family: root.family; font.pixelSize: Style.font.caption
            }
          }
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.tasbihStep < 3 ? root.tasbihSteps[root.tasbihStep][0] : "لا إله إلا الله وحده لا شريك له، له الملك وله الحمد وهو على كل شيء قدير"
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          color: root.fg; font.family: "Noto Naskh Arabic"; font.pixelSize: root.tasbihStep < 3 ? 30 : 20
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.tasbihStep < 3 ? root.tasbihSteps[root.tasbihStep][1]
            : "There is no god but Allah alone, without partner; His is the dominion and His the praise, and He has power over all things."
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          color: root.dim; font.family: root.family; font.pixelSize: Style.font.body
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "space, enter or click: count  ·  r: start again  ·  esc: back"
          color: root.dim; font.family: root.family; font.pixelSize: Style.font.caption
        }
      }
    }

    // ---- Every key.
    Column {
      visible: root.helpOpen
      width: parent.width
      spacing: Style.space(6)
      Item {
        id: helpKeys
        width: parent.width
        height: helpTitle.implicitHeight + Style.space(4)
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape || event.text === "?") { root.helpOpen = false; event.accepted = true }
        }
        Text { id: helpTitle; text: "Keys"; color: root.fg; font.family: root.family; font.pixelSize: Style.font.heading; font.bold: true }
      }
      Repeater {
        model: root.keyHelp
        Row {
          required property var modelData
          spacing: Style.space(12)
          Text { width: Style.space(70); text: modelData[0]; color: root.accent; font.family: root.family; font.pixelSize: Style.font.body; horizontalAlignment: Text.AlignRight }
          Text { text: modelData[1]; color: root.fg; font.family: root.family; font.pixelSize: Style.font.body }
        }
      }
      Text { text: "esc: back"; color: root.dim; font.family: root.family; font.pixelSize: Style.font.caption }
    }

    // ---- Eclipses.
    Column {
      visible: root.eclipsesOpen
      width: parent.width
      spacing: Style.space(10)

      Item {
        id: eclipseKeys
        width: parent.width
        height: eclipseTitleText.implicitHeight
        Keys.onPressed: function(event) {
          var k = event.key, t = event.text
          if (k === Qt.Key_Escape) root.eclipsesOpen = false
          else if (k === Qt.Key_Down || t === "j") root.eclipseIndex = Math.min(root.eclipses.length - 1, root.eclipseIndex + 1)
          else if (k === Qt.Key_Up || t === "k") root.eclipseIndex = Math.max(0, root.eclipseIndex - 1)
          else return
          event.accepted = true
        }
        Text {
          id: eclipseTitleText
          text: "Eclipses" + (root.location ? ", seen from " + root.location.name : "")
          color: root.fg
          font.family: root.family
          font.pixelSize: Style.font.heading
          font.bold: true
        }
      }

      Repeater {
        model: root.eclipses
        Row {
          required property var modelData
          required property int index
          width: parent.width
          spacing: Style.space(12)
          opacity: modelData.visible || index === root.eclipseIndex ? 1 : 0.55
          // The chosen row: a bar at its left edge.
          Rectangle {
            width: Style.space(3); height: Style.space(40); radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: index === root.eclipseIndex ? root.accent : "transparent"
          }
          // The eclipse at its deepest: the moon over the sun, or the moon in shadow.
          Canvas {
            width: Style.space(44); height: width
            anchors.verticalCenter: parent.verticalCenter
            property var e: parent.modelData
            onEChanged: requestPaint()
            onPaint: {
              var ctx = getContext("2d"); ctx.reset()
              var r = width / 2 - 2, cx = width / 2, cy = height / 2
              if (e.kind === "solar") {
                var m = e.type === "elsewhere" ? 0.3 : Math.max(0, Math.min(1.05, e.magnitude))
                ctx.fillStyle = root.css(root.accent)
                ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.fill()
                // Moon radius ~ sun's; offset so it covers m of the diameter.
                var rm = r * (e.type === "annular" ? 0.93 : 1.03), off = r + rm - m * 2 * r
                ctx.fillStyle = root.css(Color.popups.background)
                ctx.beginPath(); ctx.arc(cx + off * 0.7, cy - off * 0.7, rm, 0, 2 * Math.PI); ctx.fill()
                ctx.strokeStyle = root.css(root.faint); ctx.lineWidth = 1
                ctx.beginPath(); ctx.arc(cx + off * 0.7, cy - off * 0.7, rm, 0, 2 * Math.PI); ctx.stroke()
              } else {
                ctx.fillStyle = root.css(root.fg)
                ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.fill()
                // The umbra, a big dark disc whose edge reaches in by the magnitude.
                var depth = e.type === "penumbral" ? 0.15 : Math.min(1.2, e.magnitude)
                ctx.save(); ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.clip()
                ctx.fillStyle = root.css(Util.alpha(Color.urgent, e.type === "total" ? 0.85 : 0.75))
                if (e.type === "penumbral") ctx.fillStyle = root.css(Util.alpha(Color.popups.background, 0.35))
                var R = r * 2.6, shift = R + r - depth * 2 * r
                ctx.beginPath(); ctx.arc(cx - shift * 0.7, cy + shift * 0.7, R, 0, 2 * Math.PI); ctx.fill()
                ctx.restore()
              }
            }
          }
          Column {
            width: parent.width - Style.space(71)
            spacing: Style.space(2)
            anchors.verticalCenter: parent.verticalCenter
            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.eclipseTitle(modelData) + "  ·  " + Model.dateText(modelData.max, root.zone)
              color: modelData.visible ? root.accent : root.fg
              font.family: root.family
              font.pixelSize: Style.font.body
              font.bold: modelData.visible
            }
            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.eclipseText(modelData)
              color: root.dim
              font.family: root.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }

      // Where on Earth the chosen eclipse is seen: 80°N to 60°S.
      Canvas {
        id: eclipseCanvas
        width: parent.width
        height: width * 140 / 360
        Accessible.role: Accessible.Graphic
        Accessible.name: "Where on Earth the chosen eclipse is seen"
        readonly property real mapTop: 80
        property var m: root.eclipseMap
        onMChanged: requestPaint()
        onWidthChanged: requestPaint()
        function px(lon) { return (lon + 180) / 360 * width }
        function py(lat) { return (mapTop - lat) / 140 * height }
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          if (m) {
            var shade = m.kind === "lunar" ? { "1": 0.22, "2": 0.5 } : { "1": 0.14, "2": 0.3, "3": 0.5 }
            for (var r = 0; r < m.rows.length; r++) {
              var lat0 = 90 - r * m.step
              if (lat0 - m.step > mapTop || lat0 < mapTop - 140) continue
              for (var c = 0; c < m.rows[r].length; c++) {
                var a = shade[m.rows[r][c]]
                if (!a) continue
                ctx.fillStyle = root.css(Util.alpha(root.accent, a))
                var x0 = px(-180 + c * m.step), y0 = py(lat0)
                ctx.fillRect(x0, y0, px(-180 + (c + 1) * m.step) - x0 + 0.5, py(lat0 - m.step) - y0 + 0.5)
              }
            }
          }
          if (root.land) {
            ctx.fillStyle = root.css(Util.alpha(root.fg, 0.5))
            var st = root.land.step
            for (var lr = 0; lr < root.land.rows.length; lr++) {
              var la = 90 - st / 2 - lr * st
              if (la > mapTop || la < mapTop - 140) continue
              var row = root.land.rows[lr]
              for (var lc = 0; lc < row.length; lc++)
                if (row[lc] === "1") ctx.fillRect(px(-180 + st / 2 + lc * st) - 0.75, py(la) - 0.75, 1.5, 1.5)
            }
          }
          // The path of totality (or the ring), as wide as it is; split where it wraps the date line.
          if (m && m.path.length) {
            ctx.strokeStyle = root.css(Color.urgent); ctx.lineCap = "round"
            for (var i = 1; i < m.path.length; i++) {
              var a0 = m.path[i - 1], a1 = m.path[i]
              if (Math.abs(a1[1] - a0[1]) > 180) continue
              ctx.lineWidth = Math.max(2, a1[2] / 140 * height)
              ctx.beginPath(); ctx.moveTo(px(a0[1]), py(a0[0])); ctx.lineTo(px(a1[1]), py(a1[0])); ctx.stroke()
            }
          }
          if (root.location) {
            var x = px(root.lon), y = py(root.lat)
            ctx.strokeStyle = root.css(root.fg); ctx.lineWidth = 1.5
            ctx.beginPath(); ctx.arc(x, y, 5, 0, 2 * Math.PI); ctx.stroke()
            ctx.fillStyle = root.css(root.fg)
            ctx.beginPath(); ctx.arc(x, y, 1.8, 0, 2 * Math.PI); ctx.fill()
          }
        }
      }
      Row {
        spacing: Style.space(14)
        visible: !!root.eclipseMap
        Repeater {
          model: !root.eclipseMap ? []
            : root.eclipseMap.kind === "lunar" ? [[0.5, "moon up at its deepest"], [0.22, "up for part of it"]]
            : [[0.5, "most of the sun covered"], [0.3, "about half"], [0.14, "a bite"]].concat(root.eclipseMap.path.length ? [[-1, root.eclipses[root.eclipseIndex].global === "total" ? "totality" : "ring of fire"]] : [])
          Row {
            required property var modelData
            spacing: Style.space(5)
            Rectangle { width: Style.space(12); height: width; anchors.verticalCenter: parent.verticalCenter; color: modelData[0] < 0 ? Color.urgent : Util.alpha(root.accent, modelData[0]) }
            Text { text: modelData[1]; color: root.dim; font.family: root.family; font.pixelSize: Style.font.caption }
          }
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "During an eclipse it is sunnah to pray salat al-kusuf (the sun) or salat al-khusuf (the moon). Times are for this place, on its clock; the moon and sun come from a precise lunar theory, checked against NASA's eclipse tables."
        color: root.dim
        font.family: root.family
        font.pixelSize: Style.font.caption
      }
      Text {
        text: "↑/↓ choose  ·  esc: back"
        color: root.dim
        font.family: root.family
        font.pixelSize: Style.font.caption
      }
    }

    // ---- Adhan and reminders.
    Column {
      visible: root.alertsOpen
      width: parent.width
      spacing: Style.space(4)

      Text {
        text: "Adhan and reminders"
        color: root.fg
        font.family: root.family
        font.pixelSize: Style.font.heading
        font.bold: true
        bottomPadding: Style.space(6)
      }
      SettingsList {
        id: alertsList
        width: parent.width
        rows: root.alertRows
        valueOf: root.alertValue
        dimmed: function(i) { return i > 0 && !root.alerts.enabled }
        family: root.family
        extraKey: function(event, row) {
          if (event.key === Qt.Key_Space && row && (row.field === "sound" || row.field === "fajrSound")) { root.previewRequested(root.alertValue(row.field)); return true }
          if (event.text === "s") { root.stopRequested(); return true }
          return false
        }
        onPicked: function(field, value) { root.setAlert(field, value) }
        onActionRun: function(field, id) {
          if (id === "test") root.testRequested()
          else if (id === "stop") root.stopRequested()
          else if (id === "folder") root.adhanFolderRequested()
        }
        onClosed: root.alertsOpen = false
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        topPadding: Style.space(4)
        text: (root.alerts.enabled
          ? (root.nextAlert ? "Next: " + root.nextAlert.headline + " at " + Model.hhmm(root.nextAlert.time, root.zone) + (root.nextAlert.sound ? ", with the adhan." : ".") : "Nothing more today.")
          : "Off: Falak announces nothing.")
          + " Alerts follow the place shown" + (root.location ? " (" + root.location.name + ")" : "")
          + ". The adhan stays silent during Do Not Disturb or a screen recording; click its notification to stop it."
          + " Recordings you put in ~/.local/share/falak/adhans (ogg, opus, mp3, wav, flac) appear in the adhan choices."
          + " Prayer focus turns on Do Not Disturb and pauses whatever is playing for that long from each prayer's start, then puts both back."
        color: root.dim
        font.family: root.family
        font.pixelSize: Style.font.caption
      }
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "↑/↓ choose  ·  ←/→ change  ·  space: listen  ·  enter: test  ·  s: stop sound  ·  esc: back"
        color: root.dim
        font.family: root.family
        font.pixelSize: Style.font.caption
      }
    }

    // ---- The new crescent.
    Column {
      visible: root.crescentOpen
      width: parent.width
      spacing: Style.space(8)

      Item {
        id: crescentKeys
        width: parent.width
        height: crescentTitle.implicitHeight
        Keys.onPressed: function(event) {
          var k = event.key
          if (k === Qt.Key_Escape) root.crescentOpen = false
          else if (k === Qt.Key_Left || event.text === "h") root.crescentEvening = Math.max(0, root.crescentEvening - 1)
          else if (k === Qt.Key_Right || event.text === "l") root.crescentEvening = Math.min(2, root.crescentEvening + 1)
          else return
          event.accepted = true
        }
        Text {
          id: crescentTitle
          anchors.left: parent.left
          text: "The new crescent of " + root.crescentMonth.monthName + " " + root.crescentMonth.year
          color: root.fg
          font.family: root.family
          font.pixelSize: Style.font.heading
          font.bold: true
        }
      }
      Text {
        text: "New moon " + Model.dayTimeText(root.crescentConj, root.zone) + "  ·  evening of "
          + Model.dateText((root.crescentDay) * 86400000 + 12 * 3600000, null).replace(/ \d{4}$/, "")
        color: root.dim
        font.family: root.family
        font.pixelSize: Style.font.bodySmall
      }

      Canvas {
        id: crescentCanvas
        width: parent.width
        height: width * 128 / 360          // 72°N to 56°S
        Accessible.role: Accessible.Graphic
        Accessible.name: "Where the new crescent can be seen on this evening"
        readonly property real mapTop: 72
        function px(lon) { return (lon + 180) / 360 * width }
        function py(lat) { return (mapTop - lat) / 128 * height }
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var m = root.crescentMap
          if (m) {
            var shade = { A: 0.62, B: 0.38, C: 0.16 }
            for (var r = 0; r < m.rows.length; r++) {
              var lat0 = 60 - r * m.step
              for (var c = 0; c < m.rows[r].length; c++) {
                var a = shade[m.rows[r][c]]
                if (!a) continue
                ctx.fillStyle = root.css(Util.alpha(root.accent, a))
                var x0 = px(-180 + c * m.step), y0 = py(lat0)
                ctx.fillRect(x0, y0, px(-180 + (c + 1) * m.step) - x0 + 0.5, py(lat0 - m.step) - y0 + 0.5)
              }
            }
          }
          if (root.land) {
            ctx.fillStyle = root.css(Util.alpha(root.fg, 0.5))
            var st = root.land.step
            for (var lr = 0; lr < root.land.rows.length; lr++) {
              var la = 90 - st / 2 - lr * st
              if (la > mapTop || la < mapTop - 128) continue
              var row = root.land.rows[lr]
              for (var lc = 0; lc < row.length; lc++)
                if (row[lc] === "1") ctx.fillRect(px(-180 + st / 2 + lc * st) - 0.75, py(la) - 0.75, 1.5, 1.5)
            }
          }
          if (root.location) {
            var x = px(root.lon), y = py(root.lat)
            ctx.strokeStyle = root.css(root.fg); ctx.lineWidth = 1.5
            ctx.beginPath(); ctx.arc(x, y, 5, 0, 2 * Math.PI); ctx.stroke()
            ctx.fillStyle = root.css(root.fg)
            ctx.beginPath(); ctx.arc(x, y, 1.8, 0, 2 * Math.PI); ctx.fill()
          }
        }
      }

      // Legend.
      Row {
        spacing: Style.space(14)
        Repeater {
          model: [[0.62, "naked eye"], [0.38, "optical aid, maybe naked eye"], [0.16, "optical aid only"]]
          Row {
            required property var modelData
            spacing: Style.space(5)
            Rectangle { width: Style.space(12); height: width; anchors.verticalCenter: parent.verticalCenter; color: Util.alpha(root.accent, modelData[0]) }
            Text { text: modelData[1]; color: root.dim; font.family: root.family; font.pixelSize: Style.font.caption }
          }
        }
      }

      // Here.
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        color: root.fg
        font.family: root.family
        font.pixelSize: Style.font.body
        text: {
          var h = root.crescentHere, name = root.location ? root.location.name : "here"
          if (!h) return ""
          var words = { A: "visible to the naked eye", B: "visible with binoculars, maybe the naked eye", C: "visible only with a telescope or binoculars" }
          if (h.zone === "D") {
            var why = { "before the new moon": "the moon is not yet new at sunset", "moon sets first": "the moon sets before the sun", "no sunset": "the sun does not set" }[h.reason]
            return "From " + name + ": not visible" + (why ? ", " + why : "") + "."
          }
          var m = Model.moonPosition(h.best, root.lat, root.lon)
          return "From " + name + ": " + words[h.zone] + ". Sunset " + Model.hhmm(h.sunset, root.zone) + "; look "
            + Math.round(m.altitude) + "° up, " + Model.compassPoint(m.azimuth) + ", around " + Model.hhmm(h.best, root.zone)
            + ". The moon sets at " + Model.hhmm(h.moonset, root.zone) + ", " + Math.round(h.age) + " hours after the new moon."
        }
      }
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Odeh's criterion, as the Islamic Crescents' Observation Project uses it. Where a month waits for a local sighting, the shaded line is why it can begin a day apart from place to place."
        color: root.dim
        font.family: root.family
        font.pixelSize: Style.font.caption
      }
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        // The three evenings, as dates: the one shown in brackets.
        text: "←/→ evening: " + [0, 1, 2].map(function(i) {
            var d = new Date((Math.floor(root.crescentConj / 86400000) + i) * 86400000).getUTCDate()
            return i === root.crescentEvening ? "[" + d + "]" : String(d) }).join(" · ") + "  ·  esc: back"
        color: root.dim
        font.family: root.family
        font.pixelSize: Style.font.caption
      }
    }

    // ---- The hijri calendar.
    Column {
      visible: root.calendarOpen && !!root.calMonth
      width: parent.width
      spacing: Style.space(8)

      Item {
        id: calendarKeys
        width: parent.width
        height: calTitle.implicitHeight
        focus: root.calendarOpen
        Keys.onPressed: function(event) {
          var k = event.key, t = event.text
          if (k === Qt.Key_Escape) root.calendarOpen = false
          else if (k === Qt.Key_Left || t === "h") root.calDay -= 1
          else if (k === Qt.Key_Right || t === "l") root.calDay += 1
          else if (k === Qt.Key_Up || t === "k") root.calDay -= 7
          else if (k === Qt.Key_Down || t === "j") root.calDay += 7
          else if (k === Qt.Key_PageUp || t === "[") root.calMonthStep(-1)
          else if (k === Qt.Key_PageDown || t === "]") root.calMonthStep(1)
          else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.openCalendarDay()
          else if (t === "t") root.calDay = root.todayNumber
          else if (t === "i") root.icsRequested(Model.icsSacredDays(root.todayNumber, root.hijriOffset), "falak-sacred-days-" + root.calMonth.year + ".ics")
          else return
          event.accepted = true
        }
        Text {
          id: calTitle
          anchors.left: parent.left
          text: root.calMonth ? root.num(Model.hijriMonth(root.lang, root.calMonth.month) + " " + root.calMonth.year) : ""
          color: root.fg
          font.family: root.family
          font.pixelSize: Style.font.heading
          font.bold: true
        }
        Text {
          anchors.right: parent.right
          anchors.baseline: calTitle.baseline
          text: {
            var m = root.calMonth
            if (!m) return ""
            var a = m.days[0], b = m.days[m.length - 1]
            return root.monthsShort[a.month] + " " + a.date + " – " + root.monthsShort[b.month] + " " + b.date + " " + b.year
          }
          color: root.dim
          font.family: root.family
          font.pixelSize: Style.font.bodySmall
        }
      }

      Grid {
        id: calGrid
        columns: 7
        width: parent.width
        columnSpacing: Style.space(4)
        rowSpacing: Style.space(4)
        readonly property real cell: (width - 6 * columnSpacing) / 7

        Repeater {
          model: 7
          Text {
            required property int index
            width: calGrid.cell
            horizontalAlignment: Text.AlignHCenter
            text: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][(index + root.weekStart) % 7]
            color: (index + root.weekStart) % 7 === 5 ? root.accent : root.dim
            font.family: root.family
            font.pixelSize: Style.font.caption
            bottomPadding: Style.space(4)
          }
        }

        Repeater {
          model: root.calCells
          Rectangle {
            required property var modelData
            readonly property bool isToday: !!modelData && modelData.dayNumber === root.todayNumber
            readonly property bool isSelected: !!modelData && modelData.dayNumber === root.calDay
            readonly property bool hasEvent: !!modelData && modelData.notes.events.length > 0
            width: calGrid.cell
            height: Style.space(50)
            radius: Style.cornerRadius
            color: !modelData ? "transparent"
              : hasEvent ? Util.alpha(root.accent, 0.14)
              : modelData.notes.fast === "ramadan" ? Util.alpha(root.accent, 0.07) : Util.alpha(root.fg, 0.04)
            // Selected: the accent. Today: a quieter outline.
            border.width: isSelected ? 2 : (isToday ? 1 : 0)
            border.color: isSelected ? root.accent : Util.alpha(root.fg, 0.6)

            Text {
              visible: !!parent.modelData
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.margins: Style.space(5)
              text: parent.modelData ? root.num(parent.modelData.day) : ""
              color: parent.hasEvent || parent.isSelected ? root.accent : root.fg
              font.family: root.family
              font.pixelSize: Style.font.title
              font.bold: parent.hasEvent
            }
            // The civil date, with its month on the 1st and on the first cell.
            Text {
              visible: !!parent.modelData
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(5)
              text: !parent.modelData ? "" : (parent.modelData.date === 1 || parent.modelData.day === 1
                ? root.monthsShort[parent.modelData.month] + " " : "") + parent.modelData.date
              color: root.dim
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
            // Sunnah fast: a filled dot. No fasting: a hollow ring (shape, not
            // just colour, since some themes make urgent and accent alike).
            Rectangle {
              readonly property bool forbidden: !!parent.modelData && parent.modelData.notes.fast === "forbidden"
              visible: !!parent.modelData && (parent.modelData.notes.fast === "sunnah" || forbidden)
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(7)
              width: Style.space(7); height: width; radius: width / 2
              color: forbidden ? "transparent" : root.accent
              border.width: forbidden ? 1.5 : 0
              border.color: Color.urgent
            }
            Canvas {
              id: cellMoon
              visible: !!parent.modelData
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(6)
              width: Style.space(10); height: width
              property var phase: parent.modelData ? parent.modelData.moon : null
              onPhaseChanged: requestPaint()
              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                if (!phase) return
                var r = width / 2, cx = r, cy = r
                ctx.fillStyle = root.css(root.faint)
                ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.fill()
                var side = (phase.waxing ? 1 : -1) * (root.lat < 0 ? -1 : 1), e = 1 - 2 * phase.illumination
                ctx.fillStyle = root.css(root.dim)
                ctx.beginPath()
                for (var i = 0; i <= 16; i++) { var a = -Math.PI / 2 + Math.PI * i / 16; ctx.lineTo(cx + side * r * Math.cos(a), cy + r * Math.sin(a)) }
                for (var j = 0; j <= 16; j++) { var b = Math.PI / 2 - Math.PI * j / 16; ctx.lineTo(cx + side * e * r * Math.cos(b), cy + r * Math.sin(b)) }
                ctx.closePath(); ctx.fill()
              }
            }
            MouseArea {
              anchors.fill: parent
              enabled: !!parent.modelData
              cursorShape: Qt.PointingHandCursor
              onClicked: root.calDay = parent.modelData.dayNumber
              onDoubleClicked: root.openCalendarDay()
            }
          }
        }
      }

      // The chosen day, spelled out.
      Column {
        width: parent.width
        spacing: Style.space(3)
        Text {
          text: !root.calSelected ? "" : root.num(Model.WEEKDAYS[root.calSelected.weekday] + " " + root.calSelected.date + " "
            + Model.MONTHS[root.calSelected.month] + " " + root.calSelected.year + "  ·  " + root.calSelected.day + " "
            + Model.hijriMonth(root.lang, root.calMonth.month) + " " + root.calMonth.year)
          color: root.fg
          font.family: root.family
          font.pixelSize: Style.font.body
        }
        Text {
          visible: text !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.calSelected ? root.calSelected.notes.events.join("  ·  ") : ""
          color: root.accent
          font.family: root.family
          font.pixelSize: Style.font.body
        }
        Text {
          visible: text !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          text: {
            var n = root.calSelected ? root.calSelected.notes : null
            if (!n || !n.fast) return ""
            if (n.fast === "forbidden") return "No fasting today."
            if (n.fast === "ramadan") return "Fasting: Ramadan."
            return "Sunnah to fast: " + n.why.join(", ") + "."
          }
          color: root.calSelected && root.calSelected.notes.fast === "forbidden" ? Color.urgent : root.dim
          font.family: root.family
          font.pixelSize: Style.font.bodySmall
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "←/→ day  ·  ↑/↓ week  ·  [ ] month  ·  t: today  ·  enter: open the day  ·  i: save the year's sacred days (.ics)  ·  esc: back"
        color: root.dim
        font.family: root.family
        font.pixelSize: Style.font.caption
      }
    }

    // ---- The sun's day.
    Canvas {
      id: skyCanvas
      Accessible.role: Accessible.Graphic
      Accessible.name: !root.viewTimes ? "" : "The sun's path. " + root.rows.map(function(k) {
        return Model.LABELS[k] + " " + Model.prayerClock(k, root.viewTimes[k], root.zone) }).join(", ")
        + (root.next && root.viewingToday ? ". Next: " + root.next.label + " in " + Model.countdown(root.next.time - root.now) : "")
      visible: root.showSky
      width: parent.width
      height: Style.space(190)

      readonly property real plotTop: Style.space(14)
      readonly property real horizonY: height * 0.58
      readonly property real plotBottom: height - Style.space(16)

      function xAt(t) { return (t - root.curve.start) / (root.curve.end - root.curve.start) * width }
      // Piecewise: 0..80° above the horizon, 0..-60° below.
      function yAt(alt) {
        if (alt >= 0) return horizonY - Math.min(alt, 80) / 80 * (horizonY - plotTop)
        return horizonY + Math.min(-alt, 60) / 60 * (plotBottom - horizonY)
      }

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        if (!root.curve) return
        var c = root.curve, n = c.sun.length
        var dx = width / (n - 1)

        // Twilight bands: civil, nautical, astronomical.
        var bands = [[0, -6, 0.10], [-6, -12, 0.06], [-12, -18, 0.03]]
        for (var bi = 0; bi < bands.length; bi++) {
          ctx.fillStyle = root.css(Util.alpha(root.accent, bands[bi][2]))
          ctx.fillRect(0, yAt(bands[bi][0]), width, yAt(bands[bi][1]) - yAt(bands[bi][0]))
        }

        // Windows: makruh in the urgent colour, the last third of the night in
        // the accent, Duha as a strip along the top, midnight as a tick.
        var w = root.windows
        function band(span, color, label) {
          var a = Math.max(xAt(span[0]), 0), b = Math.min(xAt(span[1]), width)
          if (b <= a) return
          ctx.fillStyle = root.css(color)
          ctx.fillRect(a, plotTop - 6, b - a, plotBottom - plotTop + 6)
          if (label) {
            ctx.fillStyle = root.css(root.dim)
            ctx.font = Style.font.caption + "px \"" + root.family + "\""
            ctx.textAlign = "center"
            ctx.fillText(label, (a + b) / 2, plotTop + 4)
          }
        }
        for (var mi = 0; mi < w.makruh.length; mi++) band(w.makruh[mi], Util.alpha(Color.urgent, 0.16), "")
        for (var li = 0; li < w.lastThird.length; li++) band(w.lastThird[li], Util.alpha(root.accent, 0.08), "last third")
        if (w.duha) {
          ctx.fillStyle = root.css(Util.alpha(root.accent, 0.45))
          ctx.fillRect(xAt(w.duha[0]), plotTop - 6, xAt(w.duha[1]) - xAt(w.duha[0]), 2)
        }
        for (var ni = 0; ni < w.midnight.length; ni++) {
          var mx = xAt(w.midnight[ni])
          if (mx < 0 || mx > width) continue
          ctx.fillStyle = root.css(root.dim)
          ctx.fillRect(mx, horizonY - 4, 1, 8)
        }

        // Ramadan: the fast, Fajr to Maghrib, as a bar above everything.
        if (root.ramadan) {
          ctx.fillStyle = root.css(root.accent)
          ctx.fillRect(xAt(root.ramadan.fastStart), plotTop - 12, xAt(root.ramadan.fastEnd) - xAt(root.ramadan.fastStart), 3)
        }

        // Daylight: the area between the sun's curve and the horizon.
        ctx.fillStyle = root.css(Util.alpha(root.accent, 0.16))
        ctx.beginPath()
        ctx.moveTo(0, horizonY)
        for (var i = 0; i < n; i++) ctx.lineTo(i * dx, Math.min(yAt(c.sun[i]), horizonY))
        ctx.lineTo(width, horizonY)
        ctx.closePath()
        ctx.fill()

        // Reference lines: horizon, and the angles that define prayers.
        function hline(alt, dash, alpha) {
          ctx.strokeStyle = root.css(Util.alpha(root.fg, alpha))
          ctx.lineWidth = 1
          ctx.setLineDash(dash)
          ctx.beginPath(); ctx.moveTo(0, yAt(alt)); ctx.lineTo(width, yAt(alt)); ctx.stroke()
          ctx.setLineDash([])
        }
        hline(0, [], 0.45)
        var t = root.viewTimes
        if (t.angles.fajr !== null) hline(t.angles.fajr, [3, 4], 0.25)
        if (t.angles.isha !== null && t.angles.isha !== t.angles.fajr) hline(t.angles.isha, [3, 4], 0.25)
        hline(t.angles.asr, [3, 4], 0.25)

        // Hour ticks.
        ctx.fillStyle = root.css(root.dim)
        ctx.font = Style.font.caption + "px \"" + root.family + "\""
        ctx.textAlign = "center"
        for (var h = 0; h <= 24; h += 3) {
          var tx = h / 24 * width
          ctx.fillRect(tx, height - Style.space(13), 1, 3)
          if (h > 0 && h < 24) ctx.fillText((h < 10 ? "0" : "") + h, tx, height - 1)
        }

        // The moon, faint and dashed.
        ctx.strokeStyle = root.css(Util.alpha(root.fg, 0.30))
        ctx.setLineDash([2, 3])
        ctx.lineWidth = 1
        ctx.beginPath()
        for (var m = 0; m < n; m++) {
          if (m === 0) ctx.moveTo(0, yAt(c.moon[0])); else ctx.lineTo(m * dx, yAt(c.moon[m]))
        }
        ctx.stroke()
        ctx.setLineDash([])

        // The sun.
        ctx.strokeStyle = root.css(root.accent)
        ctx.lineWidth = 2
        ctx.beginPath()
        for (var s = 0; s < n; s++) {
          if (s === 0) ctx.moveTo(0, yAt(c.sun[0])); else ctx.lineTo(s * dx, yAt(c.sun[s]))
        }
        ctx.stroke()

        // Each prayer where the curve crosses its line.
        ctx.textAlign = "center"
        for (var p = 0; p < root.rows.length; p++) {
          var key = root.rows[p]
          // After midnight (Isha in a high-latitude summer) belongs to tomorrow's chart.
          if (t[key] === null || t[key] < c.start || t[key] >= c.end) continue
          var px = xAt(t[key])
          var py = yAt(Model.sunPosition(t[key], root.lat, root.lon).altitude)
          var isNext = root.viewingToday && root.next && root.next.key === key && Model.localMidnight(root.next.time, root.zone) === c.start
          ctx.fillStyle = root.css(isNext ? root.accent : root.fg)
          ctx.beginPath(); ctx.arc(px, py, isNext ? 4.5 : 3, 0, 2 * Math.PI)
          // Estimated (high latitude): a ring, since the sun never reaches the line.
          if (t.adjusted[key]) { ctx.strokeStyle = ctx.fillStyle; ctx.lineWidth = 1.5; ctx.stroke() } else ctx.fill()
          var above = key === "dhuhr" || key === "asr"
          ctx.fillText(Model.prayerLabel(key, root.viewNoon, root.zone, root.lang), px, above ? py - 9 : py + 15)
        }

        // The moment the sun stands in the qibla: a small diamond on the curve.
        if (root.qiblaSun && root.qiblaSun.toward !== null) {
          var kx = xAt(root.qiblaSun.toward), ky = yAt(Model.sunPosition(root.qiblaSun.toward, root.lat, root.lon).altitude)
          ctx.save()
          ctx.translate(kx, ky); ctx.rotate(Math.PI / 4)
          ctx.fillStyle = root.css(root.fg)
          ctx.fillRect(-3.5, -3.5, 7, 7)
          ctx.restore()
        }

        // Now: a line, and the sun where it really is.
        if (root.viewingToday && root.sunNow) {
          var nx = xAt(root.now)
          ctx.strokeStyle = root.css(Util.alpha(root.fg, 0.35))
          ctx.beginPath(); ctx.moveTo(nx, plotTop - 6); ctx.lineTo(nx, plotBottom); ctx.stroke()
          var ny = yAt(root.sunNow.altitude)
          ctx.fillStyle = root.css(Util.alpha(root.accent, 0.25))
          ctx.beginPath(); ctx.arc(nx, ny, 10, 0, 2 * Math.PI); ctx.fill()
          ctx.fillStyle = root.css(root.accent)
          ctx.beginPath(); ctx.arc(nx, ny, 5.5, 0, 2 * Math.PI); ctx.fill()
        }

        // Hover crosshair.
        if (root.hoverFraction >= 0) {
          var hx = root.hoverFraction * width
          ctx.strokeStyle = root.css(Util.alpha(root.fg, 0.5))
          ctx.setLineDash([1, 2])
          ctx.beginPath(); ctx.moveTo(hx, plotTop - 6); ctx.lineTo(hx, plotBottom); ctx.stroke()
          ctx.setLineDash([])
        }
      }

      Connections {
        target: root
        function onHoverFractionChanged() { skyCanvas.requestPaint() }
        function onNowChanged() { if (root.active) skyCanvas.requestPaint() }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: function(mouse) { root.hoverFraction = Math.max(0, Math.min(1, mouse.x / width)) }
        onExited: root.hoverFraction = -1
      }
    }

    // ---- What the curve means at the pointer (or a key to the lines).
    Text {
      visible: root.showSky
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      color: root.dim
      font.family: root.family
      font.pixelSize: Style.font.bodySmall
      text: {
        if (!root.curve || !root.viewTimes) return ""
        if (root.hoverFraction < 0) {
          var a = root.viewTimes.angles
          // ponytail: polar day/night only explains itself; scholars differ on
          // whose times to follow (the nearest city with a sunset, or Makkah's).
          if (root.viewTimes.sunrise === null && root.viewTimes.maghrib === null)
            return (root.viewTimes.noonAltitude > 0 ? "Midnight sun: the sun does not set today." : "Polar night: the sun does not rise today.")
              + " Falak cannot place Fajr, sunrise, Maghrib or Isha by the sun here. Many scholars advise the times of the nearest place where it sets, or Makkah's."
          if (root.viewTimes.adjusted.fajr || root.viewTimes.adjusted.isha)
            return "Tonight the sun never sinks " + Math.abs(a.fajr) + "° below the horizon, so Fajr and Isha are estimated ("
              + Model.HIGH_LATITUDE[root.viewTimes.highLatitude].name + " rule). Hollow dots mark them."
          var fi = "Fajr and Isha: the sun " + Math.abs(a.fajr) + "° below the horizon"
          // The Moonsighting Committee counts minutes by season; say where that puts the sun.
          if (a.fajr === null && root.viewTimes.fajr !== null && root.viewTimes.isha !== null) {
            var vt = root.viewTimes, sunAt = function(ms) { return Math.abs(Model.sunPosition(ms, root.lat, root.lon).altitude).toFixed(1) }
            fi = "Fajr " + Math.round((vt.sunrise - vt.fajr) / 60000) + " min before sunrise (sun " + sunAt(vt.fajr) + "° down), Isha "
              + Math.round((vt.isha - vt.sunset) / 60000) + " min after sunset (" + sunAt(vt.isha) + "°), by season"
          }
          return fi + "  ·  "
            + "Asr: shadows " + (root.opts.asr === "standard" ? "their own height" : "twice their height") + " longer than at noon, sun at "
            + a.asr.toFixed(1) + "°  ·  Dhuhr: the sun at its highest, " + root.viewTimes.noonAltitude.toFixed(1) + "°"
        }
        var t = root.curve.start + root.hoverFraction * (root.curve.end - root.curve.start)
        var s = Model.sunPosition(t, root.lat, root.lon)
        var mo = Model.moonPosition(t, root.lat, root.lon)
        var inWindow = root.windowAt(t)
        var where = s.altitude >= 0 ? s.altitude.toFixed(1) + "° up" : Math.abs(s.altitude).toFixed(1) + "° below the horizon"
        return Model.hhmm(t, root.zone) + "  ·  sun " + where + ", " + Model.compassPoint(s.azimuth)
          + "  ·  moon " + (mo.altitude >= 0 ? mo.altitude.toFixed(0) + "° up, " + Model.compassPoint(mo.azimuth) : "set")
          + (inWindow ? "  ·  " + inWindow : "")
      }
    }

    // ---- The six times.
    Row {
      visible: root.showSky
      width: parent.width
      Repeater {
        model: root.rows
        Column {
          required property string modelData
          readonly property bool isNext: root.viewingToday && root.next && root.next.key === modelData && Model.localMidnight(root.next.time, root.zone) === Model.localMidnight(root.viewMs, root.zone)
          readonly property bool past: root.viewingToday && root.viewTimes && root.viewTimes[modelData] !== null && root.viewTimes[modelData] <= root.now
          width: parent.width / root.rows.length
          spacing: Style.space(3)
          opacity: past && !isNext ? 0.5 : 1
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !Model.isRtl(root.lang)
            text: modelData === "dhuhr" && Model.civil(root.viewNoon, root.zone).getUTCDay() === 5 ? "الجمعة" : Model.ARABIC[modelData]
            color: isNext ? root.accent : root.dim
            font.family: "Noto Naskh Arabic"
            font.pixelSize: Style.font.title
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Model.prayerLabel(modelData, root.viewNoon, root.zone, root.lang)
            color: isNext ? root.accent : root.fg
            font.family: root.family
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.viewTimes ? root.num((root.viewTimes.adjusted[modelData] ? "≈" : "") + Model.prayerClock(modelData, root.viewTimes[modelData], root.zone)) : ""
            color: isNext ? root.accent : root.fg
            font.family: root.family
            font.pixelSize: Style.font.heading
            font.bold: isNext
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: isNext ? (root.lang === "en" ? "in " : "") + root.num(Model.countdown(root.next.time - root.now))
              : (root.viewTimes && root.viewTimes.adjusted[modelData]) ? Model.t(root.lang, "estimated")
              : (root.ramadan && modelData === "fajr") ? (root.lang === "en" ? "suhoor ends" : Model.t(root.lang, "suhoor"))
              : (root.ramadan && modelData === "maghrib") ? (root.lang === "en" ? "iftar" : Model.t(root.lang, "iftar"))
              : (modelData === "asr" ? root.otherAsr : " ")
            color: isNext ? root.accent : root.dim
            font.family: root.family
            font.pixelSize: Style.font.caption
          }
          // Your mosque's iqama, when its timetable has this day.
          Text {
            readonly property double at: root.iqama && modelData !== "sunrise" ? Model.iqamaTime(root.iqama, modelData, root.viewNoon, root.zone) || 0 : 0
            visible: at > 0
            anchors.horizontalCenter: parent.horizontalCenter
            text: "iqama " + root.num(Model.hhmm(at, root.zone))
            color: root.accent
            font.family: root.family
            font.pixelSize: Style.font.caption
          }
          // When the countdown has Asr's line, the other school's time goes under it.
          Text {
            visible: modelData === "asr" && isNext
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.otherAsr
            color: root.dim
            font.family: root.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    Rectangle { visible: root.showSky; width: parent.width; height: 1; color: root.faint }

    // ---- Qibla, and how to find it with nothing but the sun.
    Row {
      visible: root.showSky
      width: parent.width
      spacing: Style.space(16)

      Canvas {
        id: compass
        Accessible.role: Accessible.Graphic
        Accessible.name: root.qibla ? "Qibla " + Math.round(root.qibla.bearing) + " degrees, " + Model.compassPoint(root.qibla.bearing) : ""
        width: Style.space(64)
        height: width
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var cx = width / 2, cy = height / 2, r = width / 2 - 2
          ctx.strokeStyle = root.css(root.faint)
          ctx.lineWidth = 1
          ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.stroke()
          ctx.fillStyle = root.css(root.dim)
          ctx.font = Style.font.caption + "px \"" + root.family + "\""
          ctx.textAlign = "center"
          ctx.fillText("N", cx, 11)
          function rim(bearing, inset) {
            var a = (bearing - 90) * Math.PI / 180
            return [cx + (r - inset) * Math.cos(a), cy + (r - inset) * Math.sin(a)]
          }
          if (root.sunNow && root.sunNow.altitude > -0.833) {
            var sp = rim(root.sunNow.azimuth, 5)
            ctx.fillStyle = root.css(root.accent)
            ctx.beginPath(); ctx.arc(sp[0], sp[1], 4, 0, 2 * Math.PI); ctx.fill()
          }
          if (root.qibla) {
            var tip = rim(root.qibla.bearing, 6)
            ctx.strokeStyle = root.css(root.fg)
            ctx.lineWidth = 2
            ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(tip[0], tip[1]); ctx.stroke()
            ctx.fillStyle = root.css(root.fg)
            ctx.beginPath(); ctx.arc(tip[0], tip[1], 3, 0, 2 * Math.PI); ctx.fill()
            ctx.beginPath(); ctx.arc(cx, cy, 2, 0, 2 * Math.PI); ctx.fill()
          }
        }
        Connections {
          target: root
          function onSunNowChanged() { compass.requestPaint() }
          function onQiblaChanged() { compass.requestPaint() }
        }
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)
        width: parent.width - compass.width - parent.spacing
        Text {
          text: root.qibla ? "Qibla " + root.qibla.bearing.toFixed(1) + "° " + Model.compassPoint(root.qibla.bearing)
            + "  ·  " + Math.round(root.qibla.km).toLocaleString(Qt.locale(), "f", 0) + " km to the Kaaba" : ""
          color: root.fg
          font.family: root.family
          font.pixelSize: Style.font.body
        }
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          color: root.dim
          font.family: root.family
          font.pixelSize: Style.font.bodySmall
          text: {
            if (!root.qibla || !root.sunNow) return ""
            if (root.sunNow.altitude <= -0.833) return "The sun is down. By day, Falak tells you how far to turn from it to face the qibla."
            var turn = ((root.qibla.bearing - root.sunNow.azimuth + 540) % 360) - 180
            var deg = Math.round(Math.abs(turn))
            if (deg <= 2) return "Face the sun: right now it stands in the qibla."
            return "Face the sun, then turn " + deg + "° to your " + (turn > 0 ? "right" : "left") + ". No compass needed."
          }
        }
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          visible: text !== ""
          color: root.dim
          font.family: root.family
          font.pixelSize: Style.font.bodySmall
          text: {
            var q = root.qiblaSun, parts = []
            if (q && q.toward !== null) parts.push("◆ At " + Model.hhmm(q.toward, root.zone) + " the sun stands in the qibla.")
            if (q && q.shadows !== null) parts.push("At " + Model.hhmm(q.shadows, root.zone) + " every shadow points to it.")
            return parts.join(" ")
          }
        }
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          visible: text !== ""
          color: root.accent
          font.family: root.family
          font.pixelSize: Style.font.bodySmall
          text: {
            var r = root.rasd
            if (!r) return ""
            var days = Math.round((Model.localMidnight(r.time, root.zone) - root.dayKey) / 86400000)
            var when = Model.dayTimeText(r.time, root.zone) + (days > 0 ? " (in " + days + (days === 1 ? " day)" : " days)") : " (today)")
            return r.kind === "kaaba"
              ? when + ": the sun stands over the Kaaba. Every shadow on Earth points away from it."
              : when + ": the sun stands over the far side of the Earth from the Kaaba. Every shadow here points to it."
          }
        }
      }
    }

    // ---- A verse for the day shown (assets/verses.json); 55:5 until it loads.
    Column {
      visible: root.showSky
      width: parent.width
      spacing: Style.space(3)
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.verse ? root.verse[2] : "الشَّمْسُ وَالْقَمَرُ بِحُسْبَانٍ"
        color: root.fg
        font.family: "Noto Naskh Arabic"
        font.pixelSize: root.verse && root.verse[2].length > 120 ? Style.font.body + 1 : Style.font.heading
      }
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.verse ? root.verse[3] + "  (" + root.verse[1] + " " + root.verse[0] + ")"
          : "The sun and the moon move by precise calculation. Ar-Rahman 55:5"
        color: root.dim
        font.family: root.family
        font.pixelSize: Style.font.caption
      }
    }

    // ---- Keys, then the method in use.
    Column {
      visible: !!root.location
      width: parent.width
      spacing: Style.space(2)
      // Hint and method lines wrap within the panel; centred, never wider than it.
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        visible: !root.overlayOpen
        text: root.playing ? "playing the year  ·  space to stop" : "←/→ day  ·  ↑/↓ month  ·  space: play the year  ·  t: today  ·  ?: every key"
        color: root.playing ? root.accent : root.dim
        font.family: root.family
        font.pixelSize: Style.font.caption
      }
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: (root.viewTimes ? root.viewTimes.method : "") + "  ·  " + (root.opts.asr === "standard" ? "standard" : "Hanafi") + " Asr"
          + (root.viewTimes && (root.viewTimes.adjusted.fajr || root.viewTimes.adjusted.isha) ? "  ·  high latitude: " + Model.HIGH_LATITUDE[root.viewTimes.highLatitude].name : "")
        color: methodArea.containsMouse ? root.accent : Util.alpha(root.fg, 0.35)
        font.family: root.family
        font.pixelSize: Style.font.caption
        MouseArea { id: methodArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.startMethods() }
      }
    }
  }
}
