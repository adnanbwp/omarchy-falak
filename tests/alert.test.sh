#!/usr/bin/env bash
# falak-alert with stand-ins for the player, the notifier and the shell: nothing
# real is played or sent. Proves the once-only gate, the quiet rules and stop.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
alert="$here/../falak-alert"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export PATH="$here/fixtures/bin:$PATH" XDG_RUNTIME_DIR="$work" FALAK_TEST_LOG="$work/log"
sound="$work/adhan.ogg"; touch "$sound"
lines() { [[ -f $FALAK_TEST_LOG ]] && wc -l < "$FALAK_TEST_LOG" || echo 0; }
fail() { echo "FAIL: $*" >&2; cat "$FALAK_TEST_LOG" >&2 2>/dev/null; exit 1; }

"$alert" fire 2026-10-06-asr-start "Asr" "16:44" "$sound" 80
wait
grep -q 'notify .*Asr.*click to stop the adhan' "$FALAK_TEST_LOG" || fail "adhan notification"
grep -q "pw-play --volume 0.80 $sound" "$FALAK_TEST_LOG" || fail "player at 80%"

grep -q '^hook falak-prayer 2026-10-06-asr-start Asr 16:44$' "$FALAK_TEST_LOG" || fail "falak-prayer hook not run"
before=$(lines); "$alert" fire 2026-10-06-asr-start "Asr" "16:44" "$sound" 80; wait
[[ $(lines) == "$before" ]] || fail "second instance fired the same key"

# The du'a after the adhan: sent when the adhan plays to the end...
"$alert" fire 2026-10-06-dhuhr-start "Dhuhr" "13:08" "$sound" 80 "اللَّهُمَّ رَبَّ test-dua" "O Allah, test-head," "test-tail (Bukhari)"; wait
grep -q "notify .*Du'a after the adhan اللَّهُمَّ رَبَّ test-dua" "$FALAK_TEST_LOG" || fail "du'a after a full adhan"
grep -q "notify .*O Allah, test-head, test-tail (Bukhari)" "$FALAK_TEST_LOG" || fail "the du'a's English card"
# English first, so the Arabic (newer) stacks on top.
[[ $(grep -n "test-head\|test-dua" "$FALAK_TEST_LOG" | grep -o "test-head\|test-dua" | tr '\n' ' ') == "test-head test-dua " ]] || fail "du'a cards out of order"
# ...not when it was stopped, and not without the setting.
FALAK_TEST_PLAY_SECONDS=30 "$alert" fire 2026-10-06-dhuhr-stopped "Dhuhr" "13:08" "$sound" 80 "stopped-dua" &
for _ in $(seq 50); do [[ -f $work/falak/adhan.pid ]] && break; sleep 0.1; done
"$alert" stop; wait
grep -q "stopped-dua" "$FALAK_TEST_LOG" && fail "du'a after a stopped adhan"
"$alert" fire 2026-10-06-dhuhr-nodua "Dhuhr" "13:08" "$sound" 80; wait
[[ $(grep -c "Du'a after the adhan" "$FALAK_TEST_LOG") == 1 ]] || fail "du'a without the setting"

plays=$(grep -c pw-play "$FALAK_TEST_LOG")
FALAK_TEST_DND=on "$alert" fire 2026-10-06-maghrib-start "Maghrib" "19:29" "$sound" 80
grep -q 'notify .*Maghrib.*silent: Do Not Disturb is on' "$FALAK_TEST_LOG" || fail "DND notice"
[[ $(grep -c pw-play "$FALAK_TEST_LOG") == "$plays" ]] || fail "played during DND"

FALAK_TEST_RECORDING=1 "$alert" fire 2026-10-06-isha-start "Isha" "20:53" "$sound" 80
grep -q 'silent: a screen recording is running' "$FALAK_TEST_LOG" || fail "recording notice"
[[ $(grep -c pw-play "$FALAK_TEST_LOG") == "$plays" ]] || fail "played while recording"

