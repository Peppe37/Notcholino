#!/bin/bash
# Measures what Notcholino costs: memory, CPU, energy, thread count, disk and how often it spawns osascript.
# No sudo needed. Usage: scripts/benchmark.sh /path/to/Notcholino.app [seconds-per-scenario]
#
# Notcholino must not already be running. A calendar permission prompt may appear for a new build;
# the benchmark does not need it. Temperature and GPU per process need `sudo powermetrics`, see the README.
set -u
APP="${1:?usage: benchmark.sh /path/to/Notcholino.app [seconds]}"
SECS="${2:-30}"
BIN="$APP/Contents/MacOS/Notcholino"
HERE="$(cd "$(dirname "$0")" && pwd)"

if pgrep -x Notcholino >/dev/null; then echo "Quit Notcholino first."; exit 1; fi

# Mouse helper (compiled once)
HOVER="$(mktemp -d)/hover"
swiftc -O -o "$HOVER" "$HERE/hover.swift" 2>/dev/null

"$BIN" >/dev/null 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null' EXIT
sleep 8   # let it settle

measure() {  # label
  local label="$1" spawns=0 samples=0
  # 20 Hz scan for osascript children of the app while top samples the process
  top -l $((SECS + 1)) -s 1 -pid "$PID" -stats cpu,mem,threads,idlew,power > /tmp/nb_top.txt 2>/dev/null &
  local top_pid=$!
  local end=$((SECONDS + SECS))
  while [ $SECONDS -lt $end ]; do
    if pgrep -P "$PID" -x osascript >/dev/null; then spawns=$((spawns + 1)); fi
    samples=$((samples + 1)); sleep 0.05
  done
  wait $top_pid 2>/dev/null
  # top prints one data row per sample ("0.1  42M 8  83+  0.1"); the first row is since-launch, drop it
  local rows; rows=$(grep -E '^[0-9.]+ +[0-9]+[KMG]' /tmp/nb_top.txt | tail -n +2 | tr -d '+')
  local cpu thr idle pow
  cpu=$(echo "$rows" | awk '{s+=$1;n++} END{printf "%.2f", s/n}')
  thr=$(echo "$rows" | awk 'END{print $3}')
  # IDLEW is a running total of idle wakeups: report the rate over the window
  idle=$(echo "$rows" | awk 'NR==1{f=$4} {l=$4;n++} END{printf "%.1f", (l-f)/(n>1?n-1:1)}')
  pow=$(echo "$rows" | awk '{s+=$5;n++} END{printf "%.2f", s/n}')
  local fp; fp=$(footprint "$PID" 2>/dev/null | awk '/Footprint:/ {print $5, $6}' | head -1)
  local peak; peak=$(vmmap -summary "$PID" 2>/dev/null | awk -F: '/Physical footprint \(peak\)/ {gsub(/ /,"",$2); print $2}')
  printf "| %s | %s %% | %s | %s | %s | %s | %s | %s |\n" "$label" "$cpu" "$fp" "$peak" "$thr" "$idle" "$pow" "$spawns"
}

echo "Notcholino $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist") on $(sysctl -n machdep.cpu.brand_string), macOS $(sw_vers -productVersion), ${SECS}s per scenario"
echo
echo "| Scenario | CPU (avg) | Memory footprint | Peak footprint | Threads | Idle wakeups/s | Energy impact | osascript runs seen |"
echo "| --- | --- | --- | --- | --- | --- | --- | --- |"
"$HOVER" out; sleep 2
measure "Idle (notch closed)"
"$HOVER" in
measure "Opening (first ${SECS}s after hover)"
measure "Open (settled)"
"$HOVER" out
echo
echo "App bundle: $(du -sh "$APP" | awk '{print $1}')"
