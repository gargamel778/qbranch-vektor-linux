#!/bin/bash
# Vektor front-panel RGB LED status daemon.
#
#   ethernet up    -> blue breathes slowly
#   ethernet down  -> blue and green cross-fade in antiphase, so the LED morphs
#                     blue -> cyan -> green -> cyan -> blue with no dark gap
#
# Both states are driven entirely by the kernel 'pattern' trigger, so this
# daemon does nothing but poll the carrier every few seconds. The two channels
# share a period and are started together, and measure as complementary to
# within sampling jitter (their brightnesses sum to 255 throughout).
#
# Red is deliberately never touched: it belongs to the kernel 'panic' trigger,
# so it lights solid if the kernel dies, which no userspace daemon could report.
set -u
IFACE="${IFACE:-end0}"
L=/sys/class/leds
B="$L/pca963x:blue"
G="$L/pca963x:green"
BREATHE="${BREATHE:-8 1400 200 1400}"   # link up: dim <-> bright blue
FADE_MS="${FADE_MS:-800}"               # link down: half-cycle of the cross-fade

carrier(){ cat "/sys/class/net/$IFACE/carrier" 2>/dev/null || echo 0; }
plain(){ for d in "$B" "$G"; do echo none > "$d/trigger"; echo 0 > "$d/brightness"; done; }

link_up(){
    plain
    echo pattern > "$B/trigger"
    echo "$BREATHE" > "$B/pattern"
    echo -1 > "$B/repeat"
}

link_down(){
    plain
    echo pattern > "$B/trigger"; echo pattern > "$G/trigger"
    echo -1 > "$B/repeat";       echo -1 > "$G/repeat"
    # complementary ramps: as blue rises green falls, and vice versa
    echo "0 $FADE_MS 255 $FADE_MS" > "$B/pattern"
    echo "255 $FADE_MS 0 $FADE_MS" > "$G/pattern"
}

cleanup(){ plain; exit 0; }
trap cleanup TERM INT

state=""
while :; do
    if [ "$(carrier)" = "1" ]; then
        [ "$state" = "up" ]   || { link_up;   state=up; }
    else
        [ "$state" = "down" ] || { link_down; state=down; }
    fi
    sleep 2
done
