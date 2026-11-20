#!/usr/bin/env python3
"""muezzin_core.py — config + timings backend for the Muezzin Omarchy plugin.
Invoked by Service.qml / BarWidget.qml through Quickshell's Process, or by hand
from a terminal. No Quickshell/GTK dependency, so it is testable anywhere.

Commands:
  show                      print current config JSON
  status                    print { date, timings } cache, refetching if stale
  next                      print {"name": "...", "epoch": <unix>, "text": "..."}
  set city <City> <Country> update location and refetch
  set-method <id>           update calculation method and refetch
  set-madhab <hanafi|standard>
  set-reminder <minutes>
  set-volume <0-100>
  toggle-athan <on|off>     master Adhan switch
  toggle-athan-prayer <P> <on|off>
  toggle-notify <on|off>    master notification switch
  toggle-prayer <P> <on|off>  per-prayer notification switch
"""
import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import date, timedelta
from pathlib import Path

PRAYERS = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "muezzin"
CONFIG_FILE = CONFIG_DIR / "config.json"
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "muezzin"
TIMES_FILE = CACHE_DIR / "times.json"

# Bundle of Adhan recordings ships inside the plugin repo itself, so the plugin
# is fully self-contained: no separate ~/.local/share/muezzin/sounds install step.
PLUGIN_DIR = Path(__file__).resolve().parent.parent
DEFAULT_SOUNDS = str(PLUGIN_DIR / "sounds")


def default_config():
    return {
        "city": "Abuja",
        "country": "Nigeria",
        "method": 3,
        "asr_madhab": "standard",
        "reminder_minutes_before": 10,
        "notifications_enabled": True,
        "athan": {
            "enabled": True,
            "volume": 70,
            "default_voice": "Doha (default)",
            "voices": [{"name": "Doha (default)", "path": DEFAULT_SOUNDS}],
            "per_prayer": {p: {"voice": "Doha (default)", "enabled": True} for p in PRAYERS},
        },
        "enabled_prayers": {p: True for p in PRAYERS},
    }


def load_config():
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    if not CONFIG_FILE.exists():
        cfg = default_config()
        write_config(cfg)
        return cfg
    with open(CONFIG_FILE) as fh:
        cfg = json.load(fh)
    # backfill any missing keys so old installs keep working
    base = default_config()
    for key, val in base.items():
        cfg.setdefault(key, val)
    cfg["athan"].setdefault("per_prayer", base["athan"]["per_prayer"])
    for p in PRAYERS:
        cfg["athan"]["per_prayer"].setdefault(p, {"voice": "Doha (default)", "enabled": True})
    cfg.setdefault("enabled_prayers", base["enabled_prayers"])
    return cfg


def write_config(cfg):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    with open(CONFIG_FILE, "w") as fh:
        json.dump(cfg, fh, indent=2)


def fetch_timings(force=False):
    """Fetch today's timings from Aladhan; returns (date_iso, timings_dict)."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    today = date.today().isoformat()

    if not force and TIMES_FILE.exists():
        try:
            cached = json.loads(TIMES_FILE.read_text())
            if cached.get("date") == today and cached.get("timings"):
                return today, cached["timings"]
        except (json.JSONDecodeError, OSError):
            pass

    cfg = load_config()
    day_str = date.today().strftime("%d-%m-%Y")
    school = 0 if cfg["asr_madhab"] == "hanafi" else 1
    params = urllib.parse.urlencode({
        "city": cfg["city"],
        "country": cfg["country"],
        "method": int(cfg["method"]),
        "school": school,
    })
    url = f"https://api.aladhan.com/v1/timingsByCity/{day_str}?{params}"
    req = urllib.request.Request(url, headers={"User-Agent": "muezzin-omarchy-plugin/1.0"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        payload = json.load(resp)
    if payload.get("code") != 200:
        raise RuntimeError(f"Aladhan returned code {payload.get('code')}")

    raw = payload["data"]["timings"]
    timings = {}
    for key in PRAYERS:
        value = raw.get(key, "")
        timings[key] = value.split(" ")[0] if value else ""

    TIMES_FILE.write_text(json.dumps({"date": today, "timings": timings}))
    return today, timings


def next_prayer(timings):
    """Return (name, unix_epoch, humanized_remaining) for the next upcoming prayer."""
    import datetime
    import time

    now = time.time()
    today = date.today()
    candidates = []
    for p in PRAYERS:
        hhmm = timings.get(p, "")
        if not hhmm:
            continue
        h, m = [int(x) for x in hhmm.split(":")]
        # Use naive local datetime -> timestamp so it respects the machine's TZ/DST.
        dt = datetime.datetime(today.year, today.month, today.day, h, m)
        epoch = dt.timestamp()
        if epoch > now:
            candidates.append((epoch, p))
    if not candidates:
        return None, None, ""
    epoch, name = min(candidates)
    remaining = int(epoch - now)
    hh, rem = divmod(remaining, 3600)
    mm = rem // 60
    return name, int(epoch), f"{hh}h{mm}m"


def main(argv):
    cmd = argv[0] if argv else "show"

    if cmd == "show":
        print(json.dumps(load_config()))
        return 0

    if cmd == "status":
        try:
            day, timings = fetch_timings()
            print(json.dumps({"date": day, "timings": timings}))
        except Exception as exc:  # network down etc — report, don't crash the plugin
            print(json.dumps({"error": str(exc)}))
        return 0

    if cmd == "next":
        try:
            _, timings = fetch_timings()
            name, epoch, text = next_prayer(timings)
            print(json.dumps({"name": name, "epoch": epoch, "text": text}))
        except Exception as exc:
            print(json.dumps({"error": str(exc)}))
        return 0

    cfg = load_config()

    if cmd == "set" and len(argv) >= 4 and argv[1] == "city":
        cfg["city"] = argv[2]
        cfg["country"] = argv[3]
    elif cmd == "set-method":
        cfg["method"] = int(argv[1])
    elif cmd == "set-madhab":
        cfg["asr_madhab"] = argv[1] if argv[1] in ("hanafi", "standard") else "standard"
    elif cmd == "set-reminder":
        cfg["reminder_minutes_before"] = max(0, int(argv[1]))
    elif cmd == "set-volume":
        cfg["athan"]["volume"] = min(100, max(0, int(argv[1])))
    elif cmd == "toggle-athan":
        cfg["athan"]["enabled"] = argv[1] == "on"
    elif cmd == "toggle-athan-prayer":
        cfg["athan"]["per_prayer"].setdefault(argv[1], {"voice": cfg["athan"]["default_voice"], "enabled": True})
        cfg["athan"]["per_prayer"][argv[1]]["enabled"] = argv[2] == "on"
    elif cmd == "toggle-notify":
        cfg["notifications_enabled"] = argv[1] == "on"
    elif cmd == "toggle-prayer":
        cfg["enabled_prayers"][argv[1]] = argv[2] == "on"
    else:
        print(f"unknown command: {' '.join(argv)}", file=sys.stderr)
        return 1

    write_config(cfg)
    # location/method/madhab changes need a refetch; other toggles don't but it's harmless
    try:
        fetch_timings(force=cmd in ("set", "set-method", "set-madhab"))
    except Exception:
        pass
    print(json.dumps(cfg))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
