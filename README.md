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

## Try it without reflashing your unit (reversible)

This is the safest thing in this repository, and it is worth doing before anything else: **writing
the SD card changes nothing on the appliance.**

The H5 boot ROM tries SD before eMMC and before SPI NOR, so a bootable card simply outranks whatever
is already installed. The vendor's bootloader, its rootfs on eMMC, and its U-Boot in SPI NOR are all
left exactly as they were and remain the fallback. Pull the card and the unit boots the vendor
firmware again as if nothing happened. You can evaluate every claim below on your own hardware and
walk away with the appliance bit-for-bit unchanged.

No image from this repository is involved. It is a stock Armbian community build for the NanoPi K1
Plus, unmodified — stock `sun50i-h5-nanopi-k1-plus.dtb`, stock analog-codec overlay, stock family
fixup script. Nothing vendor-derived goes on the card.

### 1. Download and verify

The build tested here, which is pinned in Armbian's archive:

```bash
B=https://dl.armbian.com/nanopik1plus/archive/Armbian_26.8.1_Nanopik1plus_trixie_current_6.18.44_minimal.img.xz
curl -fLO "$B" && curl -fLO "$B.asc" && curl -fLO "$B.sha"
```

Check the hash, then the signature. **The hash alone is not enough** — a `.sha` served by the same
mirror as the image detects corruption, not substitution, and this file becomes your board's
bootloader:

```bash
shasum -a 256 -c Armbian_26.8.1_Nanopik1plus_trixie_current_6.18.44_minimal.img.xz.sha

# the image signing key is Armbian's lead maintainer's personal key, and it is
# NOT the apt repository key (8CFA83D1...) - fetch this exact fingerprint:
gpg --keyserver hkps://keyserver.ubuntu.com \
    --recv-keys DF00FAF1C577104B50BF1D0093D6889F9F0E78D5
gpg --verify Armbian_26.8.1_Nanopik1plus_trixie_current_6.18.44_minimal.img.xz{.asc,}
```

Expected, and verified for this writeup:

```
Armbian_26.8.1_Nanopik1plus_trixie_current_6.18.44_minimal.img.xz: OK
gpg: Good signature from "Igor Pecovnik <igor@armbian.com>"
gpg: WARNING: This key is not certified with a trusted signature!
```

That warning is normal and does **not** mean verification failed. It says you have not personally
established a web-of-trust path to the key — the signature itself is good. `Good signature` is the
line that matters; `BAD signature` would be the failure.

For reference, the two hashes, since it is easy to compare the wrong one:

| File | Bytes | sha256 |
|---|---|---|
| `.img.xz` (what `.sha` covers) | 306,748,160 | `c1f9ad76d457fd74c2fbf1ee77e2c8b3ff3fc5b6e9b786597c84663e1f4267cb` |
| `.img` (after `unxz`) | 1,535,115,264 | `3aa96a23945dd2c9813762dddcaabc838c4a4c3d3370b7c0917d863c5cfa9509` |

Armbian's non-archive download tracks the newest build, so the filename and both hashes will differ
from the above. Any recent `Nanopik1plus` image should work; 26.8.1 / kernel 6.18.44 is what was
tested here.

### 2. Write the card

`dd` to the wrong device destroys it, and this is the only step in this repository that can cost you
something you care about. Identify the card and confirm it before writing:

```bash
# macOS - require Internal:No, Removable, and the size you expect
diskutil list
diskutil info /dev/diskN | egrep -i 'Device / Media Name|Removable Media|Internal|Disk Size'

# Linux
lsblk -o NAME,SIZE,TYPE,TRAN,RM,MOUNTPOINTS
```

Then, with `N` replaced by the number you just confirmed:

