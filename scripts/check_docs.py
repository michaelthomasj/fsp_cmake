#!/usr/bin/env python3
r"""Verify that documentation cross-references still resolve.

    python scripts/check_docs.py            # check, exit 1 on any failure
    python scripts/check_docs.py --quiet    # only print failures
    python scripts/check_docs.py --list     # show what is being checked, then check

Exit codes:  0 everything resolves   1 at least one broken reference   2 bad usage

WHY THIS EXISTS
---------------
Four stale cross-references were found in a single day, every one by accident rather than by
checking:

  * DECISIONS.md D094 cited three entries by the wrong number.
  * RA8M2_SOLUTION.md described the FSP MCUboot backend months after D091 removed it.
  * app_build_ra8m2_iar.bat said the two project sets were out of sync after they had been
    reconciled.
  * NINETEEN .cmake and CMakeLists.txt files pointed at fsp_cmake/TFM_INTEGRATION_COMPLETE.md,
    a path that has never existed at that location - including the text of a build-time
    WARNING, so the build told you to read a file that was not there.

Only the last class is mechanically detectable, and it was the largest. This checks the three
things that are:

  1. every D### cited anywhere resolves to an entry in DECISIONS.md
  2. every relative .md link in a document resolves to a file
  3. every .md filename mentioned in a .cmake / CMakeLists.txt comment resolves

DECISIONS.md IS EXEMPT FROM (2) AND (3), BY DESIGN
--------------------------------------------------
It is append-only: entries are superseded, never edited. A reference in an old entry to a file
that has since been retired is a historical fact, not a broken link - MACHINE_HANDOFF.md is
cited six times there and was deleted on 2026-10-09. Link-checking it would make this tool
permanently noisy, and a noisy checker gets ignored, which is worse than not having one.

D-number citations (1) ARE checked inside DECISIONS.md, because a D number cannot become
D-number citations (1) ARE checked inside DECISIONS.md, because a D number cannot become
historically correct - either the entry exists or the citation is wrong.

CUSTOMER READINESS (4) - (7)
----------------------------
The five checkers in this repository all passed on a documentation set that a customer could
not use: they check citations and generated-file freshness, not whether what they resolve to
is something a recipient actually receives. These four close that gap.

  4. no shipped document names a local user path. C:\Users\<you> is the documented placeholder
     and is allowed; a real account name is a leak, and it is also an instruction a reader
     cannot follow.
  5. every link target is TRACKED IN GIT. A link that resolves on the author's disk and not in
     a clone is the failure this catches twice over: a file never committed (TEST_RESULTS.md
     was linked from README.md while untracked) and a file deliberately withheld - D146
     gitignored six maintainer documents, which stay on disk, so os.path.isfile still finds
     them.
  6. decision-ID density stays under DENSITY_LIMIT per 1000 words. A decision ID may follow a
     self-contained sentence; it is never the explanation. Three documents are exempt because
     being an index into the log is their stated job: DECISIONS.md itself, the SETTLED.md index
     generated from it, and TEST_RESULTS.md, whose first paragraph says it adds no result of
     its own and cites the entry that recorded each run.
  7. no shipped launch configuration sets setTZBoundaries true, for ANY probe. The key is per
     probe, only the selected one acts, and an inert true arms itself the moment someone
     switches probe. e2_baseline/ is exempt: it shows the unmodified e2 output on purpose and
     its README says not to launch from it.

Pass --no-customer to run only (1) - (3), for a commit that breaks one of these on purpose.
"""
import argparse
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TFM = os.path.normpath(os.path.join(ROOT, "..", "trusted-firmware-m",
                                    "platform", "ext", "target", "renesas"))

DECISIONS = "DECISIONS.md"
SKIP_DIRS = {"archive", ".git", "node_modules", "__pycache__"}
# Append-only: see the module docstring.
LINK_EXEMPT = {DECISIONS}
# Review artifacts are point-in-time snapshots by outside reviewers. They legitimately cite
# entries that do not exist yet ("needs a superseding entry (D120)") and files as they were on the
# review date, so they are not held to resolution. Checking them blocked every .md commit until
# someone wrote the entry a review merely proposed.
PATH_EXEMPT = ("docs/artifacts",          # docs/artifacts/, docs/artifacts_v2/, ...
               "docs/General_tech_review")  # the 2026-10 port and upstream-comparison reviews

# Customer-readiness configuration. See (4) - (7) in the module docstring.
#
# DENSITY_LIMIT is one decision ID every ~67 words. The documents that sat just under it when
# this was written were TROUBLESHOOTING.md and PORTING.md at 14.5, so the limit is live rather
# than decorative; the three index documents below are the only ones above it.
DENSITY_LIMIT = 15.0
DENSITY_EXEMPT = {DECISIONS, "SETTLED.md", "TEST_RESULTS.md"}
LAUNCH_EXEMPT = ("e2_baseline/",)
# C:\Users\<you> is the placeholder GETTING_STARTED.md uses. Anything else after C:\Users\ is
# somebody's account name.
RE_USERPATH = re.compile(r"[Cc]:[\\/]Users[\\/](?!<)([A-Za-z0-9._-]+)")
RE_TZ_TRUE = re.compile(r'setTZBoundaries" value="true"')

RE_ENTRY = re.compile(r"^## (D\d+) — ", re.M)
RE_CITE = re.compile(r"\bD(\d{3})\b")
RE_MDLINK = re.compile(r"\]\(([^)#][^)]*\.md)\)")
RE_MDNAME = re.compile(r"\b([A-Za-z0-9_./-]+\.md)\b")


def walk(base, exts):
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if os.path.splitext(fn)[1] in exts:
                yield os.path.join(dirpath, fn)


