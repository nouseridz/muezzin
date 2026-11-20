import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// Muezzin bar widget: shows "🕌 <Next> in <Xh Ym>" and opens Panel.qml on click.
BarWidget {
  id: root
  moduleName: "io.github.aadaz.muezzin"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  readonly property string corePath: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/io.github.aadaz.muezzin/bin/muezzin_core.py"

  property string nextText: "🕌 --:--"

  // Cheap self-contained poll; the service does the heavy notification/audio work.
  Timer {
    interval: 30000
    repeat: true
    triggeredOnStart: true
    onTriggered: nextProc.running = true
  }

  Process {
    id: nextProc
    command: [root.corePath, "next"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        if (nextProc.exitCode !== 0 || text.trim() === "") return
        try {
          var n = JSON.parse(text)
          if (!n.error && n.name) {
            nextText = "🕌 " + n.name + (n.text ? " in " + n.text : "")
          }
        } catch (e) {}
      }
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: nextText
    tooltipText: "Muezzin — prayer times"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }
}