```bash
# macOS - rdiskN (raw) is much faster than diskN
diskutil unmountDisk /dev/diskN
xz -dc Armbian_26.8.1_Nanopik1plus_trixie_current_6.18.44_minimal.img.xz \
  | sudo dd of=/dev/rdiskN bs=4m status=progress
sync

# Linux
xz -dc Armbian_26.8.1_Nanopik1plus_trixie_current_6.18.44_minimal.img.xz \
  | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

Any card size works — the rootfs auto-resizes on first boot (57 G on the 64 GB card used here).

### 3. Boot it

Insert the card and power on. Nothing else is required: no jumper, no button, no FEL. The unit comes
up on Ethernet by itself, so you do not need a console at all — but if you want to watch, UART0 is the
**3-pin** header at the board edge (PA4 = TX, PA5 = RX, 115200 8N1, **3.3 V**). Read
[docs/hardware.md](docs/hardware.md#buttons-and-headers) first: the pins are not 5 V tolerant, and the
4-pin JST is a different, still-unidentified header — not the console.

What a correct first boot looks like:

| | Expected |
|---|---|
| Boot source | `U-Boot SPL 2026.07_armbian`, then `U-boot loaded from SD` — the card outranking SPI NOR |
| DRAM | `DRAM: 2048 MiB` — the stock K1 Plus SPL parameters are right for this board |
| Device tree | stock `sun50i-h5-nanopi-k1-plus.dtb` |
| Ethernet | `end0`, `Link is Up - 1Gbps/Full`, PHY `mdio_mux-0.2:00` `RTL8211E` |
| Thermal | reads correctly, 46-52 °C idle (the vendor's 4.19 could not: `failed to read out thermal zone (-110)`) |
| Rootfs | auto-resized |
| Wi-Fi | **both radios enumerate, then disappear 4-12 minutes later** |

That last row is the bug this repository is about, and the card is how you reproduce it. `lsusb`
shows `148f:7601` and `0bda:b812` at first; leave it running and they go, with only a
`USB disconnect` line in `dmesg`. Once you have seen that, the fix below is a device-tree overlay
and one reboot.

Everything up to this point is reversible by removing the card.

---

## Install the fix

On a running Armbian:

```bash
sudo apt install device-tree-compiler
dtc -@ -I dts -O dtb -o sun50i-h5-vektor-radio-vbus.dtbo overlays/sun50i-h5-vektor-radio-vbus.dts
sudo mkdir -p /boot/overlay-user
sudo cp sun50i-h5-vektor-radio-vbus.dtbo /boot/overlay-user/
# armbianEnv.txt takes ONE user_overlays= line, space-separated. Appending a second
# is silently ignored, so edit in place if the key already exists:
grep -q '^user_overlays=' /boot/armbianEnv.txt \
  && sudo sed -i 's/^user_overlays=.*/& sun50i-h5-vektor-radio-vbus/' /boot/armbianEnv.txt \
  || echo 'user_overlays=sun50i-h5-vektor-radio-vbus' | sudo tee -a /boot/armbianEnv.txt
sudo reboot
```

The same three commands build any of the other overlays — `rgb-led`, `cpufreq`, `eeprom` — just swap
the filename and add its basename to the same space-separated `user_overlays=` line. The `eeprom` and
`rgb-led` overlays additionally need their out-of-tree modules (below), and `rgb-led` needs `i2c1` in
the stock `overlays=` line.

Confirm it took:

```
$ grep -i vektor /sys/kernel/debug/gpio
 gpio-7   (vektor-wifi-5g-vbus ) out hi
 gpio-8   (vektor-wifi-2g-vbus ) out hi

$ lsusb | grep -E '148f|0bda'
Bus 003 Device 002: ID 148f:7601 Ralink Technology, Corp. MT7601U Wireless Adapter
Bus 004 Device 002: ID 0bda:b812 Realtek Semiconductor Corp. RTL8812BU
```

Both radios then stay up. The longest run measured for this writeup is **4895 s (1 h 22 m) with zero
`USB disconnect` events in `dmesg`** — against pre-fix failures at 237-740 s, every time. That soak is
not itself proof of "forever"; the structural argument is: the pin is now held by a regulator the
kernel owns, so there is no longer anything to stop driving it. Verified on 6.18.44, and since the fix
is in the device tree, kernel version does not matter.

If you want to check your own, `dmesg | grep -c 'USB disconnect'` should stay at 0 across an uptime
comfortably past 740 s.

### If you cannot use an overlay

[`scripts/radio-power.py`](scripts/radio-power.py) drives the same two pins from userspace via
`/dev/mem` (needs `iomem=relaxed` on the kernel command line — this disables `STRICT_DEVMEM`, so add
it for the diagnostic boot only and then take it back out; the overlay is the permanent fix). Useful
for confirming the diagnosis in thirty seconds before you commit to anything: run it and watch
`lsusb`.

[`overlays/sun50i-h5-vektor-radio-power.dts`](overlays/sun50i-h5-vektor-radio-power.dts) is the same
fix as a `gpio-hog`. It works, but `regulator-fixed` wired to `&usbphy` is the mainline sunxi idiom
(`gpio-hog` appears zero times in all 293 Allwinner device tree files), so prefer the vbus overlay.

---

## Make it permanent: install to eMMC (destructive)

Everything above is reversible by removing the card. **This step is not.** It overwrites the vendor's
root filesystem on the eMMC, and the vendor system is then gone unless you imaged it first.

Do the SD section first and get the radios working there. The eMMC install copies your running
system, so a card you have already fixed and configured is what lands on the eMMC.

### 1. Back up the vendor system — this is the only way back

Take these while booted from the SD card. You cannot cleanly image a disk you are rooted on, which is
why this step lives here and not earlier.

Confirm your device numbering first. On this unit `mmcblk2` is the 7.3 GB eMMC and `mmcblk0` is the
SD, but do not assume that — check the sizes:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS
```

