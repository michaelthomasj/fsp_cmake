#!/usr/bin/env python3
"""Clone an e2 debug launch, repointing it at a different pair of build directories.

    python scripts/mk_level_launch.py <source.launch> <old-spe> <old-ns> <new-spe> <new-ns> <new-name>

    python scripts/mk_level_launch.py \\
        ra6m5_gcc_nonsecure/ra6m5_TFM_flih_gcc.launch \\
        m5gflih m5gflihns m5gl2 m5gl2ns \\
        ra6m5_TFM_flih_L2_gcc

WHAT IT IS FOR
--------------
The launches hard-code their build output, e.g. C:\\b\\m5gflih\\build-spe\\bin\\bl2.elf and
C:\\b\\m5gflihns\\bin\\tfm_ns_signed.bin. Running the same suite at a different isolation level
means a different build tree, which means a different launch - and hand-editing seven
occurrences of two directory names across a 200-line XML file is how a launch ends up flashing
one level's secure image against another level's non-secure one. That failure is silent: both
images are valid and signed, BL2 boots them, and the suite reports whatever the mismatch
produces.

WHY NOT JUST REBUILD IN PLACE
-----------------------------
Because the isolation-1 trees are the reference the decision log cites. Overwriting them means
the next comparison has nothing to compare against - the lesson of [D084].

WHAT IT REFUSES
---------------
  - a substitution that changes nothing (wrong old-dir names, silently producing a copy that
    still points at the source build)
  - an existing destination, unless --force
  - setTZBoundaries true anywhere in the result; flashing with it set is a brick hazard, and
    mk_iar_launches.py refuses on the same grounds
"""
import argparse
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source", help="launch file to clone, relative to the repo root")
    ap.add_argument("old_spe", help="SPE build dir basename in the source, e.g. m5gflih")
    ap.add_argument("old_ns", help="NS build dir basename in the source, e.g. m5gflihns")
    ap.add_argument("new_spe", help="replacement SPE build dir basename")
    ap.add_argument("new_ns", help="replacement NS build dir basename")
    ap.add_argument("new_name", help="new launch name, without the .launch suffix")
    ap.add_argument("--force", action="store_true", help="overwrite an existing destination")
    a = ap.parse_args()

    src = os.path.join(ROOT, a.source)
    if not os.path.isfile(src):
        print("no such launch: %s" % src, file=sys.stderr)
        return 1

    s = io.open(src, encoding="utf-8", newline="").read()

    # Longest first: m5gflihns contains m5gflih, so replacing the short one first would
    # turn m5gflihns into m5gl2ns-ns. Order matters and this is the whole reason for the sort.
    pairs = sorted([(a.old_ns, a.new_ns), (a.old_spe, a.new_spe)],
                   key=lambda p: -len(p[0]))

    total = 0
    for old, new in pairs:
        n = s.count(old)
        if n:
            s = s.replace(old, new)
            total += n
        print("  %-12s -> %-12s %d occurrence(s)" % (old, new, n))

    if total == 0:
        print("REFUSED: no occurrences of either build dir - the clone would still point at "
              "the source build. Check the old-dir names against the launch.", file=sys.stderr)
        return 1

    # setTZBoundaries is PER DEBUG PROBE. A launch carries one key per supported probe, e.g.
    #     com.renesas.hardwaredebug.arm.e2lite.setTZBoundaries
    #     com.renesas.hardwaredebug.arm.jlink.setTZBoundaries
    # and only the selected probe's key does anything. Every RA8M2 GCC launch in this repo has
    # the e2lite key true and the jlink key false, with "J-Link ARM" selected - so the live
    # setting is false and the true one is inert. An earlier version of this script refused on
    # any true value, which is the wrong call twice over: it blocks a clone whose active key is
    # already safe, and it leaves the inert key true for whoever later switches probe.
    #
    # Normalise instead. Flashing with boundaries set rewrites the TrustZone partitioning from
    # the project's settings, and the standing rule for this port is that it stays off for
    # every probe, not just the one currently wired up.
    live_probe = "jlink" if "J-Link" in s else None
    for m in re.finditer(r'arm\.(\w+)\.setTZBoundaries" value="(\w+)"', s):
        probe, val = m.group(1), m.group(2)
        flag = " <-- SELECTED PROBE" if probe == live_probe else " (inert, probe not selected)"
        print("  setTZBoundaries[%s] = %s%s" % (probe, val, flag))

    s, n_tz = re.subn(r'(arm\.\w+\.setTZBoundaries" value=")true(")', r'\1false\2', s)
    if n_tz:
        print("  normalised %d setTZBoundaries key(s) to false" % n_tz)

    dst = os.path.join(os.path.dirname(src), a.new_name + ".launch")
    if os.path.exists(dst) and not a.force:
        print("REFUSED: %s exists (pass --force)" % dst, file=sys.stderr)
        return 1

    io.open(dst, "w", encoding="utf-8", newline="").write(s)
    print("wrote %s" % os.path.relpath(dst, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
