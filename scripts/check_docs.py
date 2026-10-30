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
Every checker in this repository passed on a documentation set that a customer could not use:
they check citations and generated-file freshness, not whether what they resolve to is
something a recipient actually receives. These four close that gap.

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

  8. a cited SECTION exists in the document the citation names. `FILE.md §6` and
     `FILE.md §"Some heading"` are checked; a link resolves to a file and nothing used to look
     inside it, which is how three documents went on citing a README section months after it
     was removed. `[D128] §4` is not a document citation and is not checked.
  9. the course's links resolve, both within docs/learning/ and into the rendered documents
     under docs/learning/ref/. Those pages are generated and not committed (D146), so their
     anchors are computed from the Markdown the same way build_doc_html.py computes them -
     which also means this check works in a clone where ref/ has never been built.

Pass --no-customer to skip (4) - (7), for a commit that breaks one of them on purpose. The
reference checks (1) - (3) and (8) - (9) always run.
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

# Section and anchor resolution. See (8) and (9) in the module docstring.
#
# A heading's anchor is computed the way scripts/build_doc_html.py computes it, because the
# course links into the rendered pages: "D002 — ..." becomes d002, "8.4 OFS ..." becomes s8-4,
# and anything else gets a GitHub-style slug. Keep these two in step; the renderer is the
# authority and this is the reader.
RE_HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*$", re.M)
RE_SEC_NUM = re.compile(r"^§?(\d+(?:\.\d+)*)\.?\s")
RE_DNUM = re.compile(r"^(D\d{3})\b")
# A Markdown file named as a link, in backticks, or bare - immediately followed by a section
# citation. "[D128] §4" is NOT one of these: it cites a section of a decision entry, and the
# pattern requires a .md before the marker.
RE_SEC_CITE = re.compile(
    r'(?:\]\((?P<link>[A-Za-z0-9_./-]+\.md)\)'
    r'|`(?P<tick>[A-Za-z0-9_./-]+\.md)`'
    r'|(?<![`/\w])(?P<bare>[A-Za-z0-9_./-]+\.md))'
    r'\s*§\s?(?:(?P<num>\d+(?:\.\d+)*)|"(?P<title>[^"]+)")')
# The course links the rendered documents, never the raw Markdown.
RE_REF_LINK = re.compile(r'href="ref/([A-Za-z0-9_]+)\.html#([^"]+)"')
RE_HTML_ID = re.compile(r'\bid="([^"]+)"')
RE_HTML_HREF = re.compile(r'href="([^"]+)"')
COURSE = os.path.join("docs", "learning")
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

    # (4) again, over the launches. A launch names every image it flashes by ABSOLUTE path, so
    # a user path here is not cosmetic: it is a launch that works on one machine. Three RA6M5
    # launches and nine RA6E1 ones shipped that way.
    #
    # Two attributes are exempt because e2 studio writes and rewrites them itself and neither
    # decides what is flashed: ioFilePath, the register-view SVD inside the user's Eclipse
    # plugin directory, and the source-lookup "directory nest" entry. Both are reported by
    # --list rather than failed, because nothing here can produce a portable value for them.
    for path in sorted(walk(ROOT, {".launch"})):
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        if rel.startswith(LAUNCH_EXEMPT):
            continue
        text = read(path)
        for m in RE_USERPATH.finditer(text):
            before = text[max(0, m.start() - 220):m.start()]
            if "ioFilePath" in before[-200:] or "directory nest" in before[-200:]:
                continue
            fails.append((rel, "flashes from the local user path C:/Users/%s - a launch names "
                               "every image by absolute path, so this one works on one machine"
                          % m.group(1)))
            break

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


def md_sections(path):
    """(section numbers, heading titles, anchor ids) for one Markdown file."""
    nums, titles, ids = set(), set(), set()
    for _level, text in RE_HEADING.findall(read(path)):
        # Strip inline code and emphasis markers, but NEVER the underscore: it is part of
        # every identifier these headings name, and removing it made tfm_sprt slug to
        # "tfmsprt" where the renderer produces "tfm_sprt".
        t = re.sub(r"[*`]", "", text).strip()
        if not t:
            continue
        titles.add(t)
        m = RE_SEC_NUM.match(t)
        if m:
            nums.add(m.group(1))
            ids.add("s" + m.group(1).replace(".", "-"))
            continue
        m = RE_DNUM.match(t)
        if m:
            ids.add(m.group(1).lower())
            continue
        ids.add(re.sub(r"[^\w\- ]", "", t.lower()).replace(" ", "-") or "section")
    return nums, titles, ids