Then image both media to the SD card (or over the network — the eMMC is larger than a small card):

```bash
# the vendor rootfs, 7.3 GB raw; it compresses well since most of it is empty
sudo dd if=/dev/mmcblk2 bs=4M status=progress | xz -T0 -2 > vendor-emmc.img.xz

# the SPI NOR, 8 MB. NOT optional - see below
sudo dd if=/dev/mtd0 of=vendor-spi-8MB.bin bs=64k status=progress

sha256sum vendor-emmc.img.xz vendor-spi-8MB.bin | tee vendor-backup.sha256
```

The SPI NOR image is not optional. On a stock unit the eMMC is **not** bootable by the boot ROM at
all — its 8 KiB BROM entry is zeroed and both eMMC hardware boot partitions are disabled
(`PARTITION_CONFIG: 0x00`). The vendor's U-Boot lives in SPI NOR, and it is the only bootable medium
the appliance ships with. Lose it without a copy and you have lost the original boot chain.

> **Treat your eMMC image as a secret.** It is the vendor's provisioning state for *your* unit — it
> contains the device's identity and key material. Keep it offline. Do not put it in a repository,
> and do not send it to anyone, including as a "here's my backup" attachment on an issue.

### 2. Install to the eMMC

Armbian ships the installer:

```bash
sudo armbian-install
```

It is a shim that forwards to `armbian-config --api module_partitioner`, which also takes arguments
directly:

```bash
sudo armbian-install --target /dev/mmcblk2 --boot emmc --fs ext4 --yes
```

### 3. Put a bootloader on the eMMC

Because the vendor left the eMMC unbootable by the BROM, an eMMC install has to write U-Boot to the
user area at the 8 KiB offset. The installer does this, but verify it rather than assume:

```bash
UB=/usr/lib/linux-u-boot-current-nanopik1plus/u-boot-sunxi-with-spl.bin
sudo dd if="$UB" of=/dev/mmcblk2 bs=1024 seek=8 conv=fsync status=progress

# read it straight back and compare byte-for-byte
S=$(stat -c%s "$UB")
sudo dd if=/dev/mmcblk2 bs=512 skip=16 count=$(( (S+511)/512 )) status=none \
  | head -c "$S" | sha256sum
sha256sum "$UB"
```

`seek=8` with `bs=1024` is the 8 KiB offset the boot ROM looks at. The hardware boot partitions stay
disabled; nothing needs to change there.

### 4. Stop the SD card outranking the eMMC

The boot ROM tries SD **before** eMMC, so as long as the card carries a bootloader it wins — and you
would still be booting from the card while believing you had migrated. Erase its bootloader region,
keeping a copy first:

```bash
sudo dd if=/dev/mmcblk0 of=sd-first-1MiB.bin bs=1M count=1        # keep this
sudo dd if=/dev/zero of=/dev/mmcblk0 bs=1M count=1 conv=fsync
sudo dd if=/dev/mmcblk0 bs=1 skip=8196 count=8 | od -c            # must be all \0
```

After a reboot U-Boot should report `Trying to boot from MMC2`.

### 5. Reuse the card for data

```
UUID=<your-uuid>  /data  ext4  defaults,noatime,nofail,x-systemd.device-timeout=10  0 2
```

`nofail` and the device timeout matter: without them a card that is missing, dead or slow to enumerate
blocks boot on a headless box.

### Reverting

```bash
xzcat vendor-emmc.img.xz | sudo dd of=/dev/mmcblk2 bs=4M conv=fsync status=progress
sudo flash_erase /dev/mtd0 0 0
sudo flashcp -v vendor-spi-8MB.bin /dev/mtd0
```

**Not tested here** — this unit has not been reverted, so unlike everything else in this repository
these two commands are reasoned rather than demonstrated. They are the inverse of the writes that
*were* performed, and all three `mtd` nodes are writable (`flags=0xc00`), but treat them as a plan
rather than a proven recipe. The backups themselves are the part that matters; verify their
checksums when you take them, because that is what you cannot redo later.

