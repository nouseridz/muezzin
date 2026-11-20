import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Muezzin details panel: today's times + quick settings (Athan on/off,
// notifications on/off, reminder lead time, calculation method, location).
Panel {
  id: root
  moduleName: "io.github.aadaz.muezzin"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var timings: ({})
  property var cfg: ({})

  readonly property string corePath: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/io.github.aadaz.muezzin/bin/muezzin_core.py"

  function open() { root.controller.show() }
  function close() { root.controller.hide() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function refresh() {
    statusProc.running = true
    configProc.running = true
  }

  // --- data loads ---
  Process {
    id: statusProc
    command: [root.corePath, "status"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        if (statusProc.exitCode !== 0 || text.trim() === "") return
        try {
          var obj = JSON.parse(text)
          if (!obj.error) root.timings = obj.timings || {}
        } catch (e) {}
      }
    }
  }

  Process {
    id: configProc
    command: [root.corePath, "show"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        if (configProc.exitCode !== 0 || text.trim() === "") return
        try { root.cfg = JSON.parse(text) } catch (e) {}
      }
    }
  }

  // Generic setter: muezzin_core.py <args...>, then refresh both views.
  Process {
    id: setterProc
    command: []
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.refresh()
      }
    }
  }

  function runSetter(args) {
    setterProc.command = [root.corePath].concat(args)
    setterProc.running = true
  }

  // --- UI ---
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: parent.width
          text: "🕌 Muezzin"
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        Repeater {
          model: ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
          delegate: Row {
            width: parent.width
            spacing: Style.space(8)
            Text {
              width: 70
              text: modelData
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
            }
            Text {
              text: root.timings[modelData] || "--:--"
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
            }
          }
        }

        Item { width: 1; height: Style.space(4) }

        Text {
          width: parent.width
          text: "Adhan"
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.bold: true
        }

        Row {
          width: parent.width
          spacing: Style.space(8)
          Text {
            text: "Play Adhan"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
          }
          Switch {
            checked: root.cfg.athan ? root.cfg.athan.enabled !== false : true
            onToggled: runSetter(["toggle-athan", checked ? "on" : "off"])
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)
          Text {
            text: "Notifications"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
          }
          Switch {
            checked: root.cfg.notifications_enabled !== false
            onToggled: runSetter(["toggle-notify", checked ? "on" : "off"])
          }
        }

        Text {
          width: parent.width
          text: "Reminder: " + (root.cfg.reminder_minutes_before || 0) + " min before"
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
        }

        Row {
          width: parent.width
          spacing: Style.space(4)
          Button {
            text: "-"
            onClicked: runSetter(["set-reminder", String(Math.max(0, (root.cfg.reminder_minutes_before || 0) - 5))])
          }
          Button {
            text: "+"
            onClicked: runSetter(["set-reminder", String(Math.min(60, (root.cfg.reminder_minutes_before || 0) + 5))])
          }
        }

        Text {
          width: parent.width
          text: "Location: " + (root.cfg.city || "?") + ", " + (root.cfg.country || "?")
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
        }

        Text {
          width: parent.width
          text: "Method: " + String(root.cfg.method || 3)
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
        }

        Button {
          text: "Refresh times"
          onClicked: root.refresh()
        }
      }
    }
  }

  onOpenedChanged: if (root.opened) root.refresh()
}
