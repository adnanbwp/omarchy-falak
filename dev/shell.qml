import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "plugin"
import "plugin/Model.js" as Model

// Headless render of FalakView for one scenario, then quit. Driven by
// dev/render; nothing here touches Wayland, Hyprland or the running shell.
ShellRoot {
  id: shellRoot
  readonly property var scenario: JSON.parse(Quickshell.env("FALAK_SCENARIO") || "{}")
  readonly property var place: scenario.location === null ? null
    : (scenario.location || { name: "Melbourne", latitude: -37.8136, longitude: 144.9631 })
  // As FalakPanel does: the places list, the country, then "auto" resolved.
  property var cities: null
  property var land: null
  FileView {
    path: Quickshell.shellDir + "/plugin/assets/land.json"
    onLoaded: shellRoot.land = JSON.parse(text())
  }
  FileView {
    path: Quickshell.shellDir + "/plugin/assets/cities.json"
    onLoaded: shellRoot.cities = Model.parseCities(text())
  }
  readonly property string country: place && place.country ? place.country
    : (cities && place ? Model.nearestCity(cities, place.latitude, place.longitude).country : "")
  readonly property string zoneName: place && place.tz ? place.tz
    : (cities && place ? Model.nearestCity(cities, place.latitude, place.longitude).tz : "")
  property var zone: null
  onZoneNameChanged: { var cmd = Model.zoneCommand(zoneName, Date.now()); if (cmd) { zoneProc.command = cmd; zoneProc.running = true } }
  Process {
    id: zoneProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: shellRoot.zone = Model.parseZone(shellRoot.zoneName, text) }
  }

  // A scenario with "sky": true renders the full-screen sky dome instead.
  property var verseData: null
  FileView {
    path: Quickshell.shellDir + "/plugin/assets/verses.json"
    onLoaded: shellRoot.verseData = JSON.parse(text())
  }
  property var skyData: null
  FileView {
    path: Quickshell.shellDir + "/plugin/assets/sky.json"
    onLoaded: shellRoot.skyData = JSON.parse(text())
  }
  FloatingWindow {
    visible: !!scenario.sky
    implicitWidth: 1280
    implicitHeight: 800
    SkyView {
      id: skyView
      width: 1280; height: 800
      now: scenario.now ? new Date(scenario.now).getTime() : Date.now()
      location: shellRoot.place
      zone: shellRoot.zone
      sky: shellRoot.skyData
      Component.onCompleted: offset = (scenario.skyOffsetHours || 0) * 3600000
    }
  }

  FloatingWindow {
    visible: !scenario.sky
    implicitWidth: 640
    implicitHeight: 900
    color: Color.popups.background

    Rectangle {
      id: frame
      width: 640
      height: view.implicitHeight + 48
      color: Color.popups.background
      border.color: Color.popups.border
      border.width: 2

      FalakView {
        id: view
        x: 24; y: 24
        width: frame.width - 48
        now: scenario.now ? new Date(scenario.now).getTime() : Date.now()
        location: shellRoot.place
        opts: Model.resolveOpts(scenario.opts || { method: "auto", asr: "auto" }, shellRoot.country, shellRoot.zone)
        cities: shellRoot.cities
        land: shellRoot.land
        country: shellRoot.country
        hijriOffset: scenario.hijriOffset || 0
        active: false
        home: scenario.home || null
        verses: shellRoot.verseData
        iqama: scenario.iqamaCsv ? Model.parseIqama(scenario.iqamaCsv) : null
        mosqueFile: scenario.iqamaCsv ? "mosque.csv" : ""
        Component.onCompleted: { dayOffset = scenario.dayOffset || 0; hoverFraction = scenario.hover === undefined ? -1 : scenario.hover }
        onCitiesChanged: {
          if (cities && scenario.search !== undefined) startSearch(scenario.search)
          if (cities && scenario.methods) { startMethods(); if (scenario.methodIndex !== undefined) methodIndex = scenario.methodIndex }
          if (cities && scenario.calendar) { startCalendar(); calDay += scenario.calendarDays || 0 }
          if (cities && scenario.crescent) { startCrescent(); crescentEvening = scenario.crescentEvening || 0 }
          if (cities && scenario.eclipses) { startEclipses(); eclipseIndex = scenario.eclipseIndex || 0 }
          if (cities && scenario.help) startHelp()
          if (cities && scenario.journalView) { journalOn = !!scenario.journalOn; journal = scenario.journal || ({}); startJournal() }
          if (cities && scenario.teach !== undefined) { startTeach(); teachStep = scenario.teach; gnomonFraction = scenario.gnomon === undefined ? 0.5 : scenario.gnomon }
          if (cities && scenario.adjustView) { adjust = scenario.adjust || ({ elevation: 0, offsets: {} }); home = scenario.home || null; startAdjust() }
          if (cities && scenario.tasbih !== undefined) { startTasbih(); tasbihCount = scenario.tasbih }
          if (cities && scenario.alertsView) { userAdhans = scenario.userAdhans || []; alerts = Model.alertSettings(scenario.alerts || {}); startAlerts(); alertRow = scenario.alertRow || 0
            var ev = Model.alertEvents(now, location, opts, alerts, 0); for (var i = 0; i < ev.length; i++) if (ev[i].time > now) { nextAlert = ev[i]; break } }
        }
      }
    }

    Timer {
      interval: 1500
      running: true
      onTriggered: (scenario.sky ? skyView : frame).grabToImage(function(result) {
        console.log("falak-render", result.saveToFile(Quickshell.env("FALAK_OUT")) ? "ok" : "failed", Quickshell.env("FALAK_OUT"))
        console.log("falak-pill", JSON.stringify(Model.pill(view.now, view.location, view.opts)))
        Qt.quit()
      })
    }
  }
}
