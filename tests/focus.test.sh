#!/usr/bin/env bash
# falak-focus with a stand-in bus and shell: pauses only what plays, turns on
# Do Not Disturb only if it was off, and restores exactly that.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
focus="$here/../falak-focus"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export PATH="$here/fixtures/bin:$PATH" XDG_RUNTIME_DIR="$work" FALAK_TEST_LOG="$work/log" FALAK_TEST_DIR="$work"
mkdir -p "$work/players"
fail() { echo "FAIL: $*" >&2; cat "$work/log" >&2 2>/dev/null; exit 1; }
echo Playing > "$work/players/org.mpris.MediaPlayer2.spotify"
echo Paused > "$work/players/org.mpris.MediaPlayer2.chromium.instance42"
echo off > "$work/dnd"

"$focus" begin 15
[[ $(cat "$work/dnd") == on ]] || fail "DND not turned on"
[[ $(cat "$work/players/org.mpris.MediaPlayer2.spotify") == Paused ]] || fail "spotify not paused"
grep -q '^player org.mpris.MediaPlayer2.spotify$' "$work/falak/focus" || fail "pause not recorded"
grep -q 'chromium' "$work/falak/focus" && fail "recorded a player that was not playing"

grep -q 'setsid -f sh -c .* 900 ' "$work/log" || fail "no restore timer for 15 minutes"
"$focus" check                                   # time not up: nothing changes
[[ $(cat "$work/dnd") == on ]] || fail "check restored early"

"$focus" end
[[ $(cat "$work/dnd") == off ]] || fail "DND not restored"
[[ $(cat "$work/players/org.mpris.MediaPlayer2.spotify") == Playing ]] || fail "spotify not resumed"
[[ $(cat "$work/players/org.mpris.MediaPlayer2.chromium.instance42") == Paused ]] || fail "touched a paused player"
[[ ! -f $work/falak/focus ]] || fail "marker left behind"

# DND already on before focus: focus must leave it on afterwards.
echo on > "$work/dnd"
"$focus" begin 10 && "$focus" end
[[ $(cat "$work/dnd") == on ]] || fail "turned off a DND the user had on"

# A restart after the time is up: check restores.
echo off > "$work/dnd"
"$focus" begin 10
sed -i 's/^until .*/until 1/' "$work/falak/focus"
"$focus" check
[[ $(cat "$work/dnd") == off ]] || fail "check did not restore after the time was up"
"$focus" begin 0 2>/dev/null && fail "accepted 0 minutes" || true
echo "falak focus: ok"
