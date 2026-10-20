#!/bin/bash
# The preview video, second version: Espresso, Notchy answering about the weather in Milan, and Snap. Everything on screen is
# made up (the answer, the song, the windows) so no one's data, key or voice is in it. Start your screen recorder, then run this.
#
#   scripts/demo/play-v2.sh run [N]  THE ONE TO USE: start your screen recorder, run this, and after a countdown of N seconds (10 by
#                                    default) it does everything: the stage and the demo app come up, the scene plays (about a
#                                    minute), and it all goes away and your own Notcholino comes back. Don't touch the Mac.
#
# The stage covers the whole screen, Terminal included. So never run `up` by hand from a Terminal that the cover will hide; if
# anything goes wrong, press ⌃⌥⌘Q (or wait ten minutes) and it all stops by itself and your Notcholino comes back.
#
#   scripts/demo/play-v2.sh up       the first part of `run`: quits your Notcholino and starts the stage and the demo copy of the app
#   scripts/demo/play-v2.sh play     the middle part: plays the scene
#   scripts/demo/play-v2.sh down     the last part: stops the demo and starts your own Notcholino again
#
# It needs the helpers in /tmp (stage, mouse, demowin: build them with `scripts/demo/build.sh`) and a demo copy of the app in
# /tmp/demo (see build.sh). The demo Notchy is a debug build that listens for the answer the stage sends it.
set -u
CMD=/tmp/stage-cmd.txt
say() { echo "$1" >> "$CMD"; }
caption() { say "caption: $1"; }
m() { /tmp/mouse "$@"; }

case "${1:-}" in
  run)
    n="${2:-10}"
    echo "Start the screen recording now. The scene begins in $n seconds and covers the screen: don't touch the Mac."
    echo "If something goes wrong, press Control-Option-Command-Q: everything stops and your Notcholino comes back."
    for i in $(seq "$n" -1 1); do printf '%s ' "$i"; sleep 1; done; echo
    "$0" up
    "$0" play
    sleep 1
    "$0" down ;;
  up)
    pkill -x Notcholino 2>/dev/null; pkill -f mediaremote-adapter.pl 2>/dev/null; sleep 1
    ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
    /tmp/stage "$ROOT/docs/assets/shots/control-center.png" >/dev/null 2>&1 &
    sleep 1
    # A throwaway copy of the app: its own plugins and extensions, a made-up song, no calendar, and settings given on the command line
    # (so nothing of yours is written). Notchy is a debug build that plays the answer the stage sends it.
    NOTCHOLINO_NOW_PLAYING_SCRIPT="$ROOT/scripts/demo/fake_now_playing.pl" NOTCHOLINO_EXTENSIONS_DIR=/tmp/demo/ext NOTCHOLINO_PLUGINS_DIR=/tmp/demo/plugins \
      /tmp/demo/Notcholino.app/Contents/MacOS/Notcholino -extensionsDeveloperMode YES -extensionsEnabled "(notchy,snap)" \
      -notchyChoices '{text = anthropic; vision = anthropic; speech = openai;}' -selectedCalendarIDs '()' \
      -pluginOrder "(espresso,tomato,hotter,pinger,clippy,picker,devices,quicky)" -updateCheckEnabled NO >/tmp/demo/app.log 2>&1 &
    sleep 7; echo "the stage and the demo app are up" ;;
  down)
    echo quit >> "$CMD"; sleep 1
    pkill -x stage; pkill -x demowin; pkill -f /tmp/demo/Notcholino.app; pkill -f mediaremote-adapter.pl; sleep 1
    open /Applications/Notcholino.app
    echo "everything is back as it was" ;;
  play)
    sleep 2
    caption "Notcholino turns your notch into a hub"
    sleep 3.5
    # Now Playing
    m move 756 6 0.6; sleep 0.3; m move 756 42 0.4
    caption "Now Playing, right where you look"
    sleep 3.2
    # Control Center, and Espresso
    m move 732 38 0.5; m click; sleep 0.9
    caption "Plugins live in the Control Center"
    sleep 1.8
    m move 618 112 0.6; m click; sleep 1.0
    caption "Espresso keeps your Mac awake"
    sleep 1.2
    m move 890 110 0.6; m click; sleep 3.2
    m move 756 430 1.0
    caption ""
    sleep 2.0
    # Notchy
    caption "Notchy, your AI companion"
    sleep 1.5
    say "voice: Hey Notchy, what's the weather like in Milan tomorrow?"
    sleep 3.8
    say "notchy: 1.8|Milan tomorrow: mostly cloudy, 12–19 °C, a 30% chance of light rain. A light jacket will do."
    sleep 11.0
    say "voice: hide"
    caption ""
    sleep 1.5
    # Snap
    /tmp/demowin >/dev/null 2>&1 &
    sleep 1.5
    caption "Snap: drop a window on the notch"
    sleep 1.8
    m drag 330 454 663 146 1.3 1.0
    sleep 1.8
    m drag 900 484 849 146 1.3 1.0
    sleep 2.5
    caption ""
    # The end: the windows go, the card comes
    pkill -x demowin
    sleep 0.8
    say "end: show"
    sleep 4.5
    say "end: hide"
    ;;
  *) echo "usage: $0 up | play | down" ;;
esac
