"""Generate an e2 studio debug launch for a RA6M5 PSA Arch suite.

    python make_psa_arch_launch.py <name> <spe-build-dir> <ns-build-dir>
    python make_psa_arch_launch.py ra6m5_TFM_test_storage_gcc C:\\b\\m5cry C:\\b\\m5sto

ra6m5_TFM_test_crypto_gcc.launch is the template. Only the build directories change: SPE images
come from <spe>\\build-spe\\bin, the NS image from <ns>\\bin. e2 resolves the J-Link settings
file as ${LaunchConfigName}.jlink, so a copy is made under the new name as well.

The launches live in ra6m5_gcc_nonsecure/ for both toolchains - that is the e2 project the
launch is attached to, not a statement about which compiler built the images.

Two things to know when e2 touches these files:

  - Opening a launch in the Debug Configurations dialog rewrites it, and has been observed to
    drop reset-on-connection (the jlink.connection.resetCon attribute AND -uResetCon= 1 in
    serverParam). Without it the debugger attaches to a running secure image and the flash
    erase fails. Compare against the template if a launch suddenly cannot erase.
  - The test launches erase code and data flash on download, matching the RA6E1 convention.
    Data flash holds the NV counters and the PS/ITS areas, so not erasing it carries state
    between runs - which is how a stale security counter once made BL2 reject a good image.
"""
import io
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LAUNCH_DIR = os.path.join(os.path.dirname(HERE), "ra6m5_gcc_nonsecure")
TEMPLATE = "ra6m5_TFM_test_crypto_gcc"
BS = chr(92)

if len(sys.argv) != 4:
    print(__doc__)
    sys.exit(2)

name, spe, ns = sys.argv[1], sys.argv[2], sys.argv[3]
spe = spe.rstrip(BS)
ns = ns.rstrip(BS)

with io.open(os.path.join(LAUNCH_DIR, TEMPLATE + ".launch"), "rb") as f:
    b = f.read()

# NS first: "m5cryns" contains "m5cry", so the SPE swap would corrupt it otherwise.
b = b.replace(b"C:" + BS.encode() + b"b" + BS.encode() + b"m5cryns", ns.encode())
b = b.replace(b"C:" + BS.encode() + b"b" + BS.encode() + b"m5cry", spe.encode())

# e2 writes CRLF; keep the files byte-comparable with the ones it maintains.
b = b.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")

with io.open(os.path.join(LAUNCH_DIR, name + ".launch"), "wb") as f:
    f.write(b)
shutil.copyfile(
    os.path.join(LAUNCH_DIR, TEMPLATE + ".jlink"),
    os.path.join(LAUNCH_DIR, name + ".jlink"),
)

# Sanity check: every image path in the result must sit under one of the two directories
# asked for. Substring tests on the build-dir names give false positives - a new SPE path may
# legitimately contain the template's name - so check the paths themselves.
paths = re.findall(rb"[A-Za-z]:" + re.escape(BS.encode()) + rb"[^\"<>|]*?" + re.escape(BS.encode()) + rb".(?:elf|bin)", b)
stray = sorted({p.decode() for p in paths
                if not p.startswith(spe.encode()) and not p.startswith(ns.encode())})
print("%s -> spe %s | ns %s" % (name, spe, ns))
for s in stray:
    print("   unexpected image path:", s)
