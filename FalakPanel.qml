import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Falak's panel: lifecycle, settings, location, clock and the pill. What it
// shows is FalakView.qml. ←/→ walk the days, space plays the year, t returns
// to today.
Panel {
  id: root
  moduleName: "adnanbwp.falak"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  // For dev/check-panel, which drives the view headless.
  readonly property var panelView: view

  // ---- Lifecycle (the weather panel's pattern).
  function openFromHotkey() {
    root.now = Date.now()
    view.dayOffset = 0
    root.controller.show()
  }
  function close() {
    view.playing = false
    root.controller.hide()
  }
  function toggle() { if (root.opened) root.close(); else root.openFromHotkey() }
  function switchPanel(direction) {
    return root.bar && typeof root.bar.switchPanelFrom === "function"
      ? root.bar.switchPanelFrom(root.barIdentity, direction) : false
  }

  // ---- Settings, from this widget's shell.json entry. "auto" method and Asr
  //      follow the country (Model.COUNTRY_METHOD).
  // A choice made in the panel shows at once; the settings round trip catches up.
  property var pendingSettings: ({})
  onSettingsChanged: pendingSettings = ({})
  function opt(name, fallback) { return pendingSettings[name] !== undefined ? pendingSettings[name] : setting(name, fallback) }
  readonly property var rawOpts: ({ method: String(opt("method", "auto")), asr: String(opt("asr", "auto")),
                                     highLatitude: String(setting("highLatitude", "angle")),
                                     lang: Model.language(String(setting("language", "auto")), Qt.locale().name),
                                     numerals: String(setting("numerals", "auto")),
                                     elevation: Number(adjustSetting.elevation) || 0, offsets: adjustSetting.offsets || null })
  readonly property var adjustSetting: opt("adjust", null) || ({ elevation: 0, offsets: {} })
  readonly property var homeSetting: Model.parseLocation(JSON.stringify(opt("home", null)))
  readonly property var opts: Model.resolveOpts(rawOpts, country, zone)
  readonly property int hijriOffset: parseInt(setting("hijriOffset", 0), 10) || 0

  // ---- Location: Falak's own (chosen in the panel, stored in its settings),
  //      else the weather widget's file, so one place can serve both.
  readonly property var ownLocation: Model.parseLocation(JSON.stringify(setting("location", null)))
  property var weatherLocation: null
  // A pick shows at once; the settings round trip catches up.
  property var pendingLocation: undefined
  readonly property var location: pendingLocation !== undefined ? pendingLocation : (ownLocation || weatherLocation)
  onOwnLocationChanged: pendingLocation = undefined
  property FileView locationFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.weatherLocation = Model.parseLocation(text())
    onLoadFailed: root.weatherLocation = null
  }

  // ---- Places (1.8 MB): loaded only to search, or to find the country of a
  //      location that came without one.
  property bool citiesWanted: false
  property var cities: null
  readonly property string country: location && location.country ? location.country
    : (cities && location ? Model.nearestCity(cities, location.latitude, location.longitude).country : "")
  onLocationChanged: if (location && (!location.country || !location.tz)) citiesWanted = true
  property FileView citiesFile: FileView {
    path: root.citiesWanted ? Qt.resolvedUrl("assets/cities.json").toString().replace(/^file:\/\//, "") : ""
    printErrors: false
    onLoaded: root.cities = Model.parseCities(text())
  }

  // ---- The place's clock: its IANA zone, read once through zdump (Qt's JS
  //      has no time zones). Covers last year to six years ahead.
  readonly property string zoneName: location && location.tz ? location.tz
    : (cities && location ? Model.nearestCity(cities, location.latitude, location.longitude).tz : "")
  property var zone: null
  onZoneNameChanged: {
    var cmd = Model.zoneCommand(zoneName, Date.now())
    if (!cmd) { zone = null; return }
    zoneProc.command = cmd
    zoneProc.running = true
  }
  Process {
    id: zoneProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.zone = Model.parseZone(root.zoneName, text)
    }
  }

  // ---- For scripts: omarchy-shell adnanbwp.falak next | times | hijri | pill.
  //      (With two bars, one instance answers; their answers are the same.)
  IpcHandler {
    target: root.moduleName
    function next(): string {
      var n = Model.nextPrayer(root.now, root.location ? root.location.latitude : 0, root.location ? root.location.longitude : 0, root.opts)
      return !root.location || !n ? "{}" : JSON.stringify({ prayer: n.key, label: Model.prayerLabel(n.key, n.time, root.zone, "en"),
        time: Model.prayerClock(n.key, n.time, root.zone), in: Model.countdown(n.time - root.now), epoch: Math.round(n.time / 1000) })
    }
    function times(): string {
      if (!root.location) return "{}"
      var t = Model.prayerTimes(root.now, root.location.latitude, root.location.longitude, root.opts), out = { place: root.location.name, method: t.method }
      for (var i = 0; i < Model.PRAYERS.length; i++) out[Model.PRAYERS[i]] = Model.prayerClock(Model.PRAYERS[i], t[Model.PRAYERS[i]], root.zone)
      return JSON.stringify(out)
    }
    function hijri(): string {
      var h = Model.hijriDate(root.now, root.hijriOffset, false, root.zone)
      return h.day + " " + h.monthName + " " + h.year
    }
    function pill(): string { return root.label.replace(/^\S+ /, "") }
  }

  // ---- The sky dome: full screen, on the bar's monitor, opened with "s".
  property bool skyOpen: false
  property bool skyWanted: false
  property var skyData: null
  property FileView skyFile: FileView {
    path: root.skyWanted ? Qt.resolvedUrl("assets/sky.json").toString().replace(/^file:\/\//, "") : ""
    printErrors: false
    onLoaded: { try { root.skyData = JSON.parse(text()) } catch (e) { root.skyData = null } }
  }
  function openSky() {
    skyWanted = true
    root.close()
    skyWindow.view.offset = 0
    skyWindow.view.playing = false
    skyOpen = true
    Qt.callLater(function() { skyWindow.view.forceActiveFocus() })
  }
  SkyWindow {
    id: skyWindow
    shown: root.skyOpen
    screen: root.anchorItem && root.anchorItem.QsWindow.window ? root.anchorItem.QsWindow.window.screen : null
    view.now: root.now
    view.location: root.location
    view.zone: root.zone
    view.sky: root.skyData
    view.family: root.bar ? root.bar.fontFamily : Style.font.family
  }
  Connections {
    target: skyWindow.view
    function onCloseRequested() { root.skyOpen = false; skyWindow.view.playing = false }
  }

  // ---- The journal file: written only when you tick a prayer, never sent anywhere.
  readonly property string journalPath: Quickshell.env("HOME") + "/.local/share/falak/journal.json"
  property var journalData: ({})
  property FileView journalFile: FileView {
    path: root.journalPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.journalData = Model.parseJournal(text())
    onLoadFailed: root.journalData = ({})
  }
  function saveJournal(j) {
    root.journalData = j
    Quickshell.execDetached(["sh", "-c", 'mkdir -p "${1%/*}" && printf "%s" "$2" > "$1.tmp" && mv "$1.tmp" "$1"', "falak-journal", journalPath, JSON.stringify(j)])
  }
  function eraseJournal() { root.journalData = ({}); Quickshell.execDetached(["rm", "-f", journalPath]) }

  // The verses (25 KB), read once.
  property var verses: null
  property FileView versesFile: FileView {
    path: Qt.resolvedUrl("assets/verses.json").toString().replace(/^file:\/\//, "")
    printErrors: false
    onLoaded: { try { root.verses = JSON.parse(text()) } catch (e) { root.verses = null } }
  }

  // The crescent map's coastline (16 KB), loaded the first time it opens.
  property bool landWanted: false
  property var land: null
  property FileView landFile: FileView {
    path: root.landWanted ? Qt.resolvedUrl("assets/land.json").toString().replace(/^file:\/\//, "") : ""
    printErrors: false
    onLoaded: { try { root.land = JSON.parse(text()) } catch (e) { root.land = null } }
  }

  function savePlace(place) {
    root.pendingLocation = place
    var value = place ? JSON.stringify({ name: place.name, region: place.region || "", country: place.country || "",
                                         tz: place.tz || "", latitude: place.latitude, longitude: place.longitude }) : "null"
    saveProc.command = ["omarchy-bar", "set", root.moduleName, "location", value, "--json"]
    saveProc.running = true
  }
  Process { id: saveProc }

  // Strings as they are; objects (the alerts) as JSON.
  function saveSetting(key, value) {
    var next = {}
    for (var k in pendingSettings) next[k] = pendingSettings[k]
    next[key] = value
    pendingSettings = next
    settingProc.command = typeof value === "object"
      ? ["omarchy-bar", "set", root.moduleName, key, JSON.stringify(value), "--json"]
      : ["omarchy-bar", "set", root.moduleName, key, value]
    settingProc.running = true
  }
  Process { id: settingProc }
  // The first read can race shell startup (the weather panel saw it too), so
  // read once more shortly after; identical content changes nothing.
  Timer {
    interval: 1500
    running: true
    onTriggered: locationFile.reload()
  }

  // ---- Clock. Coarse while closed (the pill shows minutes), every second open...
  property double now: Date.now()
  Timer {
    // ...and every second for the last ten minutes before iftar or suhoor's end,
    // and in the minute before an alert, so it fires on the second.
    interval: root.opened || root.skyOpen || root.pill.fast || (root.nextAlert && root.nextAlert.time - root.now < 60000) ? 1000 : 15000
    running: true
    repeat: true
    onTriggered: root.now = Date.now()
  }

  // ---- Adhan and reminders. The schedule lives here, in the bar widget: no
  //      widget on the bar, no alerts. falak-alert does the announcing, once
  //      across all bars (its own marker), and is launched detached so a
  //      shell reload cannot cut an adhan off.
  readonly property var alertsRaw: opt("alerts", null)
  readonly property var alerts: Model.alertSettings(alertsRaw)
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  // Recomputed every ten minutes (and on any change), not every second.
  readonly property double alertsEpoch: Math.floor(now / 600000) * 600000
  // Visible eclipses for the eclipse alert: once a day, only when asked for.
  readonly property double alertsDay: Math.floor(now / 86400000)
  readonly property var alertEclipses: alerts.enabled && alerts.eclipses === "notify" && location
    ? Model.nextEclipses(alertsDay * 86400000, location.latitude, location.longitude, 2, 3) : []
  readonly property var alertList: Model.alertEvents(alertsEpoch, location, opts, alertsRaw, hijriOffset, alertEclipses, iqama)

  // ---- Your mosque's timetable: the newest CSV in ~/.local/share/falak/mosque.
  readonly property string mosqueDir: Quickshell.env("HOME") + "/.local/share/falak/mosque"
  property var iqama: null
  property string mosqueFile: ""
  function scanMosque() { if (!mosqueScan.running) mosqueScan.running = true }
  Process {
    id: mosqueScan
    command: ["sh", "-c", 'mkdir -p "$1" && f=$(ls -t "$1"/*.csv 2>/dev/null | head -1) && [ -n "$f" ] && { basename "$f"; cat "$f"; } || true', "falak-mosque", root.mosqueDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || ""), nl = t.indexOf("\n")
        root.mosqueFile = nl > 0 ? t.slice(0, nl) : ""
        root.iqama = nl > 0 ? Model.parseIqama(t.slice(nl + 1)) : null
      }
    }
  }
  function openMosqueFolder() { Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && xdg-open "$1"', "falak-mosque", mosqueDir]) }
  readonly property var nextAlert: {
    for (var i = 0; i < alertList.length; i++) if (alertList[i].time > now) return alertList[i]
    return null
  }
  property var fired: ({})
  // Bundled recordings by id; your own as "user:<file>" from the folder below.
  readonly property string userAdhanDir: Quickshell.env("HOME") + "/.local/share/falak/adhans"
  function soundPath(id) {
    if (!id) return ""
    if (id.indexOf("user:") === 0) return userAdhanDir + "/" + id.slice(5).replace(/\//g, "")
    return pluginDir + "/assets/adhans/" + id + ".ogg"
  }
  property var userAdhans: []
  function scanAdhans() { if (!adhanScan.running) adhanScan.running = true }
  Process {
    id: adhanScan
    command: ["sh", "-c", 'mkdir -p "$1" && find "$1" -maxdepth 1 -type f \\( -iname "*.ogg" -o -iname "*.opus" -o -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" \\) -printf "%f\\n" | sort', "falak-adhans", root.userAdhanDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.userAdhans = String(text || "").split("\n").filter(function(n) { return n !== "" })
    }
  }
  // A shell restart mid-focus must not leave Do Not Disturb on: restore if due.
  Component.onCompleted: { scanAdhans(); scanMosque(); Quickshell.execDetached([pluginDir + "/falak-focus", "check"]) }
  function openAdhanFolder() { Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && xdg-open "$1"', "falak-adhans", userAdhanDir]) }
  function fireAlert(e) {
    var f = {}
    for (var k in fired) f[k] = fired[k]
    f[e.key] = true
    fired = f
    Quickshell.execDetached([pluginDir + "/falak-alert", "fire", e.key, e.headline, e.body, soundPath(e.sound), String(alerts.volume)])
    // Prayer focus, a moment later so the prayer's own notification shows first.
    if (e.kind === "start" && e.key.indexOf("-sunrise-") < 0 && alerts.focus > 0)
      Quickshell.execDetached(["sh", "-c", 'sleep 3; exec "$1" begin "$2"', "falak-focus", pluginDir + "/falak-focus", String(alerts.focus)])
  }
  onNowChanged: {
    var due = Model.dueAlerts(alertList, now, fired)
    for (var i = 0; i < due.length; i++) fireAlert(due[i])
  }
  function previewSound(id) { Quickshell.execDetached([pluginDir + "/falak-alert", "preview", soundPath(id), String(alerts.volume)]) }
  function stopSound() { Quickshell.execDetached([pluginDir + "/falak-alert", "stop"]) }
  function testAlert() {
    // Always with the chosen adhan, so it can be heard; still silent under DND.
    fireAlert({ key: "test-" + Date.now(), headline: "Falak test", body: "This is how an adhan alert looks and sounds",
                sound: alerts.sound })
  }

  // ---- The pill.
  readonly property var pill: Model.pill(now, location, opts, hijriOffset)
  readonly property string label: pill.label
  readonly property string glyph: pill.glyph
  readonly property bool inPrayerWindow: pill.active

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(600))
    contentHeight: panel.fittedContentHeight(view.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      objectName: "falakKeys"
      anchors.fill: parent
      // Typing a place: keys belong to the search field.
      blocked: view.editing
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { view.walk(dx !== 0 ? dx : dy * 30) }
      onActivateRequested: view.playing = !view.playing
      onTextKey: function(t) {
        if (t === "t" || t === "T") { view.playing = false; view.dayOffset = 0 }
        // Not "l": PanelKeyCatcher takes h/j/k/l as arrows before textKey.
        else if (t === "p" || t === "P") view.startSearch("")
        else if (t === "m" || t === "M") view.startMethods()
        else if (t === "c" || t === "C") view.startCalendar()
        else if (t === "n" || t === "N") view.startCrescent()
        else if (t === "a" || t === "A") view.startAlerts()
        else if (t === "e" || t === "E") view.startEclipses()
        else if (t === "s" || t === "S") root.openSky()
        else if (t === "?") view.startHelp()
        else if (t === "d" || t === "D") view.startTasbih()
        else if (t === "o" || t === "O") view.startAdjust()
        else if (t === "w" || t === "W") view.startTeach()
        else if (t === "r" || t === "R") view.startJournal()
      }

      FalakView {
        id: view
        width: parent.width
        now: root.now
        location: root.location
        opts: root.opts
        hijriOffset: root.hijriOffset
        cities: root.cities
        ownLocation: !!root.ownLocation
        onCitiesWanted: root.citiesWanted = true
        land: root.land
        onLandWanted: root.landWanted = true
        onLocationPicked: function(place) { root.savePlace(place) }
        onKeysReleased: keyCatcher.forceActiveFocus()
        country: root.country
        onSettingPicked: function(key, value) { root.saveSetting(key, value) }
        alerts: root.alerts
        nextAlert: root.nextAlert
        onPreviewRequested: function(sound) { root.previewSound(sound) }
        onStopRequested: root.stopSound()
        onTestRequested: root.testAlert()
        adjust: root.adjustSetting
        home: root.homeSetting
        verses: root.verses
        journalOn: root.opt("journal", "off") === "on"
        journal: root.journalData
        onJournalSaved: function(j) { root.saveJournal(j) }
        onJournalErased: root.eraseJournal()
        // The coming year's sacred days, saved to Downloads for any calendar app.
        onIcsRequested: function(text, fileName) {
          Quickshell.execDetached(["sh", "-c", 'd=$(xdg-user-dir DOWNLOAD 2>/dev/null); f="${d:-$HOME}/$1"; printf "%s" "$2" > "$f" && omarchy-notification-send --app-name Falak "Saved the sacred days" "$f"', "falak-ics", fileName, text])
        }
        userAdhans: root.userAdhans
        onAdhanFolderRequested: root.openAdhanFolder()
        onAlertsOpenChanged: if (alertsOpen) { root.scanAdhans(); root.scanMosque() }
        onAdjustOpenChanged: if (adjustOpen) root.scanMosque()
        iqama: root.iqama
        mosqueFile: root.mosqueFile
        onMosqueFolderRequested: root.openMosqueFolder()
        family: root.bar ? root.bar.fontFamily : Style.font.family
        active: root.opened
        reducedMotion: !!root.bar && root.bar.foregroundAnimationEnabled === false
      }
    }
  }
}
