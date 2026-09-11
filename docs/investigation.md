# How the fault was found

Kept because the dead ends are more useful than the answer. The answer is four lines of device tree;
getting there took a day and about a dozen refuted hypotheses.

## The symptom

Both soldered Wi-Fi radios enumerate normally at boot, then disappear. `dmesg` contains exactly one
line per radio and nothing else, ever:

```
usb 3-1: USB disconnect, device number 2
usb 4-1: USB disconnect, device number 2
```

No error, no reset, no retry. The two radios die minutes apart, and neither the survival time nor the
gap between them is constant:

| Kernel | Radio 1 | Radio 2 | Gap |
|---|---|---|---|
| 6.18.44 | 310 s | 340 s | 30 s |
| 7.1.8 | 350 s | 398 s | 48 s |
| 7.1.8, no drivers | 237 s | 251 s | 14 s |
| 6.1.77 | 389 s | 402 s | 13 s |

Meanwhile the vendor's own 4.19 kernel held both radios for 7862 seconds with zero disconnects.

## What it was not

Each of these was eliminated by a controlled test, and several of them were confidently asserted
before being refuted:

| Hypothesis | How it died |
|---|---|
| The Wi-Fi drivers | Both radios still drop with `modprobe.blacklist` set and `lsmod` empty of them |
| Network load | Reproduced with the Ethernet cable physically out, polling only over serial |
| "4.19 works because no drivers were loaded" | Loaded both drivers on 4.19: 6672 s, zero disconnects |
| systemd / udev / rfkill / NetworkManager | Reproduced on a modern kernel booted with `init=/bin/bash` |
| Thermal | 33–35 °C, and the *hotter* runs lasted longer |
| Port power | `HCSPARAMS` shows PPC=0; this controller has no port-power control |
| VBUS regulators | Only `usb0` has one in either device tree |
| USB autosuspend | `usbcore.autosuspend=-1`, and it drops with no driver bound at all |
| USB 2.0 LPM / L1 | EHCI LPM was removed from Linux in 2012; the H5 EHCI has no LPM capability |
| A kernel regression | 6.1.77, the oldest prebuilt Armbian kernel, fails identically |
| `PHY_DISCON_TH_SEL` not reaching PHY2/3 | Programmed it by hand; controlled A/B gave 683 s without and 715 s with |

Two source-level findings were worth the effort even though they did not solve it. **CCS (`PORTSC`
bit 0) is a read-only hardware bit** — nothing in `usbcore` or `ehci-hcd` can clear it, so a
`0x1005 → 0x1000` transition necessarily starts in the analog domain. And on `ehci-hcd` there is **no
periodic timer** servicing an idle root port at all (`uses_new_polling = 1` with `HCD_FLAG_POLL_RH`
never set), so nothing in software was even touching the port.

## The mistake that hid it

The 20 Hz sampler watched every GPIO bank through the moment of the drop and found every register
**bit-for-bit constant**. That was reported as "no load switch moves, so that hypothesis is dead."

True, and the wrong question. The pins were already wrong at boot and never changed. **An instrument
that only detects change is blind to a value that was wrong all along.** Failure modes divide into
"something happened" and "something was never set up", and a change-detector only sees the first.

## What actually found it

Diffing *static* state between the working kernel and the broken one. On the vendor's 4.19:

```
gpiochip1: GPIOs 0-223, parent: platform/1c20800.pinctrl
 gpio-7   (                    |BL-M7612            ) out hi
 gpio-8   (                    |BL-7601             ) out hi
```

Two GPIOs claimed, named after the two radio modules, driven high. On every modern kernel those lines
are not claimed at all and read low. It was sitting in `/sys/kernel/debug/gpio` the whole time.

## Proof, both directions

On a running kernel with both radios alive, clearing the two bits:

```
before PA_DAT=00000180
after  PA_DAT=00000000
[ 1512.286700] usb 4-1: USB disconnect, device number 2
[ 1512.292574] usb 5-1: USB disconnect, device number 2
```

Both gone in 6 ms. Setting them back:

```
PA_DAT now 00000180
mt7601u 4-1:1.0 wlx...: renamed from wlan0
ieee80211 phy2: Selected rate control algorithm 'minstrel_ht'
```

Both back, drivers rebound.

## Why every observation now makes sense

Two separate enable pins, so two radios dying independently, minutes apart. A floating pin
discharging through leakage, so a random failure time. The module genuinely unpowered, so the port
reports no connection and no host-side reset could ever recover it. Nothing failing, so no error
message. And the "boot the vendor kernel first" ritual worked because that kernel drives the pins,
and the pin state survives a warm reset into the next kernel.

## Establishing which pin feeds which port

The vendor's labels suggested a mapping. Testing it took two attempts, and the first was worthless:
drive one pin, reboot, observe both radios present, nearly conclude one pin is sufficient. **A warm
reboot never drops the rail**, so the other module was simply still powered from before. Redone with
one pin explicitly held *low*, exactly one module survived, which settles it.

## A note on warm resets

On this board, a warm reset out of the vendor 4.19 kernel hangs it dead — no output at all, not even
the U-Boot SPL banner. Both `reboot -f` and sysrq `b` do it, because both route through PSCI to the
firmware, which drives a watchdog in the always-on power domain.

The **main-domain sunxi watchdog at `0x01c20ca0`** is a different device and resets cleanly:

```sh
exec 3>/dev/watchdog     # hold the fd open, never feed it; 16 s timeout
```

Worth knowing on any headless Allwinner board where `reboot` sometimes wedges the machine.

---

# Finding the LED

A shorter hunt than the radios, and a cleaner lesson: the answer was in the vendor's own files the
whole time.

