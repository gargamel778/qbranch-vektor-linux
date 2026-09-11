#!/bin/bash
# Boot-time sanity check for the Vektor's board-specific configuration.
# Fails loudly if a kernel, device-tree or package change silently undid something.
LOG=${LOG:-/var/log/vektor-selfcheck.log}
mkdir -p "$(dirname "$LOG")" 2>/dev/null
fail=0
note(){ echo "$*"; echo "$(date -Is) $*" >> "$LOG" 2>/dev/null; }

G=$(grep -c "vektor-wifi-.g-vbus" /sys/kernel/debug/gpio 2>/dev/null)
R=$(ls /sys/bus/usb/devices/ 2>/dev/null | grep -cE "^[0-9]+-1$")
L=$(ls -1d /sys/class/leds/pca963x:* 2>/dev/null | wc -l)
K=$(readlink /boot/Image   | sed 's/^vmlinuz-//')
I=$(readlink /boot/uInitrd | sed 's/^uInitrd-//')
D=$(readlink /boot/dtb     | sed 's/^dtb-//')
N=$(dpkg -l 2>/dev/null | grep -cE "^ii +linux-image-[a-z]+-sunxi64")
F=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies 2>/dev/null | wc -w)
MAGIC=$(dd if=/dev/mtd0 bs=1 skip=4 count=8 status=none 2>/dev/null)
S=$(systemctl is-active armbian-led-state.service 2>/dev/null)
P=$(sed -n 's/.*\[\(.*\)\].*/\1/p' /sys/class/leds/pca963x:red/trigger 2>/dev/null)

[ "$G" = "2" ] || { note "FAIL: radio power overlay not applied ($G/2 gpio lines claimed)"; fail=1; }
[ "$R" = "2" ] || { note "FAIL: only $R/2 radios enumerated"; fail=1; }
[ "$L" = "3" ] || { note "FAIL: RGB LED absent ($L/3 pca963x channels) - check the leds-pca963x DKMS module and the i2c1 overlay"; fail=1; }
[ -e /sys/bus/i2c/devices/1-0050/eeprom ] || { note "FAIL: EEPROM not bound - check the at24 DKMS module and the eeprom overlay"; fail=1; }
[ "${F:-0}" -ge 2 ] || { note "FAIL: CPU scaling unavailable ($F operating points) - check the cpufreq overlay"; fail=1; }
[ "$S" = "active" ] || { note "FAIL: armbian-led-state is ${S:-absent} - its save script emits an empty hr_pattern= for pattern-trigger LEDs and the restore rejects it; check the sanitize drop-in"; fail=1; }
[ "$P" = "panic" ] || { note "FAIL: red LED trigger is '${P:-none}', not panic - a kernel panic would go unsignalled"; fail=1; }
[ "$MAGIC" = "eGON.BT0" ] || { note "WARN: SPI NOR has no valid bootloader header - the third boot path is gone"; fail=1; }
{ [ "$K" = "$I" ] && [ "$K" = "$D" ]; } || { note "FAIL: boot set mismatched (kernel=$K initrd=$I dtb=$D)"; fail=1; }
[ "${N:-0}" -le 1 ] || { note "WARN: $N kernel branches installed - the initramfs hook will fight over /boot/uInitrd"; fail=1; }

[ "$fail" = "0" ] && note "OK: radios ${R}/2, LED ${L}/3, gpio ${G}/2, eeprom bound, ${F} cpu freqs, SPI fallback present, led-state active, red armed, boot set consistent on $K"
exit $fail
