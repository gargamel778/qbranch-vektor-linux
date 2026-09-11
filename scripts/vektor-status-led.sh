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
# Red is armed once with the kernel 'panic' trigger and then never touched, so
# it lights solid if the kernel dies -- which no userspace daemon could report.
set -u
IFACE="${IFACE:-end0}"
L=/sys/class/leds
B="$L/pca963x:blue"
G="$L/pca963x:green"
R="$L/pca963x:red"
BREATHE="${BREATHE:-8 1400 200 1400}"   # link up: dim <-> bright blue
FADE_MS="${FADE_MS:-800}"               # link down: half-cycle of the cross-fade
POLL="${POLL:-2}"

# What each channel's pattern should read back as. A channel parked on
# trigger=none has no 'pattern' attribute at all, so its expected value is "".
want_b=""
want_g=""

carrier(){ cat "/sys/class/net/$IFACE/carrier" 2>/dev/null || echo 0; }
rd(){ cat "$1/pattern" 2>/dev/null || true; }
plain(){ for d in "$B" "$G"; do echo none > "$d/trigger"; echo 0 > "$d/brightness"; done; }

link_up(){
    plain
    echo pattern > "$B/trigger"
    echo "$BREATHE" > "$B/pattern"
    echo -1 > "$B/repeat"
    want_b="$BREATHE"; want_g=""
}

link_down(){
    plain
    echo pattern > "$B/trigger"; echo pattern > "$G/trigger"
    echo -1 > "$B/repeat";       echo -1 > "$G/repeat"
    # complementary ramps: as blue rises green falls, and vice versa
    echo "0 $FADE_MS 255 $FADE_MS" > "$B/pattern"
    echo "255 $FADE_MS 0 $FADE_MS" > "$G/pattern"
    want_b="0 $FADE_MS 255 $FADE_MS"; want_g="255 $FADE_MS 0 $FADE_MS"
}

# Hand red to the kernel. Nothing else here touches it, and arming it at start
# rather than relying on armbian-led-state restoring a saved trigger means it is
# armed on every boot regardless of how the last shutdown went.
arm_panic(){ echo panic > "$R/trigger" 2>/dev/null || true; }

cleanup(){ plain; exit 0; }
trap cleanup TERM INT

arm_panic

# Re-assert on drift, not just on carrier transitions: armbian-led-state's
# restore writes a saved pattern straight into sysfs and would otherwise leave
# the LED showing a stale state indefinitely, since the carrier never changed.
# Both channels are checked -- green can be stomped while blue still matches.
#
# If a write does not take (sysfs rejecting it, the LED class going away), stop
# re-asserting after MAX_MISS attempts instead of blanking and rewriting both
# channels twice a second forever. A carrier change clears the backoff.
MAX_MISS=3
state=""; miss=0; warned=0
while :; do
    if [ "$(carrier)" = "1" ]; then now=up; else now=down; fi

    drift=0
    [ "$(rd "$B")" = "$want_b" ] || drift=1
    [ "$(rd "$G")" = "$want_g" ] || drift=1

    if [ "$now" != "$state" ]; then miss=0; warned=0; fi

    if { [ "$now" != "$state" ] || [ "$drift" = 1 ]; } && [ "$miss" -lt "$MAX_MISS" ]; then
        if [ "$now" = "up" ]; then link_up; else link_down; fi
        state="$now"
        if [ "$(rd "$B")" = "$want_b" ] && [ "$(rd "$G")" = "$want_g" ]; then
            miss=0
        else
            miss=$((miss + 1))
            if [ "$miss" -ge "$MAX_MISS" ] && [ "$warned" = 0 ]; then
                echo "vektor-status-led: pattern writes are not taking, backing off" >&2
                warned=1
            fi
        fi
    fi
    sleep "$POLL"
done
