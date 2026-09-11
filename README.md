# Q-Branch Labs Vektor → mainline Linux

Running current Armbian on a **Q-Branch Labs "Vektor"**, including **both soldered Wi-Fi radios**,
which no mainline kernel drives out of the box.

If you found one of these in a drawer and flipped it over, the label reads **FCC ID `2ASZI-VK02A`**,
model `VK02A`. It was a subscription VPN/privacy appliance. Q-Branch Labs, Inc. was compulsorily
struck off in January 2025, so the service is gone and there was never a final firmware release.

**The hardware is fine, and it is not exotic.** It is a private re-layout of the FriendlyELEC
**NanoPi K1 Plus**, and it shipped running Armbian from the factory. Putting your own Linux on it is a
re-install, not a port.

---

## The short version

Write a current Armbian **NanoPi K1 Plus** image to a microSD, and it boots. Ethernet, eMMC, SPI NOR,
USB and serial all work immediately.

**The two Wi-Fi radios will not.** They enumerate, then vanish from the USB bus at a random point
between roughly 4 and 12 minutes, leaving nothing in `dmesg` but:

```
usb 3-1: USB disconnect, device number 2
usb 4-1: USB disconnect, device number 2
```

The cause is two GPIOs. **PA7 and PA8 are the radios' power enables.** The vendor's 4.19 kernel claims
them and drives them high; no mainline kernel does, because a real NanoPi K1 Plus has no soldered
radios and its device tree has no reason to mention those pins. Left undriven they float, and the
modules eventually lose power.

The fix is a device-tree overlay: [`overlays/sun50i-h5-vektor-radio-vbus.dts`](overlays/sun50i-h5-vektor-radio-vbus.dts).

| Pin | Vendor's GPIO label | Module | Controller | PHY |
|---|---|---|---|---|
| PA8 | `BL-7601` | MediaTek MT7601U `148f:7601` | `1c1c000.usb` | 2 |
| PA7 | `BL-M7612` | Realtek RTL8812BU `0bda:b812` | `1c1d000.usb` | 3 |

`BL-M7612` is a leftover: the slot was designed for a MediaTek MT7612 and shipped with a Realtek part.

---

## Install the fix

On a running Armbian:

```bash
sudo apt install device-tree-compiler
dtc -@ -I dts -O dtb -o sun50i-h5-vektor-radio-vbus.dtbo overlays/sun50i-h5-vektor-radio-vbus.dts
sudo mkdir -p /boot/overlay-user
sudo cp sun50i-h5-vektor-radio-vbus.dtbo /boot/overlay-user/
echo 'user_overlays=sun50i-h5-vektor-radio-vbus' | sudo tee -a /boot/armbianEnv.txt
sudo reboot
```

Confirm it took:

```
$ grep -i vektor /sys/kernel/debug/gpio
 gpio-7   (vektor-wifi-5g-vbus ) out hi
 gpio-8   (vektor-wifi-2g-vbus ) out hi

$ lsusb | grep -E '148f|0bda'
Bus 003 Device 002: ID 148f:7601 Ralink Technology, Corp. MT7601U Wireless Adapter
Bus 004 Device 002: ID 0bda:b812 Realtek Semiconductor Corp. RTL8812BU
```

Both radios should now stay put indefinitely. Verified on 6.18.44; the fix is in the device tree, so
kernel version does not matter.

### If you cannot use an overlay

[`scripts/radio-power.py`](scripts/radio-power.py) drives the same two pins from userspace via
`/dev/mem` (needs `iomem=relaxed` on the kernel command line). Useful for confirming the diagnosis in
thirty seconds before you commit to anything: run it and watch `lsusb`.

[`overlays/sun50i-h5-vektor-radio-power.dts`](overlays/sun50i-h5-vektor-radio-power.dts) is the same
fix as a `gpio-hog`. It works, but `regulator-fixed` wired to `&usbphy` is the mainline sunxi idiom
(`gpio-hog` appears zero times in all 293 Allwinner device tree files), so prefer the vbus overlay.

---

## The front-panel RGB LED

Same shape of problem as the radios, different bus. The LED is **not on a GPIO**. It is an
**NXP PCA9633** four-channel I2C PWM driver at address **0x62 on i2c1** (`i2c@1c2b000`), sharing that
bus with the AT24C04 EEPROM at 0x50/0x51.

