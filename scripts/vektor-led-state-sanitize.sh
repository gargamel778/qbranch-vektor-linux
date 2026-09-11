#!/bin/bash
# Strip empty-value lines from the Armbian LED state file.
#
# The kernel "pattern" trigger exposes both "pattern" (software, ms) and
# "hr_pattern" (hrtimer, us). pattern_trig_show_patterns() prints nothing for
# whichever kind is not currently stored, so on a software pattern hr_pattern
# reads back empty. armbian-led-state-save.sh dumps every writable attribute
# unfiltered and emits "hr_pattern="; armbian-led-state-restore.sh then treats
# any empty value as a syntax error and exits 1, so the unit fails at boot.
#
# This runs as ExecStartPre from a drop-in under /etc, so it survives an
# armbian-bsp-cli upgrade reverting the fix in the packaged save script.
set -u
F="${1:-/etc/armbian-leds.conf}"
[ -f "$F" ] || exit 0
n=$(grep -cE "^[A-Za-z_][A-Za-z0-9_-]*=$" "$F" || true)
if [ "${n:-0}" -gt 0 ]; then
    sed -i -E "/^[A-Za-z_][A-Za-z0-9_-]*=\$/d" "$F"
    echo "vektor: dropped $n empty-value line(s) from $F"
fi
exit 0