### Keeping U-Boot current

The `linux-u-boot-current-nanopik1plus` package ships the binary; nothing writes it to your boot
medium automatically. So an `apt upgrade` can leave the package newer than what is actually booting
you, silently and indefinitely.

A worked example from this board: the eMMC was written from the U-Boot bundled in the 26.8.1 image
(built Aug 09 2026, patch hash `P5dee`), and the SPI NOR was flashed later, after an upgrade had
pulled package 26.8.3 (Aug 17 2026, `P9bd1`). The fallback ended up **newer than the primary**. Check
what you are actually running against what is installed:

```bash
UB=/usr/lib/linux-u-boot-current-nanopik1plus/u-boot-sunxi-with-spl.bin
strings "$UB" | grep -m1 'U-Boot 20'                                        # the package
sudo dd if=/dev/mmcblk2 bs=512 skip=16 count=2000 status=none | strings | grep -m1 'U-Boot 20'   # eMMC
sudo dd if=/dev/mtd0 bs=512 count=2000 status=none | strings | grep -m1 'U-Boot 20'              # SPI NOR
```

If they differ and you want them aligned, rewrite with the step 3 command (eMMC) or the SPI NOR
section below. Do the SPI NOR one first: it is last in the boot order, so a bad write there cannot
stop the board booting, which makes it the safe one to practise on.

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
   sudo mkdir -p /usr/src/leds-pca963x-1.0
   sudo cp scripts/dkms/leds-pca963x/{dkms.conf,Makefile} /usr/src/leds-pca963x-1.0/
   sudo curl -sSL -o /usr/src/leds-pca963x-1.0/leds-pca963x.c \
     https://raw.githubusercontent.com/torvalds/linux/v6.18/drivers/leds/leds-pca963x.c
   sudo dkms add -m leds-pca963x -v 1.0
   sudo dkms install -m leds-pca963x -v 1.0
   ```

   `AUTOINSTALL="yes"` in the shipped `dkms.conf` is what rebuilds it on every kernel upgrade.
   Confirm with `dkms status` — it should read `leds-pca963x/1.0, <kernel>, aarch64: installed`.
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

Red is left to the kernel `panic` trigger, so it lights even when userspace is already dead, which is
the one failure a daemon can never report. The daemon arms it once at start and never touches it
again — do not rely on `armbian-led-state` restoring it, for the reason in the next section.

### The `pattern` trigger breaks `armbian-led-state` — on any board

Worth knowing before you use the `pattern` trigger on Armbian, because the failure appears one reboot
later and does not name the LED that caused it:

```
× armbian-led-state.service - Armbian leds state
   armbian-led-state-restore.sh[16621]: Invalid state file, syntax error in configuration file
```

Since Linux 6.10 the `pattern` trigger stores **one** pattern but exposes it through up to three
sysfs attributes, selected by an `enum pattern_type`:

| attribute | type | present when |
|---|---|---|
| `pattern` | `PATTERN_TYPE_SW` — standard timer | always |
| `hr_pattern` | `PATTERN_TYPE_HR` — hrtimer | always |
| `hw_pattern` | `PATTERN_TYPE_HW` — offloaded to the LED controller | only if the driver implements `pattern_set` |

Both software forms take the same `brightness delta_t` list and `delta_t` is in **milliseconds** for
both — `hr_pattern` is not a finer unit, it is the same unit on a higher-resolution timer
(`ms_to_ktime()` vs `msecs_to_jiffies()` in `pattern_trig_timer_restart()`).

Only one type is stored at a time, and `pattern_trig_show_patterns()` in
`drivers/leds/trigger/ledtrig-pattern.c` prints nothing for any other:

```c
	if (!data->npatterns || data->type != type)
		goto out;
