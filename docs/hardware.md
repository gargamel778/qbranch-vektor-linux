# What is actually on the board

PCB marked **V4.0**, dated 2019-07-05. FCC ID **`2ASZI-VK02A`**, granted April 2020 to Q-Branch Labs,
Inc., Wilmington, Delaware — their only filing. Models `VK02A`–`VK02Z` are colour variants of
identical hardware. The FCC internal-photos exhibit shows this PCB with the RF cans removed and is
the only published teardown; it is free to download from the FCC OET database by ID.

Three boot stages all name the same board: ATF prints `model: FriendlyARM NanoPi K1 plus`, U-Boot
prints `Model: FriendlyARM NanoPi K1 plus`, and the kernel prints
`Machine model: FriendlyElec NanoPi K1 Plus`. Those strings match Armbian's out-of-tree U-Boot patch
and kernel DTS byte for byte. **There is no mainline NanoPi K1 Plus DTS at all** — it exists only as
an Armbian patch. The vendor wrote no board port; they shipped stock Armbian with their application
on top.

| Part | Identity | Role |
|---|---|---|
| SoC | Allwinner **H5**, soc id `0x1718` | 4 × Cortex-A53, ARM64, Mali-450MP4. No PCIe, no USB 3.0, no SATA |
| DRAM | 4 × Samsung `K4B4G1646E-BCMA` | 4 Gbit ×16 each → **2 GB** |
| eMMC | Samsung `KLM8G1GETF` | 8 GB → `mmcblk2`, 7.28 GiB user area, plus `boot0`/`boot1` |
| SPI NOR | Winbond `W25Q64JVSIQ` | 8 MB, holds the vendor U-Boot. Linux misdetects it as `s25fl064k`; harmless |
| Ethernet | Realtek `RTL8211E` | gigabit, RGMII, external PHY |
| 5 GHz radio | **Realtek RTL8812BU** on an AI-Link module, two u.FL | 2T2R 802.11ac over **USB**, `0bda:b812` |
| 2.4 GHz radio | **MediaTek MT7601UN**, one u.FL | 1T1R 802.11n over **USB**, `148f:7601` |
| EEPROM | Atmel `AT24C04C` | 4 Kbit I²C at 0x50/0x51 |
| Soft power | 10-pin MSOP marked `9633 / 02 03`, MMBT3904, two SOD-123 diodes | power latch. **There is no PMIC** |

## Differences from a stock NanoPi K1 Plus

| | Stock K1 Plus | Vektor V4.0 | Consequence |
|---|---|---|---|
| SPI NOR | none at all | 8 MB, holds the bootloader | Armbian's DTS already declares `&spi0` with a `jedec,spi-nor` child, so a stock image binds `m25p80` and hands you MTD access |
| Wi-Fi | one SDIO RTL8189 | **two USB radios**, nothing on SDIO | `mmc1` probes and finds nothing. **This is where the GPIO problem comes from** |
| CPU regulator | Silergy SY8106A | **absent** | fixed CPU rail, no DVFS, `vdd-cpux-dummy` at 1.1 V |
| USB | 3 × USB-A + micro-USB | 1 × USB-A + OTG header + 2 soldered radios | all four H5 USB ports in use |
| Display | HDMI connector | **nothing routed** | headless only; the DRM driver reports `Cannot find any crtc or sizes` |
| Power in | micro-USB | 5 V barrel jack | certified supply was 5 V / 2 A |
| Buttons | one | POWER, UBOOT, RECOVERY, RESET | |

## Buttons and headers

- **UBOOT** grounds H5 ball **W6**, so the boot ROM goes straight to USB FEL. Confirmed on hardware by
  reading `VER_REG`: `md.l 0x01c00024 1` returns `00000101` idle and `00000001` with the button held;
  bit 8 is `UBOOT_SEL_PAD_STA`, 0 = FEL. **This is the escape hatch, and it works.**
- **RECOVERY** is an ordinary GPIO, *not* the boot-mode pin — holding it leaves bit 8 at 1. A vendor
  U-Boot patch polls it and prints `recovery button press 1s.`, but no `recovery*` environment
  variable exists, so whatever it does is compiled in and still unknown.
- **RESET** grounds ball V6.
- **3-pin header** is the UART0 console: PA4 = TX, PA5 = RX, 115200 8N1, 3.3 V, at the board edge
  beside the SPI flash. Silkscreen boxes pin 1. **Pitch is ~2.0 mm, not 2.54 mm**, so standard DuPont
  leads do not fit.
- **5-pin header** labelled OTG is a micro-USB breakout and is the FEL port.
- **4-pin JST** is unidentified and unpopulated in shipping units. Its traces run to the same node as
  the POWER button, so a front-panel harness is the best guess.

⚠️ The H5's I/O pads are **not 5 V tolerant** — absolute maximum on `VCC-IO` is −0.3 to +3.6 V. Never
let 5 V reach the 3-pin header, the JST, or any GPIO. And you cannot tell TX from RX with a
multimeter here: the SPL enables a pull-up on PA5, so both pins read about 3.3 V.

## Boot order

`SDC0 → EMMC2 → SDC2 → NAND → SPI_NOR → USB FEL`, each step taken only on failure, and the whole
sequence gated on the UBOOT pin. So a bootable microSD outranks everything and no onboard flash ever
needs erasing to take control of the board. That is what makes this device safe to experiment with.

## The front-panel RGB LED

Not on a GPIO. An **NXP PCA9633** four-channel I2C PWM LED driver at **0x62 on i2c1**
(`i2c@1c2b000`), sharing the bus with the AT24C04 EEPROM at 0x50/0x51. Confirmed by scan:

```
50: 50 51 -- -- ...
60: -- -- 62 -- ...
```

Channel mapping, from the vendor device tree and verified on hardware one channel at a time:

| `reg` | PWM register | Colour |
|---|---|---|
| 0 | 0x02 | green |
| 1 | 0x03 | red |
| 2 | 0x04 | blue |
| 3 | 0x05 | unused |

⚠️ The node names in the vendor's tree contradict their own `reg` values — `green@1` carries
`reg = <0x0>` and `red@0` carries `reg = <0x1>`. Trust `reg`.

On mainline the chip is never woken and sits at its power-on default of `MODE1=0x10` (SLEEP set),
`LEDOUT=0x00` (all outputs off), which is why the LED appears dead.

Armbian's kernels do not build the driver: `# CONFIG_LEDS_PCA963X is not set`, and it is not shipped
as a module either. It is one self-contained source file and builds cleanly out of tree against
`linux-headers-current-sunxi64`.
