#!/usr/bin/env python3
"""Extract a HEDZ disc image to a folder. Usage: extract_disc.py <hedz.cue|hedz.img|hedz.bin|hedz.iso> <outdir>
Raw 2352-byte-sector images (MODE1/2352, as in the .cue) are first converted to a plain ISO (2048 bytes of user data per
sector), which 7z can read. Needs `7z` (p7zip / 7zip) on PATH."""
import os, re, shutil, subprocess, sys, tempfile

if len(sys.argv) != 3:
    sys.exit(__doc__)
src, out = sys.argv[1], sys.argv[2]
if src.lower().endswith(".cue"):
    m = re.search(r'FILE\s+"?([^"\r\n]+?)"?\s+BINARY', open(src, errors="replace").read())
    if not m:
        sys.exit("cannot find the FILE line in " + src)
    src = os.path.join(os.path.dirname(os.path.abspath(src)), m.group(1))
seven = shutil.which("7z") or shutil.which("7zz") or shutil.which("7za")
if not seven:
    sys.exit("7z not found (install p7zip / 7zip)")
size = os.path.getsize(src)
with tempfile.TemporaryDirectory(prefix="hedz-iso-") as tmp:
    iso = src
    if size % 2352 == 0 and not src.lower().endswith(".iso"):
        iso = os.path.join(tmp, "disc.iso")
        with open(src, "rb") as f, open(iso, "wb") as o:
            while True:
                sec = f.read(2352 * 512)
                if not sec:
                    break
                for i in range(0, len(sec), 2352):
                    s = sec[i:i + 2352]
                    o.write(s[16:2064] if s[15] == 1 else s[24:2072])     # MODE1 / MODE2 form 1
    os.makedirs(out, exist_ok=True)
    # exit code 2 is only a warning here: the disc has an extra Mac/HFS part ("Incorrect big-endian headers") that 7z skips
    r = subprocess.run([seven, "x", "-y", "-o" + out, iso], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if r.returncode not in (0, 1, 2):
        sys.exit("7z failed with exit code %d" % r.returncode)
if not os.path.exists(os.path.join(out, "Hedz", "Hedz.exe")):
    sys.exit("extracted, but Hedz/Hedz.exe is missing - is this the HEDZ CD?")
print("extracted to", out)
