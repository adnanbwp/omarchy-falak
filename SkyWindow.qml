import QtQuick
import Quickshell
import Quickshell.Wayland

// The sky dome's full-screen layer: a separate file so dev/check-panel can
// swap it for a plain Item (there is no layer shell headless).
PanelWindow {
  id: root
  property bool shown: false
  property alias view: skyView
  visible: shown
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  WlrLayershell.namespace: "falak-sky"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  SkyView { id: skyView; anchors.fill: parent }
}