## Four wrong guesses

Armbian inherits two LED definitions from the real NanoPi K1 Plus, `nanopi:green:status` on PA10 and
`nanopi:red:pwr` on PL10. The vendor's kernel drove neither of those; it drove **PE0** and **PL3**,
both exported by its userspace. That looked like a strong lead, so those four pins were driven one at
a time with everything else dark.

All four were dead. PL3 even had to be freed from the button driver first, since Armbian claims it as
`sw4` while the vendor put its button on PL4.

## What actually found it

One grep of the vendor's own application source:

```
LED_CONTROL_FILE = "/sys/class/leds/pca963x:{}/brightness"
```

`pca963x` is an NXP I2C LED driver. The LED was never on a GPIO, which is why no pin could light it.
The vendor's device tree then gave the address, the bus and the channel mapping outright, and their
settings file even names the colours they used: white for standby, orange for notifications, red for
failure, yellow while updating.

The lesson is the same one the radios taught, applied earlier: **diff against the working system
before probing.** Two greps of harvested vendor material beat an hour of driving pins.

## A bonus finding in the same file

The vendor's device tree also declares this:

```
leds {
    compatible = "gpio-leds";
    pwr    { label = "BL-7601";  default-state = "on"; gpios = <&pio 0 8 0>; };
    status { label = "BL-M7612"; default-state = "on"; gpios = <&pio 0 7 0>; };
};
```

That is PA8 and PA7 — the Wi-Fi radio power enables — implemented as `gpio-leds` purely as a
convenient way to hold a pin high at boot. Independent confirmation of the radio fix, from the
vendor's side.

---

# The LED fix broke a service, one reboot later

`armbian-led-state.service` came up failed after the next reboot:

```
× armbian-led-state.service - Armbian leds state
   Process: 16621 ExecStart=/usr/lib/armbian/armbian-led-state-restore.sh (code=exited, status=1/FAILURE)
   armbian-led-state-restore.sh[16621]: Invalid state file, syntax error in configuration file
```

The message does not say which line, which LED, or which attribute.

## Reading the parser instead of guessing

The restore script rejects a line only here:

```bash
[[ "$LINE" =~ $REGEX_PARSE ]]
PARAM=${BASH_REMATCH[1]}
VALUE=${BASH_REMATCH[2]}
if [[ -z $PARAM || -z $VALUE ]]; then
    echo "Invalid state file, syntax error in configuration file "
    exit 1
fi
```

So the file contains a key with no value. It was `hr_pattern=`.

That is not corruption — it is generated deterministically. The kernel `pattern` trigger exposes two
attributes for one underlying pattern, `pattern` (software, ms) and `hr_pattern` (hrtimer, µs), and
`pattern_trig_show_patterns()` bails out early when asked for the kind that is not stored:

```c
	if (!data->npatterns || (data->is_hw_pattern ^ hardware))
		goto out;      /* prints nothing */
```

`armbian-led-state-save.sh` dumps every writable attribute, filtering only values containing control
characters, so it writes `hr_pattern=`. One empty value aborts the entire restore, so no LED is
restored at all.

An Armbian bug, not a Vektor one. It surfaced here only because the Ethernet cross-fade is the first
thing on this board to use the `pattern` trigger.

## Two bugs of my own, found on the way

**The comment lied.** The daemon's header read *"Red is deliberately never touched: it belongs to the
kernel `panic` trigger"* — and nothing in the daemon ever set that trigger. It had been armed by hand
once, captured into the state file at shutdown, and was only ever coming back through the restore
that was now failing. Live state was `red trigger=none`: a kernel panic would have gone unsignalled,
while the documentation said otherwise. Documented intent is not implemented behaviour, and only the
running system can tell you which you have.

**Watching for an edge again.** Restarting `armbian-led-state` under the running daemon left blue and
green in the link-*down* cross-fade with the cable plugged in. The restore writes a saved pattern
straight into sysfs; the daemon only acted on carrier *transitions*, and the carrier had not changed,
so it never corrected the LED. This is the same mistake as the GPIO sampler earlier in this document —
watching for a change when the *level* is what matters. Fixed by ordering the units and by having the
daemon re-assert whenever the LED drifts from what it last wrote.

## Testing the tests

Both new self-check assertions were made to fail before being trusted: `red trigger` forced to `none`,
and a bad line appended to the state file with `chattr +i` used to defeat the sanitizer so the restore
genuinely saw it.

```
FAIL: armbian-led-state is failed - its save script emits an empty hr_pattern= ...
FAIL: red LED trigger is 'none', not panic - a kernel panic would go unsignalled
```

That step matters more than it looks. A check that has only ever returned OK has not been tested; it
has merely been run. Several hours were lost earlier in this project to exactly that — a sampler that
could not have reported the thing it was watching for.

## Result

After a real reboot, with no manual intervention:

```
Active: active (exited)
Process: 458 ExecStartPre=/usr/local/sbin/vektor-led-state-sanitize.sh  (status=0/SUCCESS)
Process: 483 ExecStart=/usr/lib/armbian/armbian-led-state-restore.sh    (status=0/SUCCESS)

  blue   trigger=pattern  brightness=118  pattern=8 1400 200 1400
  green  trigger=none     brightness=0
  red    trigger=panic    brightness=0

0 loaded units listed.        # systemctl --failed
```

The sanitizer logged nothing on that boot: the shutdown save was already clean, so the one-line fix in
the save script carried the whole cycle and the `/etc` drop-in stayed an untriggered backstop. That is
the arrangement worth copying — fix the cause where you can, and put the guarantee somewhere a package
upgrade cannot reach.
