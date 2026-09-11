#!/bin/bash
# Vektor thermal + cpufreq characterisation, in-case.
#   phase 1  idle settle
#   phase 2  load ramp 1->2->3->4 cores, to see frequency respond to load
#   phase 3  sustained 4-core load to thermal steady state
#   phase 4  cool-down
# Aborts the load immediately if the SoC reaches ABORT_C, well under the
# 105 C critical trip. There is no serial console on this board any more.
set -u
Z=/sys/class/thermal/thermal_zone0
C=/sys/class/thermal/cooling_device0
CD=/sys/devices/system/cpu/cpu0/cpufreq
LOG=${LOG:-/var/log/vektor-thermal.log}
ABORT_C=${ABORT_C:-95000}
SETTLE=${SETTLE:-180}
RAMP=${RAMP:-60}
SUSTAIN=${SUSTAIN:-600}
COOL=${COOL:-180}
mkdir -p "$(dirname "$LOG")"

pids=()
spawn(){ for i in $(seq 1 "$1"); do sh -c 'while :; do :; done' & pids+=($!); done; }
killall_load(){ for p in "${pids[@]:-}"; do kill "$p" 2>/dev/null; done; pids=(); }
trap 'killall_load; echo "aborted"; exit 1' INT TERM

hdr(){ printf "%-9s %-8s %6s %7s %7s %7s %7s %6s %5s %s\n" phase elapsed tempC cpu0 cpu1 cpu2 cpu3 maxkHz cool load; }
row(){
  local t; t=$(cat $Z/temp)
  if [ "$t" -ge "$ABORT_C" ]; then killall_load; echo "*** ABORT: $t mC >= $ABORT_C ***" | tee -a "$LOG"; exit 2; fi
  printf "%-9s %-8s %6s %7s %7s %7s %7s %6s %5s %s\n" \
    "$1" "${2}s" "$((t/1000))" \
    "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)" \
    "$(cat /sys/devices/system/cpu/cpu1/cpufreq/scaling_cur_freq 2>/dev/null || echo -)" \
    "$(cat /sys/devices/system/cpu/cpu2/cpufreq/scaling_cur_freq 2>/dev/null || echo -)" \
    "$(cat /sys/devices/system/cpu/cpu3/cpufreq/scaling_cur_freq 2>/dev/null || echo -)" \
    "$(cat $CD/scaling_max_freq)" "$(cat $C/cur_state)" "$(cut -d' ' -f1 /proc/loadavg)" | tee -a "$LOG"
}

{ echo "# vektor thermal test $(date -Is)"; echo "# in case; abort at ${ABORT_C} mC; trips: $(for i in 0 1 2 3 4 5; do printf "%s " "$(cat $Z/trip_point_${i}_temp 2>/dev/null)"; done)"; } > "$LOG"
hdr | tee -a "$LOG"

s=0; while [ $s -lt $SETTLE ]; do row idle $s; sleep 20; s=$((s+20)); done
for n in 1 2 3 4; do
  killall_load; spawn $n; e=0
  while [ $e -lt $RAMP ]; do row "load-${n}c" $e; sleep 15; e=$((e+15)); done
done
e=0; while [ $e -lt $SUSTAIN ]; do row sustain $e; sleep 20; e=$((e+20)); done
killall_load
e=0; while [ $e -lt $COOL ]; do row cool $e; sleep 20; e=$((e+20)); done
echo "# done $(date -Is)" | tee -a "$LOG"
echo "LOGFILE=$LOG"