```

So on a software pattern, `hr_pattern` reads back **empty** — and since both `pattern` and
`hr_pattern` are always visible, every pattern-trigger LED has at least one attribute that reads
empty.

`armbian-led-state-save.sh` writes out every writable attribute unfiltered, skipping only values with
control characters, so at shutdown it emits `hr_pattern=`. `armbian-led-state-restore.sh` treats an
empty value as fatal and `exit 1`s.

The restore is a streaming `while read` loop that writes each attribute as it parses it, so the abort
does not lose everything — it loses **everything from the offending line onward**. On this board the
first empty value fell in the `pca963x:blue` stanza, so the two `nanopi:*` LEDs and blue's trigger
were restored and `pca963x:red` was never reached. That is precisely why red was found sitting on
`trigger=none` with its `panic` trigger unarmed.

This is not specific to this board, but it does need **kernel 6.10 or newer**, which is where
`hr_pattern` was added. Before that the trigger exposed only `pattern` plus a conditional
`hw_pattern`, so an LED whose driver has no `pattern_set` — like this one — had nothing that could
read back empty.

Two layers fix it:

1. [`patches/armbian-led-state-save-empty-value.patch`](patches/armbian-led-state-save-empty-value.patch)
   — one line, `[[ -z "$VALUE" ]] && continue`, so the empty value is never written. Note that
   `/usr/lib/armbian/armbian-led-state-save.sh` belongs to `armbian-bsp-cli-*` and is not a conffile,
   so a package upgrade reverts this silently.
2. [`scripts/systemd/10-vektor-strip-empty-values.conf`](scripts/systemd/10-vektor-strip-empty-values.conf)
   — a drop-in under `/etc`, which no package upgrade can touch, running
   [`scripts/vektor-led-state-sanitize.sh`](scripts/vektor-led-state-sanitize.sh) as `ExecStartPre` to
   scrub the state file before the restore reads it.

The first keeps the file clean; the second means an upgrade reverting the first changes nothing you
can observe.

There is a related ordering trap. `armbian-led-state`'s restore writes a saved pattern straight into
sysfs, so if it runs after your daemon has set the LED, the board shows a stale state indefinitely —
a daemon watching only for carrier *transitions* never notices, because the carrier never changed.
Hence [`scripts/systemd/10-after-led-state.conf`](scripts/systemd/10-after-led-state.conf) for
ordering, and a daemon that re-asserts whenever the LED drifts from what it last wrote. Measured
recovery after a deliberate stomp: 2 s.

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

### Measured thermals, in the case

A nineteen-minute instrumented run ([`scripts/thermal-test.sh`](scripts/thermal-test.sh)): idle
settle, a 1-to-4-core ramp, ten minutes sustained, then cool-down.

| Phase | Temp | Frequency | Cooling state |
|---|---|---|---|
| Settled idle | 43-45 C | 480 MHz | 0 |
| 1 core | 48 C | 816 MHz | 0 |
| 2 cores | 51-53 C | 816 MHz | 0 |
| 3 cores | 55-58 C | 816 MHz | 0 |
| 4 cores, sustained | rises to 74-75 C over ~400 s | 816 MHz | 0 |
| **4 cores, past ~420 s** | **holds 74-75 C** | **cycles 816 / 648 / 480** | **0 / 1 / 2** |
| 20 s after load ends | 65 C | 480 MHz | 0 |

Throttling engages on its own at the 75 C trip and holds there by cycling all three cooling states.
Roughly 30 C of headroom remains to the 105 C critical trip.

**The governor responds to the presence of load, not its size.** One busy core reaches 816 MHz within
fifteen seconds, and four cores do the same. What scales with core count is temperature. The saving
is entirely at idle, where it drops to the 480 MHz minimum.

Three traps worth knowing if you repeat this:

- **Check the thermal interface first.** An earlier run of this test reported a 70.5 C ceiling. The
  heatsink had been unbolted for photographs and its pad discarded, so that number described a board
  with no thermal path at all.
- **Run long enough to reach steady state.** That same run lasted 150 s. At the equivalent point the
  proper run reads about 67 C and is still climbing; it does not settle until roughly 400 s. A
  temperature still rising is not a ceiling.
- **Rows showing cores at different frequencies are an artifact.** `affected_cpus` is `0 1 2 3` under
  a single `policy0`, so this SoC cannot run cores at different clocks. Reading the four sysfs files
  takes about 32 ms, long enough to straddle a transition. The sensor also jitters by about 4 C
  between consecutive samples.


## The AT24C04 EEPROM

512 bytes at 0x50/0x51 on the same bus as the LED driver. Present, answering, and claimed by nothing,
because `# CONFIG_EEPROM_AT24 is not set` in Armbian's kernels — the same gap as the LED driver.
Build `at24` out of tree exactly as for `leds-pca963x` above, using
[`scripts/dkms/at24/`](scripts/dkms/at24) and
`https://raw.githubusercontent.com/torvalds/linux/v6.18/drivers/misc/eeprom/at24.c`, then apply
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
cat /proc/mtd            # CHECK FIRST - confirm the layout matches before erasing anything
```

This step erases flash, so verify the partition numbering on your own unit rather than trusting the
numbers below. On this board:

```
dev:    size   erasesize  name
mtd0: 00800000 00001000 "spi0.0"      <- the whole 8 MB chip
mtd1: 00100000 00001000 "uboot"       <- 1 MB at chip offset 0
mtd2: 00100000 00001000 "env"         <- the U-Boot environment; leave it alone
```

`mtd0` is the whole chip, `mtd1` is the `uboot` partition starting at offset 0, and `mtd2` holds the
U-Boot environment — do not write that one (and never `saveenv` from U-Boot on this board). If your
`/proc/mtd` differs, stop and work out the mapping first: `flash_erase` on the wrong node destroys the
fallback you are trying to create.

```bash
sudo dd if=/dev/mtd0 of=nor-backup.bin bs=64k          # back up all 8 MB first
sudo flash_erase /dev/mtd1 0 0                          # the "uboot" partition, chip offset 0
sudo flashcp -v /usr/lib/linux-u-boot-current-nanopik1plus/u-boot-sunxi-with-spl.bin /dev/mtd1
sudo dd if=/dev/mtd0 bs=1 skip=4 count=8                # must print eGON.BT0
```

Because the flash is last in the boot order, a failed write here cannot break a working boot — but a
`flash_erase` aimed at the wrong device very much can.


## Installing the runtime pieces

Everything under `scripts/` expects to live in `/usr/local/sbin`, and the unit files reference it by
absolute path. Nothing here is required for the radio fix — that is the overlay alone.

```bash
# the LED status daemon
sudo install -m 755 scripts/vektor-status-led.sh /usr/local/sbin/
sudo install -m 644 scripts/vektor-status-led.service /etc/systemd/system/
# if your Ethernet interface is not end0:
sudo systemctl edit vektor-status-led.service     # [Service] / Environment=IFACE=eth0

