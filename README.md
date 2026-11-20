# Muezzin — Omarchy Plugin

A prayer-time reminder widget for the [Omarchy](https://omarchy.org) desktop.
Shows the next prayer with a live countdown in the top bar, fires a desktop
notification and plays the **Adhan** at each prayer time, and opens a settings
panel on click.

Built as a native Omarchy/Quickshell plugin: `bar-widget` + headless `service`,
so it installs with `omarchy plugin add` and needs no manual Waybar config or
systemd unit.

## Features

- Live countdown in the bar: `🕌 Maghrib in 1h17m`
- Desktop notification at exact prayer time + optional heads-up reminder
- Adhan audio via `mpv`, 5 bundled per-prayer recordings (Public Domain)
- Settings panel from the bar icon: master Adhan switch, notifications switch,
  reminder lead time (+/- 5 min), location/method display, refresh button
- Fetches times from the free [Aladhan API](https://aladhan.com/prayer-times-api)
  (no key); caches daily; refetches at day rollover

## Requirements

Already present on a default Omarchy install (nothing to `pacman -S`):
`python3`, `jq`, `mpv`. Optional but expected on any desktop:
`notify-send` (libnotify).

## Install

```bash
omarchy plugin add https://github.com/AADaz/muezzin.git --enable
```

Or manually:

```bash
git clone https://github.com/AADaz/muezzin.git \
  ~/.config/omarchy/plugins/io.github.aadaz.muezzin
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.aadaz.muezzin
omarchy bar put io.github.aadaz.muezzin --section right
```

This repo also ships an `install.sh` that does the copy + validate + enable steps
for people who cloned it into a normal folder instead.

## Configure

Click the 🕌 widget → settings panel. Set city/country and calculation method
from a terminal if you want the full list (24 methods) rather than the panel's
quick controls:

```bash
~/.config/omarchy/plugins/io.github.aadaz.muezzin/bin/muezzin_core.py set city "Abuja" "Nigeria"
~/.config/omarchy/plugins/io.github.aadaz.muezzin/bin/muezzin_core.py set-method 3
```

Full CLI surface (config lives at `~/.config/muezzin/config.json`):

```
show | status | next
set city <City> <Country>
set-method <id>            # 1 Karachi, 2 ISNA, 3 MWL, 4 Umm al-Qura, 5 Egyptian, ...
set-madhab hanafi|standard
set-reminder <minutes>
set-volume <0-100>
toggle-athan on|off        toggle-notify on|off
toggle-athan-prayer <P> on|off
toggle-prayer <P> on|off
```

## Remove

```bash
omarchy plugin remove io.github.aadaz.muezzin
rm -rf ~/.config/muezzin ~/.cache/muezzin   # optional: drop saved settings/cache
```

## How it works

- `Service.qml` — headless singleton. Every 30s asks `bin/muezzin_core.py next`
  for the upcoming prayer and broadcasts it to the bar widget. Every 20s checks
  whether a prayer time has just passed; if so, runs `notify-send` and spawns
  `mpv` to play the Adhan for that prayer.
- `BarWidget.qml` — the bar item. Self-polls the same core command every 30s so
  its label is correct even before the service has broadcast anything; left-click
  toggles `Panel.qml`.
- `Panel.qml` — details popup: today's 5 times, Adhan/notifications switches,
  reminder +/- , location/method readouts, refresh.
- `bin/muezzin_core.py` — all config + Aladhan fetch logic, pure Python stdlib,
  invoked via Quickshell `Process`. Unit-testable without a display server.

## Security / privacy notes

- No sandboxing beyond what Omarchy gives every plugin: this code runs with your
  user privileges inside `omarchy-shell`, like any installed plugin.
- Network use is limited to a single HTTPS GET per day against
  `api.aladhan.com` (city/country/method are sent as query params; nothing else
  leaves the machine). No API key, no account.
- Adhan audio is bundled locally; playback uses `mpv`, which may phone home only
  if you've configured it to — by default it doesn't.

## License

MIT — see [LICENSE](LICENSE).

## Adhan audio credit

"Adhan Recordings from Doha, Qatar" (recorded 2013–2014), Public Domain Mark
1.0, via Internet Archive:
https://archive.org/details/adhan.recordings.from.doha.qatar
