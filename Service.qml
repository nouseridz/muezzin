import QtQuick
import Quickshell
import Quickshell.Io
import "bin/MuezzinBridge.js" as Bridge

// Muezzin service: headless singleton.
// - Polls muezzin_core.py every 30s for the next prayer, emits timingsChanged().
// - Watches every 20s for exact prayer times; fires notify-send + Adhan playback.
Item {
  id: root

  property var shell: null
  signal timingsChanged(var timings, string nextName, int nextEpoch)

  property var cfg: ({})
  property var todayTimings: ({})

  readonly property string corePath: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/io.github.aadaz.muezzin/bin/muezzin_core.py"

  // --- boot: load cached status, then config ---
  Process {
    id: bootStatus
    command: [root.corePath, "status"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        if (bootStatus.exitCode === 0 && text.trim() !== "") {
          try {
            var obj = JSON.parse(text)
            if (!obj.error) root.todayTimings = obj.timings || {}
          } catch (e) { console.warn("muezzin: status json", e) }
        }
        bootConfig.running = true
      }
    }
  }

  Process {
    id: bootConfig
    command: [root.corePath, "show"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        if (bootConfig.exitCode === 0 && text.trim() !== "") {
          try { root.cfg = JSON.parse(text) } catch (e) {}
        }
        tick.start()
        prayerWatcher.start()
      }
    }
  }

  Timer {
    id: tick
    interval: 30000
    repeat: true
    triggeredOnStart: false
    onTriggered: nextProc.running = true
  }

  Timer {
    id: prayerWatcher
    interval: 20000
    repeat: true
    triggeredOnStart: false
    onTriggered: checkPrayerTime()
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
          if (n.error) return
          root.timingsChanged(root.todayTimings, n.name || "", n.epoch || 0)
        } catch (e) {}
      }
    }
  }

  property var firedToday: ({_day: ""})
  property var remindedToday: ({_day: ""})

  function checkPrayerTime() {
    if (!cfg || !cfg.enabled_prayers || !todayTimings) return
    var nowSec = Math.floor(Date.now() / 1000)
    var key = Bridge.dayKey(new Date())
    if (firedToday._day !== key) { firedToday = {_day: key}; remindedToday = {_day: key} }

    for (var i = 0; i < Bridge.PRAYERS.length; i++) {
      var p = Bridge.PRAYERS[i]
      if (cfg.enabled_prayers[p] === false) continue
      var hhmm = todayTimings[p]
      if (!hhmm) continue
      var epoch = Bridge.prayerEpoch(new Date(), hhmm)

      var lead = Number(cfg.reminder_minutes_before || 0) * 60
      if (lead > 0 && !remindedToday[p] && nowSec >= epoch - lead && nowSec < epoch) {
        if (cfg.notifications_enabled !== false) {
          notifyProc.command = Bridge.notifyCommand(
            "🕌 " + p + " coming up",
            p + " is in " + (cfg.reminder_minutes_before || 0) + " minutes.")
          notifyProc.running = true
        }
        remindedToday[p] = true
      }

      if (!firedToday[p]) {
        if (nowSec >= epoch && nowSec < epoch + 60) {
          if (cfg.notifications_enabled !== false) {
            notifyProc.command = Bridge.notifyCommand(
              "🕌 " + p + " prayer time", "It's time for " + p + " prayer.")
            notifyProc.running = true
          }
          playAdhan(p)
          firedToday[p] = true
        } else if (nowSec >= epoch + 60) {
          firedToday[p] = true
        }
      }
    }
  }

  function playAdhan(prayer) {
    if (!cfg || !cfg.athan || cfg.athan.enabled === false) return
    var per = cfg.athan.per_prayer ? cfg.athan.per_prayer[prayer] : null
    if (per && per.enabled === false) return
    var voiceName = (per && per.voice) || cfg.athan.default_voice || "Doha (default)"
    var voices = cfg.athan.voices || []
    var dir = ""
    for (var i = 0; i < voices.length; i++) {
      if (voices[i].name === voiceName) { dir = voices[i].path; break }
    }
    if (!dir) dir = Quickshell.env("HOME") + "/.local/share/muezzin/sounds"
    dir = String(dir).replace(/^~/, Quickshell.env("HOME"))
    soundProc.command = ["mpv", "--no-video", "--volume=" + (Number(cfg.athan.volume) || 70),
                         dir + "/" + prayer + ".mp3"]
    soundProc.running = true
  }

  // Reusable detached playback process; silent, never blocks the timers.
  Process {
    id: soundProc
    command: []
    running: false
    stdout: StdioCollector { onStreamFinished: {} }
  }

  // Reusable notification process (notify-send).
  Process {
    id: notifyProc
    command: []
    running: false
    stdout: StdioCollector { onStreamFinished: {} }
  }

  Component.onCompleted: {
    // boot process chain starts itself via `running: true`
  }
}