# make armbian-led-state survive a pattern-trigger LED (see the section above)
sudo install -m 755 scripts/vektor-led-state-sanitize.sh /usr/local/sbin/
sudo mkdir -p /etc/systemd/system/armbian-led-state.service.d \
              /etc/systemd/system/vektor-status-led.service.d
sudo install -m 644 scripts/systemd/10-vektor-strip-empty-values.conf \
     /etc/systemd/system/armbian-led-state.service.d/
sudo install -m 644 scripts/systemd/10-after-led-state.conf \
     /etc/systemd/system/vektor-status-led.service.d/

sudo systemctl daemon-reload
sudo systemctl enable --now vektor-status-led.service
sudo systemctl restart armbian-led-state.service

# optional: the boot self-check and the thermal soak
sudo install -m 755 scripts/vektor-selfcheck.sh scripts/thermal-test.sh /usr/local/sbin/
```

The self-check is a plain script, not a unit — run it by hand, or wire it to a
`systemd` unit or `cron @reboot` if you want it at every boot. It needs root (it reads
`/sys/kernel/debug/gpio` and `/dev/mtd0`). Both it and `thermal-test.sh` honour `LOG=`, and the
self-check takes an optional `REQUIRE_MOUNT=/your/data/partition`.

To apply the one-line Armbian patch:

```bash
sudo patch -p1 -d/ --backup < patches/armbian-led-state-save-empty-value.patch
```

That file is owned by `armbian-bsp-cli-*` and is not a conffile, so an upgrade silently reverts it.
The drop-in above is what actually guarantees the fix; the patch just keeps the state file clean.

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
loudly if a kernel or package change silently undoes something. Assertions are proven able to fail
before being trusted — a check that has only ever passed has not been tested. That review has already
caught two of its own: the boot-set check passed when all three `/boot` symlinks were *missing*
(all empty, so the equality held), and the radio check counted USB devices on port 1 of any bus
rather than the radios themselves.

## Licensing

The overlays, scripts and prose here are MIT, per [LICENSE](LICENSE).

Short excerpts of the vendor's device tree, their application source, and kernel output are quoted in
`docs/` for identification and interoperability analysis only. They are not covered by the MIT grant
and remain under their original licenses. No vendor rootfs, device tree, application or bootloader
binary is redistributed here, and none will be.

`leds-pca963x.c` and `at24.c` are GPL-2.0 kernel sources. This repository does not vendor them — the
build instructions fetch them from the upstream tree at build time, so they keep their own license.

## Contributing

If you have one of these, corrections and confirmations are welcome — particularly the 4-pin JST
header's pinout, which is unpopulated in shipping units and still unidentified.
