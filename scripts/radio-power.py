#!/usr/bin/env python3
"""Drive the Vektor's two Wi-Fi radio enable lines, PA7 and PA8.

The vendor's 4.19 kernel claims these as "BL-M7612" and "BL-7601" and drives
them high. Mainline never claims them, because a genuine NanoPi K1 Plus has no
soldered radios, so on Armbian they float and the modules drop off the USB bus
minutes later. Driving them low on a working kernel kills both radios in 6 ms;
driving them high brings both back and the drivers rebind.

Needs iomem=relaxed on the kernel command line.
"""
import mmap, os, struct, sys

PIO  = 0x01C20000          # page base
PA   = 0x800               # bank A offset within that page
CFG0 = PA + 0x00           # pins 0-7,  4 bits each
CFG1 = PA + 0x04           # pins 8-15
DAT  = PA + 0x10

ON = not (len(sys.argv) > 1 and sys.argv[1] in ("off", "0", "low"))

fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=PIO)

def rd(o):    return struct.unpack("<I", m[o:o+4])[0]
def wr(o, v): m[o:o+4] = struct.pack("<I", v)

print("before  CFG0=%08x CFG1=%08x DAT=%08x" % (rd(CFG0), rd(CFG1), rd(DAT)))

# PA7 function = CFG0 bits 28-31, PA8 function = CFG1 bits 0-3.  1 = output.
wr(CFG0, (rd(CFG0) & ~(0xF << 28)) | (0x1 << 28))
wr(CFG1, (rd(CFG1) & ~(0xF <<  0)) | (0x1 <<  0))

d = rd(DAT)
wr(DAT, (d | (1 << 7) | (1 << 8)) if ON else (d & ~((1 << 7) | (1 << 8))))

print("after   CFG0=%08x CFG1=%08x DAT=%08x  -> radios %s"
      % (rd(CFG0), rd(CFG1), rd(DAT), "ON" if ON else "OFF"))
