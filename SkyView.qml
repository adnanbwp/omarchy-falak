import QtQuick
import qs.Commons
import "Model.js" as Model

// The sky over the place, full screen: zenith at the centre, horizon at the
// rim, north up and east to the left, as you see it lying on your back. Stars
// fade in with the twilight. ←/→ ten minutes (shift: an hour), ↑/↓ a day,
// space plays time, t returns to now, Esc closes.
Item {
  id: root

  property double now: Date.now()
  property var location: null
  property var zone: null
  property var sky: null               // assets/sky.json
  property string family: Style.font.family
  signal closeRequested()

  // Time shown: now plus an offset the keys move; playing runs it forward.
  property double offset: 0
  property bool playing: false
  readonly property double t: now + offset
  readonly property real lat: location ? location.latitude : 0
  readonly property real lon: location ? location.longitude : 0
  readonly property var sun: location ? Model.sunPosition(t, lat, lon) : null
  readonly property var moon: location ? Model.moonPosition(t, lat, lon) : null
  readonly property var phase: Model.moonPhase(t)
  readonly property var qibla: location ? Model.qibla(lat, lon) : null
  onTChanged: canvas.requestPaint()
  onSkyChanged: canvas.requestPaint()

  focus: true
  Keys.onPressed: function(event) {
    var k = event.key, big = event.modifiers & Qt.ShiftModifier
    if (k === Qt.Key_Escape) closeRequested()
    else if (k === Qt.Key_Left || event.text === "h") offset -= big ? 3600000 : 600000
    else if (k === Qt.Key_Right || event.text === "l") offset += big ? 3600000 : 600000
    else if (k === Qt.Key_Up || event.text === "k") offset -= 86400000
    else if (k === Qt.Key_Down || event.text === "j") offset += 86400000
    else if (k === Qt.Key_Space) playing = !playing
    else if (event.text === "t") { offset = 0; playing = false }
    else return
    event.accepted = true
  }
  // Time-lapse: two minutes of sky per frame, about an hour every second.
  Timer {
    interval: 33
    running: root.playing && root.visible
    repeat: true
    onTriggered: root.offset += 120000
  }

  readonly property color fg: Color.popups.text
  readonly property color accent: Color.accent
  function css(c, a) {
    c = Qt.color(c)
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + (a === undefined ? c.a : a) + ")"
  }

  // Night, twilight or day: the sky's own colour from the theme, by the sun.
  readonly property real daylight: !sun ? 0 : Math.max(0, Math.min(1, (sun.altitude + 12) / 18))
  Rectangle {
    anchors.fill: parent
    color: Color.popups.background
    Rectangle { anchors.fill: parent; color: root.accent; opacity: 0.05 + 0.25 * root.daylight }
  }

  Canvas {
    id: canvas
    anchors.fill: parent
    Accessible.role: Accessible.Graphic
    Accessible.name: "The sky over " + (root.location ? root.location.name : "here")
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      if (!root.location) return
      var cx = width / 2, cy = height / 2 - 6, R = Math.min(width, height) / 2 - 76
      // Labels claim space, brightest first; one that would overlap is skipped.
      var placed = []
      var room = function(x, y, w) {
        for (var i = 0; i < placed.length; i++)
          if (Math.abs(placed[i][0] - x) < (placed[i][2] + w) / 2 + 6 && Math.abs(placed[i][1] - y) < 26) return false
        placed.push([x, y, w]); return true
      }
      var at = function(alt, az, below) {
        var p = Model.domeXY(alt, az, below)
        return p ? [cx + p.x * R, cy + p.y * R] : null
      }
      var font = function(px) { return px + "px \"" + root.family + "\"" }
      var starsShown = Math.max(0, Math.min(1, (-root.sun.altitude - 2) / 10))

      // The dome, altitude rings at 30° and 60°, the horizon.
      ctx.strokeStyle = root.css(root.fg, 0.10); ctx.lineWidth = 1
      for (var ring = 30; ring < 90; ring += 30) {
        var rr = Math.tan((90 - ring) * Math.PI / 360) * R
        ctx.beginPath(); ctx.arc(cx, cy, rr, 0, 2 * Math.PI); ctx.stroke()
      }
      ctx.strokeStyle = root.css(root.fg, 0.45); ctx.lineWidth = 1.5
      ctx.beginPath(); ctx.arc(cx, cy, R, 0, 2 * Math.PI); ctx.stroke()

      // Constellation figures, where both ends are up.
      if (root.sky && starsShown > 0) {
        ctx.strokeStyle = root.css(root.accent, 0.35 * starsShown); ctx.lineWidth = 1
        for (var li = 0; li < root.sky.lines.length; li++) {
          var line = root.sky.lines[li], prev = null
          for (var pi = 0; pi < line.length; pi++) {
            var h = Model.horizontal(line[pi][0], line[pi][1], root.t, root.lat, root.lon)
            var pt = at(h.altitude, h.azimuth)
            if (pt && prev) { ctx.beginPath(); ctx.moveTo(prev[0], prev[1]); ctx.lineTo(pt[0], pt[1]); ctx.stroke() }
            prev = pt
          }
        }
      }

      // Stars: size by magnitude, a hint of colour by B−V.
      var labels = []
      if (root.sky && starsShown > 0) {
        for (var si = 0; si < root.sky.stars.length; si++) {
          var st = root.sky.stars[si]
          var hs = Model.horizontal(st[0], st[1], root.t, root.lat, root.lon)
          var ps = at(hs.altitude, hs.azimuth)
          if (!ps) continue
          var size = Math.max(0.6, (5.2 - st[2]) * 0.62)
          var bv = st[3], tint = bv < 0.2 ? "rgba(190,210,255," : bv > 1.0 ? "rgba(255,210,170," : "rgba(255,255,245,"
          ctx.fillStyle = tint + (starsShown * Math.min(1, 0.35 + (5.2 - st[2]) / 5)) + ")"
          ctx.beginPath(); ctx.arc(ps[0], ps[1], size, 0, 2 * Math.PI); ctx.fill()
          var nm = root.sky.names[si]
          if (nm && st[2] <= 1.6) labels.push([ps[0], ps[1], nm[0], nm[1]])
        }
      }
      // Bright stars' names, in English and Arabic.
      ctx.textAlign = "left"
      for (var lb = 0; lb < labels.length; lb++) {
        var l = labels[lb]
        ctx.font = font(12)
        if (!room(l[0] + 7 + ctx.measureText(l[2]).width / 2, l[1] + 5, ctx.measureText(l[2]).width)) continue
        ctx.fillStyle = root.css(root.fg, 0.75 * starsShown)
        ctx.font = font(12); ctx.fillText(l[2], l[0] + 7, l[1] - 2)
        if (l[3]) { ctx.fillStyle = root.css(root.fg, 0.55 * starsShown); ctx.font = "13px \"Noto Naskh Arabic\""; ctx.fillText(l[3], l[0] + 7, l[1] + 13) }
      }

      // Planets.
      if (root.sky) {
        // Brightest first, so Venus keeps its label next to Mercury.
        var order = ["ven", "jup", "mar", "sat", "mer", "ura", "nep"]
        for (var pk = 0; pk < order.length; pk++) {
          var pl = Model.planetRaDec(root.sky.planets, order[pk], root.t)
          var hp = Model.horizontal(pl.ra, pl.dec, root.t, root.lat, root.lon)
          var pp = at(hp.altitude, hp.azimuth)
          if (!pp) continue
          var dim = order[pk] === "ura" || order[pk] === "nep"
          var vis = dim ? starsShown : Math.max(starsShown, order[pk] === "ven" ? 0.9 : 0.4)
          ctx.fillStyle = root.css(root.accent, vis)
          ctx.beginPath(); ctx.arc(pp[0], pp[1], dim ? 2 : 3.5, 0, 2 * Math.PI); ctx.fill()
          ctx.font = font(12); ctx.fillStyle = root.css(root.accent, vis)
          var pw = ctx.measureText(root.sky.planets[order[pk]].name).width
          if (room(pp[0] + 7 + pw / 2, pp[1], pw)) ctx.fillText(root.sky.planets[order[pk]].name, pp[0] + 7, pp[1] + 4)
        }
      }

      // The moon, in its phase (mirrored south of the equator).
      var pm = at(root.moon.altitude, root.moon.azimuth)
      if (pm) {
        var r = 11, side = (root.phase.waxing ? 1 : -1) * (root.lat < 0 ? -1 : 1), e = 1 - 2 * root.phase.illumination
        ctx.fillStyle = root.css(root.fg, 0.18)
        ctx.beginPath(); ctx.arc(pm[0], pm[1], r, 0, 2 * Math.PI); ctx.fill()
        ctx.fillStyle = root.css(root.fg, 0.95)
        ctx.beginPath()
        for (var a = 0; a <= 32; a++) { var th = -Math.PI / 2 + Math.PI * a / 32; ctx.lineTo(pm[0] + side * r * Math.cos(th), pm[1] + r * Math.sin(th)) }
        for (var b = 0; b <= 32; b++) { var tb = Math.PI / 2 - Math.PI * b / 32; ctx.lineTo(pm[0] + side * e * r * Math.cos(tb), pm[1] + r * Math.sin(tb)) }
        ctx.closePath(); ctx.fill()
        ctx.font = font(12); ctx.fillStyle = root.css(root.fg, 0.8)
        ctx.fillText("Moon", pm[0] + 15, pm[1] + 4)
      }
      // The sun, with a glow.
      var pz = at(root.sun.altitude, root.sun.azimuth)
      if (pz) {
        ctx.fillStyle = root.css(root.accent, 0.25)
        ctx.beginPath(); ctx.arc(pz[0], pz[1], 26, 0, 2 * Math.PI); ctx.fill()
        ctx.fillStyle = root.css(root.accent, 1)
        ctx.beginPath(); ctx.arc(pz[0], pz[1], 12, 0, 2 * Math.PI); ctx.fill()
      }

      // The rim: compass points (east on the left) and the qibla.
      ctx.textAlign = "center"; ctx.font = font(15)
      var points = [["N", 0], ["E", 90], ["S", 180], ["W", 270]]
      for (var cp = 0; cp < points.length; cp++) {
        var q = at(0, points[cp][1], true), dx = q[0] - cx, dy = q[1] - cy, n = Math.sqrt(dx * dx + dy * dy)
        ctx.fillStyle = root.css(root.fg, 0.8)
        ctx.fillText(points[cp][0], cx + dx / n * (R + 22), cy + dy / n * (R + 22) + 5)
      }
      if (root.qibla) {
        var qb = at(0, root.qibla.bearing, true), qx = qb[0] - cx, qy = qb[1] - cy, qn = Math.sqrt(qx * qx + qy * qy)
        ctx.save(); ctx.translate(cx + qx / qn * R, cy + qy / qn * R); ctx.rotate(Math.PI / 4)
        ctx.fillStyle = root.css(root.fg, 1); ctx.fillRect(-6, -6, 12, 12); ctx.restore()
        ctx.fillStyle = root.css(root.fg, 0.9); ctx.font = font(13)
        ctx.fillText("Qibla " + Math.round(root.qibla.bearing) + "°", cx + qx / qn * (R + 58), cy + qy / qn * (R + 58) + 4)
      }
    }
  }

  // Where and when.
  Column {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.margins: 28
    spacing: 4
    Text {
      text: root.location ? "The sky over " + root.location.name : ""
      color: root.fg
      font.family: root.family
      font.pixelSize: 22
      font.bold: true
    }
    Text {
      text: Model.dateText(root.t, root.zone) + "  ·  " + Model.hhmm(root.t, root.zone)
        + (Math.abs(root.offset) < 60000 ? "  ·  now" : root.playing ? "  ·  playing" : "")
      color: Math.abs(root.offset) < 60000 ? root.fg : root.accent
      font.family: root.family
      font.pixelSize: 15
    }
    Text {
      text: !root.sun ? "" : root.sun.altitude > 0 ? "The sun is " + Math.round(root.sun.altitude) + "° up; the stars wait for dusk."
        : root.sun.altitude > -12 ? "Twilight: the sun is " + Math.round(-root.sun.altitude) + "° below the horizon."
        : "Night."
      color: Util.alpha(root.fg, 0.6)
      font.family: root.family
      font.pixelSize: 13
    }
  }
  Text {
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottomMargin: 18
    text: "←/→ 10 minutes  ·  shift: an hour  ·  ↑/↓ a day  ·  space: play  ·  t: now  ·  esc: close      Lying on your back, facing north: east is on the left."
    color: Util.alpha(root.fg, 0.5)
    font.family: root.family
    font.pixelSize: 12
  }
}