def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def tracked_files():
    """Paths git tracks, repo-relative with forward slashes. Empty set if git is unavailable."""
    try:
        out = subprocess.check_output(["git", "-C", ROOT, "ls-files"],
                                      stderr=subprocess.DEVNULL).decode("utf-8", "replace")
    except (OSError, subprocess.CalledProcessError):
        return None
    return {line.strip() for line in out.splitlines() if line.strip()}


def customer_checks(docs, tracked):
    """(4) - (7) in the module docstring. Returns a list of (where, what)."""
    fails = []

    for path in docs:
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        if rel.startswith(PATH_EXEMPT) or os.path.basename(path) == DECISIONS:
            continue
        # A document the repository does not track is not shipped, so it is not held to any
        # of this. The six documents D146 withheld are still on disk and would otherwise be
        # checked - and fail, because they link each other.
        if tracked is not None and rel not in tracked:
            continue
        text = read(path)

        # (4) local user paths
        for who in sorted(set(RE_USERPATH.findall(text))):
            fails.append((rel, "names the local user path C:/Users/%s - a reader cannot "
                               "follow it, and it is a leak" % who))

        # (6) decision-ID density
        if os.path.basename(path) not in DENSITY_EXEMPT:
            words = len(text.split())
            cites = len(RE_CITE.findall(text))
            if words:
                density = cites * 1000.0 / words
                if density > DENSITY_LIMIT:
                    fails.append((rel, "cites %d decision IDs in %d words, %.1f per 1000 "
                                       "against a limit of %.0f - an ID may follow a "
                                       "self-contained sentence but is never the explanation"
                                  % (cites, words, density, DENSITY_LIMIT)))

        # (5) link targets must be tracked, not merely present on disk
        if tracked is None or os.path.basename(path) in LINK_EXEMPT:
            continue
        for link in sorted(set(RE_MDLINK.findall(text))):
            if link.startswith(("http://", "https://")):
                continue
            target = os.path.normpath(os.path.join(os.path.dirname(rel), link))
            target = target.replace("\\", "/")
            if target.startswith("../"):
                continue          # the other repository; (3) covers what it can
            if target not in tracked:
                fails.append((rel, "links %s, which is not tracked in git - it resolves on "
                                   "this disk and not in a clone" % link))

    # (7) setTZBoundaries
    for path in sorted(walk(ROOT, {".launch"})):
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        if rel.startswith(LAUNCH_EXEMPT):
            continue
        n = len(RE_TZ_TRUE.findall(read(path)))
        if n:
            fails.append((rel, "sets setTZBoundaries true for %d probe(s). Only the selected "
                               "probe acts, so an inert true arms itself when the probe is "
                               "switched" % n))
    return fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--no-customer", action="store_true",
                    help="skip the customer-readiness checks (4)-(7)")
    a = ap.parse_args()

    dec_path = os.path.join(ROOT, DECISIONS)
    if not os.path.isfile(dec_path):
        print(f"check_docs: {DECISIONS} not found at {ROOT}", file=sys.stderr)
        return 2
    entries = set(RE_ENTRY.findall(read(dec_path)))

    docs = sorted(walk(ROOT, {".md"}))
    builds = sorted(walk(TFM, {".cmake", ".txt"})) if os.path.isdir(TFM) else []
    if a.list:
        print(f"{len(entries)} decision entries")
        print(f"{len(docs)} markdown files under {ROOT}")
        print(f"{len(builds)} build files under {TFM}\n")

    fails = []

    for path in docs:
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        if rel.startswith(PATH_EXEMPT):
            continue
        text = read(path)

        for num in sorted(set(RE_CITE.findall(text)), key=int):
            if f"D{num}" not in entries:
                fails.append((rel, f"cites D{num}, which is not an entry in {DECISIONS}"))

        if os.path.basename(path) in LINK_EXEMPT:
            continue
        for link in sorted(set(RE_MDLINK.findall(text))):
            if link.startswith(("http://", "https://")):
                continue
            if not os.path.isfile(os.path.join(os.path.dirname(path), link)):
                fails.append((rel, f"link to {link} does not resolve"))

    # Build files: a .md named in a comment must exist, in this repo or beside the file.
    for path in builds:
        rel = os.path.relpath(path, TFM).replace("\\", "/")
        for name in sorted(set(RE_MDNAME.findall(read(path)))):
            bare = os.path.basename(name)
            if (os.path.isfile(os.path.join(ROOT, name))        # path relative to fsp_cmake
                    or os.path.isfile(os.path.join(ROOT, bare))  # bare name at its root
                    or os.path.isfile(os.path.join(os.path.dirname(path), bare))
                    or os.path.isfile(os.path.join(TFM, name))):
                continue
            fails.append((f"[tfm] {rel}", f"names {name}, which does not exist"))

    tracked = None
    if not a.no_customer:
        tracked = tracked_files()
        if tracked is None and not a.quiet:
            print("check_docs: git unavailable - link targets checked on disk only")
        fails += customer_checks(docs, tracked)

    if fails:
        print(f"check_docs: {len(fails)} broken reference(s)\n")
        for where, what in fails:
            print(f"  {where}: {what}")
        return 1

    if not a.quiet:
        n_exempt = sum(1 for p in docs
                       if os.path.relpath(p, ROOT).replace("\\", "/").startswith(PATH_EXEMPT))
        extra = "" if a.no_customer else ", customer-readiness checks pass"
        print(f"check_docs: ok — {len(entries)} entries, {len(docs) - n_exempt} docs checked "
              f"({n_exempt} review snapshots exempt), {len(builds)} build files, "
              f"all references resolve{extra}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
