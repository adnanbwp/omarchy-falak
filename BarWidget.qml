import QtQuick
import qs.Commons
import qs.Ui

// The pill: the next prayer and how long until it. Everything else lives in
// Panel.qml, which also owns the clock and the sums (the weather widget's shape).
BarWidget {
  id: root
  moduleName: "adnanbwp.falak"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function open() { if (panelLoader.item) panelLoader.item.openFromHotkey() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("FalakPanel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: panelLoader.item ? (root.vertical ? panelLoader.item.glyph : panelLoader.item.label) : ""
    active: panelLoader.item ? panelLoader.item.inPrayerWindow : false
    activeColor: Color.accent
    tooltipText: ""
    Accessible.role: Accessible.Button
    Accessible.name: "Falak: " + text.replace(/^\S+ /, "")
    onPressed: function(b) { if (panelLoader.item) panelLoader.item.toggle() }
  }
}
