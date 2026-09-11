#!/bin/bash
# Boot-time sanity check for the Vektor's board-specific configuration.
# Fails loudly if a kernel, device-tree or package change silently undid something.
LOG=/data/logs/selfcheck.log
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

[ "$G" = "2" ] || { note "FAIL: radio power overlay not applied ($G/2 gpio lines claimed)"; fail=1; }
[ "$R" = "2" ] || { note "FAIL: only $R/2 radios enumerated"; fail=1; }
[ "$L" = "3" ] || { note "FAIL: RGB LED absent ($L/3 pca963x channels) - check the leds-pca963x DKMS module and the i2c1 overlay"; fail=1; }
{ [ "$K" = "$I" ] && [ "$K" = "$D" ]; } || { note "FAIL: boot set mismatched (kernel=$K initrd=$I dtb=$D)"; fail=1; }
[ "${N:-0}" -le 1 ] || { note "WARN: $N kernel branches installed - the initramfs hook will fight over /boot/uInitrd"; fail=1; }
findmnt -no TARGET /data >/dev/null 2>&1 || { note "WARN: /data not mounted"; fail=1; }

[ "$fail" = "0" ] && note "OK: radios ${R}/2, LED ${L}/3, gpio overlay ${G}/2, boot set consistent on $K"
exit $fail