FALAK_TEST_PLAY_SECONDS=30 "$alert" fire 2026-10-07-fajr-start "Fajr" "05:18" "$sound" 50 &
for _ in $(seq 50); do [[ -f $work/falak/adhan.pid ]] && break; sleep 0.1; done
[[ -f $work/falak/adhan.pid ]] || fail "no pidfile while playing"
player=$(cat "$work/falak/adhan.pid")
"$alert" stop
sleep 0.8
kill -0 "$player" 2>/dev/null && fail "stop left the player running"
[[ ! -f $work/falak/adhan.pid ]] || fail "stop left the pidfile"
wait

# Reported: two tests seconds apart. The first one's cleanup must not
# delete the second's pidfile, and stop must still silence the second.
# Poll, never a fixed sleep: on a busy machine the second player starts late.
FALAK_TEST_PLAY_SECONDS=30 "$alert" fire test-1 "Falak test" "one" "$sound" 50 &
for _ in $(seq 50); do [[ -f $work/falak/adhan.pid ]] && break; sleep 0.1; done
first=$(cat "$work/falak/adhan.pid" 2>/dev/null || echo none)
FALAK_TEST_PLAY_SECONDS=30 "$alert" fire test-2 "Falak test" "two" "$sound" 50 &
second=none
for _ in $(seq 50); do s=$(cat "$work/falak/adhan.pid" 2>/dev/null || echo none); [[ $s != none && $s != "$first" ]] && { second=$s; break; }; sleep 0.1; done
[[ $second != none ]] || fail "the first test's cleanup deleted the second's pidfile"
"$alert" stop
for _ in $(seq 30); do pgrep -f "$here/fixtures/bin/pw-play" >/dev/null || break; sleep 0.1; done
pgrep -f "$here/fixtures/bin/pw-play" >/dev/null && fail "stop left a player running after two tests"
wait

# A pidfile naming something that isn't a player (a reused pid) is not killed.
mkdir -p "$work/falak"; sleep 30 & innocent=$!
echo "$innocent" > "$work/falak/adhan.pid"
"$alert" stop
sleep 0.3
kill -0 "$innocent" 2>/dev/null || fail "stop killed a non-player named in the pidfile"
kill "$innocent"; wait "$innocent" 2>/dev/null || true

# The backstop: a Falak adhan playing with no pidfile at all is still stopped.
mkdir -p "$work/adnanbwp.falak/assets/adhans"; touch "$work/adnanbwp.falak/assets/adhans/makkah.ogg"
# A process the kernel names pw-play (a symlink to tail, which keeps running).
mkdir -p "$work/real"; ln -s "$(command -v tail)" "$work/real/pw-play"
"$work/real/pw-play" -f "$work/adnanbwp.falak/assets/adhans/makkah.ogg" &
orphan=$!
rm -f "$work/falak/adhan.pid"
sleep 0.2
"$alert" stop
sleep 0.8
kill -0 "$orphan" 2>/dev/null && fail "stop missed an adhan with no pidfile"
wait
# ...but only players: a process that merely mentions such a path is left alone.
bash -c 'sleep 5' "$work/adnanbwp.falak/assets/adhans/makkah.ogg" &
bystander=$!
sleep 0.2
"$alert" stop
sleep 0.3
kill -0 "$bystander" 2>/dev/null || fail "stop killed a process that only mentioned an adhan path"
kill "$bystander"; wait "$bystander" 2>/dev/null || true

"$alert" fire 'bad key;rm' "x" "y" 2>/dev/null && fail "accepted a bad key" || true

# Preview: plays, at the given volume, without a notification.
n=$(grep -c notify "$FALAK_TEST_LOG")
"$alert" preview "$sound" 40
grep -q "pw-play --volume 0.40 $sound" "$FALAK_TEST_LOG" || fail "preview volume"
[[ $(grep -c notify "$FALAK_TEST_LOG") == "$n" ]] || fail "preview sent a notification"
echo "falak alert: ok"