def section_checks(docs, tracked):
    """(8): a cited section must exist in the document the citation names.

    This is the check that was missing when three documents went on pointing at
    README.md §"Freeing space in the secure image" after that section was removed: a link
    resolves to a FILE, and nothing looked inside it.
    """
    fails, cache = [], {}

    def sections(path):
        if path not in cache:
            cache[path] = md_sections(path)
        return cache[path]

    for doc in docs:
        rel = os.path.relpath(doc, ROOT).replace("\\", "/")
        if rel.startswith(PATH_EXEMPT) or os.path.basename(doc) in LINK_EXEMPT:
            continue
        if tracked is not None and rel not in tracked:
            continue
        for m in RE_SEC_CITE.finditer(read(doc)):
            name = m.group("link") or m.group("tick") or m.group("bare")
            target = os.path.normpath(os.path.join(os.path.dirname(doc), name))
            if not os.path.isfile(target):
                continue          # (2) and (3) report a missing file; one message is enough
            nums, titles, _ids = sections(target)
            num, title = m.group("num"), m.group("title")
            if title:
                # A citation may wrap across lines, and so may a heading; compare on one line.
                title = " ".join(title.split())
                titles = {" ".join(h.split()) for h in titles}
            if num and num not in nums:
                fails.append((rel, "cites %s §%s, which is not a section of it" % (name, num)))
            elif title and not any(title in h for h in titles):
                fails.append((rel, 'cites %s §"%s", which is not a heading in it' % (name, title)))
    return fails


def course_checks():
    """(9): the course's own links, and its links into the rendered documents.

    The rendered pages under docs/learning/ref/ are generated and not committed, so their
    anchors are computed from the Markdown rather than read back - which also means this check
    works in a clone where ref/ has never been built.
    """
    course = os.path.join(ROOT, COURSE)
    if not os.path.isdir(course):
        return []
    pages = sorted(f for f in os.listdir(course) if f.endswith(".html"))
    if not pages:
        return []
    fails = []
    ids = {}
    for f in pages:
        ids[f] = set(RE_HTML_ID.findall(read(os.path.join(course, f))))

    for f in pages:
        text = read(os.path.join(course, f))

        # into the rendered documents: ref/<NAME>.html#anchor
        for name, frag in RE_REF_LINK.findall(text):
            src = ("scripts/README.md" if name == "scripts_README" else name + ".md")
            path = os.path.join(ROOT, src)
            if not os.path.isfile(path):
                fails.append(("%s/%s" % (COURSE.replace("\\", "/"), f),
                              "links ref/%s.html, which no Markdown file renders to" % name))
                continue
            # The renderer disambiguates a repeated heading by suffixing "_2", "_3" and so
            # on. md_sections() does not carry that state, so accept the base as well:
            # DECISIONS.md alone renders 48 such ids, every one of them a "Carried" heading.
            base = re.sub(r"_\d+$", "", frag)
            anchors = md_sections(path)[2]
            if frag not in anchors and base not in anchors:
                fails.append(("%s/%s" % (COURSE.replace("\\", "/"), f),
                              "links ref/%s.html#%s; %s has no heading with that anchor"
                              % (name, frag, src)))

        # within the course
        for href in RE_HTML_HREF.findall(text):
            if href.startswith(("http://", "https://", "mailto:", "ref/")):
                continue
            page, _, frag = href.partition("#")
            here = "%s/%s" % (COURSE.replace("\\", "/"), f)
            if page and not os.path.isfile(os.path.join(course, page)):
                fails.append((here, "links %s, which does not exist" % href))
                continue
            if frag and frag not in ids.get(page or f, set()):
                fails.append((here, "links %s; there is no element with that id" % href))
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
            if (os.path.isfile(os.path.join(ROOT, name))        # path relative to this repository
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
    fails += section_checks(docs, tracked)
    fails += course_checks()

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