On mainline nothing ever touches it, so it sits in its power-on default forever:

```
MODE1=0x10   (SLEEP set)      LEDOUT=0x00   (all outputs off)
```

Three things are needed, and Armbian ships none of them:

1. **The i2c1 bus enabled.** Armbian has a stock overlay: add `i2c1` to `overlays=` in
   `/boot/armbianEnv.txt`.
2. **The driver.** `CONFIG_LEDS_PCA963X is not set` in Armbian's sunxi64 kernels, and it is not
   built as a module either. It is a single self-contained file, so build it out of tree:

   ```bash
   sudo apt install linux-headers-current-sunxi64 build-essential dkms
   curl -sSLO https://raw.githubusercontent.com/torvalds/linux/v6.18/drivers/leds/leds-pca963x.c
   # then register it with DKMS so it survives kernel upgrades - see scripts/ and the notes below
   ```
3. **The device tree node**: [`overlays/sun50i-h5-vektor-rgb-led.dts`](overlays/sun50i-h5-vektor-rgb-led.dts).

Channel mapping, from the vendor's device tree and confirmed on hardware one channel at a time:

| `reg` | PWM register | Colour |
|---|---|---|
| 0 | 0x02 | green |
| 1 | 0x03 | red |
| 2 | 0x04 | blue |
| 3 | 0x05 | unused |

The node names in the vendor's own tree are misleading, `green@1` carries `reg = <0x0>` and `red@0`
carries `reg = <0x1>`. The `reg` values are the authoritative ones.

Once installed you get ordinary LED class devices:

```
/sys/class/leds/pca963x:green
/sys/class/leds/pca963x:red
/sys/class/leds/pca963x:blue
```

### Proving it in thirty seconds, before building anything

With just `i2c-tools` and the bus enabled, the chip can be driven by hand. This is worth doing first:

```bash
sudo i2cdetect -y -r 1          # expect 0x50, 0x51 (EEPROM) and 0x62 (PCA9633)
sudo i2cset -y 1 0x62 0x00 0x00 # MODE1: clear SLEEP
sudo i2cset -y 1 0x62 0x08 0xAA # LEDOUT: all four channels to individual PWM
sudo i2cset -y 1 0x62 0x03 0xFF # PWM1 full -> red
```


### Using it

[`scripts/vektor-status-led.sh`](scripts/vektor-status-led.sh) with
[`scripts/vektor-status-led.service`](scripts/vektor-status-led.service) gives:

| Colour | Meaning | Driven by |
|---|---|---|
| blue breathing | running, link up | kernel `pattern` trigger |
| blue and green cross-fading | Ethernet link down | kernel `pattern` trigger, complementary ramps |
| red solid | kernel panic | kernel `panic` trigger |

Everything is a kernel trigger, so the daemon only polls the carrier every couple of seconds and
does no work otherwise. The two channels of the cross-fade use complementary ramps of the same
period rather than two `timer` triggers, which would free-run on their own phases and drift into
being lit together; measured, the two brightnesses sum to 255 throughout and stayed that way over
40 seconds.

Red is deliberately left to the kernel `panic` trigger, so it lights even when userspace is already
dead, which is the one failure a daemon can never report.

Other triggers this board exposes, all kernel-native and needing no code: per-radio `phy0*` and
`phy1*` for association and traffic, `mdio_mux-0.2:00:link` and `:1Gbps` from the Ethernet PHY, and
`mmc0`/`mmc1`/`mmc2` for storage activity. Each channel takes one trigger at a time.


---

## CPU frequency scaling

Out of the box all four cores sit at whatever U-Boot left them on, 816 MHz, because `cpufreq-dt`
never probes. The stock device tree gives `cpu0` a `cpu-supply` pointing at a Silergy SY8106A
regulator on r_i2c at 0x65, and this board does not have that chip: a scan of that bus is empty. The
regulator never appears, so cpufreq defers forever.

[`overlays/sun50i-h5-vektor-cpufreq.dts`](overlays/sun50i-h5-vektor-cpufreq.dts) gives `cpu0` a
`regulator-fixed` at 1.1 V describing the rail that actually exists, and disables the phantom chip.

