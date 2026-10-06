# Changelog

`omarchy plugin update` installs the latest `main`. The version numbers just label what changed.

## 2.1.0 (2026-10-06)

- The du'a after the adhan (Sahih al-Bukhari 614), in Arabic and English: two notifications (the Arabic on top, the English below, each within the card's line limit) when an adhan plays to the end (not when you stop it), and in the panel for each prayer's first ten minutes. "Du'a after the adhan" in the alert settings turns it off.

- Stop only stops a player: a pidfile naming any other process (a reused pid) is ignored, and the runtime files live only in the per-user `$XDG_RUNTIME_DIR`, never a shared `/tmp`.
- Do Not Disturb works with Falak: the adhan stays silent while it is on, and prayer focus turns it back off when it ends. Both read the state with `omarchy-shell -q`, which prints nothing, so neither ever saw it.

- Where on Earth each eclipse is seen: in `e`, pick one with ↑/↓ and a world map shows the partial zone by depth and the path of totality (or the annular ring) at its true width. For a lunar eclipse it shows where the moon is up.
- Solar eclipses are named by their own type, so a total eclipse seen elsewhere no longer reads "partial".
- The Moonsighting Committee method now uses its seasonal rule: Fajr and Isha are a number of minutes from sunrise and sunset that changes with latitude and season.
- A click anywhere in the panel gives the keyboard back to the open view. Before this, a view that lost focus ignored every key, Esc included.
- First public release. Plugin id `adnanbwp.falak`.

## 2.0.0

Methods for 26 authorities, adhan and reminders, the sky dome, eclipses, the hijri calendar, the crescent map, nine languages and the rest of what's listed in the README.
