// MuezzinBridge.js — shared helpers for Muezzin's QML files.
// Pure JS (no Quickshell imports) so it stays testable.

.pragma library

var PRAYERS = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

function pad(n) {
  return n < 10 ? "0" + n : "" + n
}

function humanRemaining(seconds) {
  var s = Math.max(0, seconds)
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  if (h > 0) return h + "h" + m + "m"
  return m + "m"
}

function dayKey(d) {
  var dt = d || new Date()
  return dt.getFullYear() + "-" + pad(dt.getMonth() + 1) + "-" + pad(dt.getDate())
}

function prayerEpoch(today, hhmm) {
  var parts = String(hhmm).split(":")
  var dt = new Date(today.getFullYear(), today.getMonth(), today.getDate(),
                    parseInt(parts[0], 10), parseInt(parts[1], 10), 0, 0)
  return Math.floor(dt.getTime() / 1000)
}

// Shell out for desktop notifications. Kept here (not in QML) so the exact
// command stays consistent between Service.qml and Panel.qml.
function notifyCommand(title, body) {
  return ["notify-send", "-u", "normal", title, body]
}