The safety limit then comes from the OPP table rather than from a guess:

| Frequency | Needs | At 1.1 V |
|---|---|---|
| 480, 648 MHz | 1.04 V | accepted |
| 816 MHz | 1.10 V | accepted |
| 960 MHz and up | 1.20 V+ | rejected |

So the ceiling can never exceed the frequency the board already ran at. If you establish the rail is
higher, raise the two voltages in the overlay and more operating points appear.

**Thermal throttling needs nothing extra.** `cpu0` already has `#cooling-cells` and the thermal zone
already carries cooling-maps for its passive trips at 75/80/85/90/95 °C. They activate the moment
cpufreq exists. Verified by temporarily lowering the first trip to 58 °C, since a four-core load only
reaches 70.5 °C on an open bench and cannot otherwise throttle at all: cooling states 0, 1 and 2 map
to 816, 648 and 480 MHz and recover cleanly.

## The AT24C04 EEPROM

512 bytes at 0x50/0x51 on the same bus as the LED driver. Present, answering, and claimed by nothing,
because `# CONFIG_EEPROM_AT24 is not set` in Armbian's kernels — the same gap as the LED driver.
Build `at24` out of tree the same way and apply
[`overlays/sun50i-h5-vektor-eeprom.dts`](overlays/sun50i-h5-vektor-eeprom.dts), which declares it
**read-only** because page 0 already holds a vendor provisioning token.

It is *not* where the Ethernet MAC lives. The board runs a fabricated locally-administered MAC from
the device tree; the real one is only recoverable from the vendor's rootfs. Set it with a
`systemd.link` file rather than in the device tree so it survives kernel and DTB changes.

## SPI NOR as a third boot path

The boot ROM tries SD, then eMMC, then SPI NOR. On a stock unit the flash holds the vendor's 2018
U-Boot and is never reached. Writing a current U-Boot there gives a fallback if the primary
bootloader is ever corrupted, and because the flash is last in the boot order, writing it cannot
break a working boot.

```bash
sudo apt install mtd-utils
sudo dd if=/dev/mtd0 of=nor-backup.bin bs=64k          # back up all 8 MB first
sudo flash_erase /dev/mtd1 0 0                          # the "uboot" partition, chip offset 0
sudo flashcp -v /usr/lib/linux-u-boot-current-nanopik1plus/u-boot-sunxi-with-spl.bin /dev/mtd1
sudo dd if=/dev/mtd0 bs=1 skip=4 count=8                # must print eGON.BT0
```


## Documentation

- **[docs/hardware.md](docs/hardware.md)** — what is actually on the board, and how it differs from a
  stock NanoPi K1 Plus.
- **[docs/investigation.md](docs/investigation.md)** — how the fault was found, including the dead
  ends. Worth reading if you are chasing something similar: most of it is about being wrong
  efficiently.

## Is this a general pattern?

Yes, and that is the more useful takeaway. A vendor builds an appliance on an SBC, solders a
peripheral to a USB port, and gates its power with a GPIO. Mainline enables the host controller
because the base board's device tree does, but nothing drives the enable pin, because on the base
board there is no such pin. The peripheral is then absent from `lsusb`, or present and then gone, with
nothing in the logs.

The kernel's own term for these is **onboard USB devices** (`CONFIG_USB_ONBOARD_DEV`); device tree
calls them "hard wired USB devices". The confirmation step is always the same and takes seconds:
toggle the suspected GPIO and watch `lsusb`.

## Status

Working: gigabit Ethernet, eMMC, microSD, SPI NOR, USB-A, serial console, both Wi-Fi radios
(2.4 GHz MT7601U, dual-band RTL8812BU), the front-panel RGB LED, the AT24C04 EEPROM, CPU frequency
scaling with working thermal throttling, and a U-Boot fallback in SPI NOR.

[`scripts/vektor-selfcheck.sh`](scripts/vektor-selfcheck.sh) checks all of it at boot and fails
loudly if a kernel or package change silently undoes something.

## Contributing

If you have one of these, corrections and confirmations are welcome — particularly the 4-pin JST
header's pinout, which is unpopulated in shipping units and still unidentified.
