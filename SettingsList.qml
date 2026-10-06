import QtQuick
import qs.Commons

// A keyboard-and-mouse list of settings: one row each, choices as chips (or
// ‹ name › for long lists), actions as buttons. ↑/↓ moves, ←/→ changes, Enter
// runs a row's first action, Esc closes. The owner keeps the values.
//
//   rows: [{ field, label, options: [[value, "Label"], ...], cycle, hint, actions: [["Label", id], ...] }]
Column {
  id: root

  property var rows: []
  property var valueOf: function(field) { return undefined }
  property var dimmed: function(index) { return false }
  // Extra keys for the owner (e.g. space to preview a sound): return true if handled.
  property var extraKey: function(event, row) { return false }
  property int current: 0
  property string family: Style.font.family
  property color fg: Color.popups.text
  property color dim: Util.alpha(fg, 0.55)
  property color faint: Util.alpha(fg, 0.14)
  property color accent: Color.accent

  signal picked(string field, var value)
  signal actionRun(string field, var id)
  signal closed()

  spacing: Style.space(4)

  // Values come back from saved JSON, so compare as text (250 and "250" agree).
  function same(a, b) { return String(a) === String(b) }

  function step(dir) {
    var row = rows[current]
    if (!row || !row.options) return
    var cur = valueOf(row.field), i = 0
    for (var k = 0; k < row.options.length; k++) if (root.same(row.options[k][0], cur)) i = k
    picked(row.field, row.options[(i + dir + row.options.length) % row.options.length][0])
  }
  function takeKeys() { keyTarget.forceActiveFocus() }

  Item {
    id: keyTarget
    width: 1; height: 1
    Keys.onPressed: function(event) {
      var k = event.key, t = event.text, row = root.rows[root.current]
      if (root.extraKey(event, row)) { event.accepted = true; return }
      if (k === Qt.Key_Escape) root.closed()
      else if (k === Qt.Key_Up || t === "k") root.current = Math.max(0, root.current - 1)
      else if (k === Qt.Key_Down || t === "j") root.current = Math.min(root.rows.length - 1, root.current + 1)
      else if (k === Qt.Key_Left || t === "h") root.step(-1)
      else if (k === Qt.Key_Right || t === "l") root.step(1)
      else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && row && row.actions) root.actionRun(row.field, row.actions[0][1])
      else return
      event.accepted = true
    }
  }

  Repeater {
    model: root.rows
    Rectangle {
      id: rowItem
      required property var modelData
      required property int index
      readonly property bool isCurrent: index === root.current
      width: root.width
      height: Style.space(30)
      radius: Style.cornerRadius
      color: isCurrent ? Style.hoverFillFor(root.fg, root.accent) : "transparent"
      opacity: root.dimmed(index) ? 0.45 : 1
      MouseArea { anchors.fill: parent; onClicked: { root.current = rowItem.index; root.takeKeys() } }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        text: rowItem.modelData.label
        color: rowItem.isCurrent ? root.accent : root.fg
        font.family: root.family
        font.pixelSize: Style.font.body
      }
      Row {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)
        // Chips.
        Repeater {
          model: rowItem.modelData.options && !rowItem.modelData.cycle ? rowItem.modelData.options : []
          Rectangle {
            required property var modelData
            readonly property bool on: root.same(root.valueOf(rowItem.modelData.field), modelData[0])
            width: chip.implicitWidth + Style.space(14)
            height: chip.implicitHeight + Style.space(6)
            radius: height / 2
            color: on ? Util.alpha(root.accent, 0.18) : "transparent"
            border.width: 1
            border.color: on ? root.accent : root.faint
            Text { id: chip; anchors.centerIn: parent; text: modelData[1]; color: parent.on ? root.accent : root.dim; font.family: root.family; font.pixelSize: Style.font.caption }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.current = rowItem.index; root.picked(rowItem.modelData.field, modelData[0]); root.takeKeys() } }
          }
        }
        // ‹ name ›.
        Text {
          visible: !!rowItem.modelData.cycle
          text: {
            if (!rowItem.modelData.cycle) return ""
            var v = root.valueOf(rowItem.modelData.field), name = v
            for (var i = 0; i < rowItem.modelData.options.length; i++) if (root.same(rowItem.modelData.options[i][0], v)) name = rowItem.modelData.options[i][1]
            return "‹  " + name + "  ›" + (rowItem.isCurrent && rowItem.modelData.hint ? "   " + rowItem.modelData.hint : "")
          }
          color: root.accent
          font.family: root.family
          font.pixelSize: Style.font.bodySmall
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.current = rowItem.index; root.step(1); root.takeKeys() } }
        }
        // Buttons.
        Repeater {
          model: rowItem.modelData.actions || []
          Rectangle {
            required property var modelData
            width: act.implicitWidth + Style.space(14)
            height: act.implicitHeight + Style.space(6)
            radius: height / 2
            color: "transparent"
            border.width: 1
            border.color: root.accent
            Text { id: act; anchors.centerIn: parent; text: modelData[0]; color: root.accent; font.family: root.family; font.pixelSize: Style.font.caption }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.current = rowItem.index; root.actionRun(rowItem.modelData.field, modelData[1]); root.takeKeys() } }
          }
        }
      }
    }
  }
}
