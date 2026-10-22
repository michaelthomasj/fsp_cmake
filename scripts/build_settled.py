# -*- coding: utf-8 -*-
"""Generate SETTLED.md from DECISIONS.md.

    python scripts/build_settled.py            # write SETTLED.md
    python scripts/build_settled.py --check    # exit 1 if it is stale, write nothing

Exit codes:  0 up to date / written   1 --check found drift   2 parse error

WHY THIS IS GENERATED AND NOT WRITTEN

DECISIONS.md is append-only, so a position is stated by the newest entry in its thread and
the earlier ones stay as the reasoning. That is right for the record and wrong for a reader
who only wants to know what is true now: by D126 one defect had eight entries, and the first
of them is wrong in ways only the eighth explains.

A hand-maintained index of 126 entries drifts - an external review found 157 stale claims
across this document set in one pass, most of them a decision that was taken and never
carried out of the log. So this file is derived, and the pre-commit hook fails on drift.

WHAT IT CAN AND CANNOT SAY

Entry titles in this log are written as assertions ("the isolation-macro gap is this port's,
not upstream's"), so listing the current entry's title per thread gives a usable statement of
position without inventing prose. What it CANNOT generate is the curated paragraph that
explains a position in context - that is the hand-written "Settled questions" table at the top
of DECISIONS.md, which stays, and is the right place for the threads that need more than a
title.

Output is deterministic - no timestamps - so --check is a byte comparison.
"""
import argparse
import io
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "DECISIONS.md")
OUT = os.path.join(ROOT, "SETTLED.md")

MID = u"\u00b7"
DISPLACING = ("Supersedes", "Corrects")      # these change what an earlier entry asserts
CLOSING = ("Closes",)                        # these change an earlier entry's STATUS, not its claims
ADDITIVE = ("Builds on",)                    # these do nothing to the earlier entry

# WHY "Closes" IS ITS OWN RELATION
#
# Three entries carry a status that was true when written and is not true now: D008 and D014
# are "Provisional", D029's title is literally "OPEN DEFECT". Each was closed by a later entry
# - D015, D017, D048 - which recorded it as "Builds on", the one relation that says the earlier
# entry is untouched. So this file listed "OPEN DEFECT: .ram_from_flash is excluded from
# copy-init" in the Standing table with its title as the current position, five weeks after
# D048 fixed it. That is the worst failure this index can have: not a stale detail, but
# pointing a reader at a closed defect as live.
#
# Closes is not Supersedes: the entry is not replaced and its reasoning is still the account of
# the problem. It is not Corrects either: nothing in it was wrong. And like Corrects it must not
# join a lineage - D029 and D048 answer different questions.


def parse(text):
    """-> list of dicts, source order."""
    lines = text.replace("\r\n", "\n").split("\n")
    heads = [i for i, l in enumerate(lines) if re.match(r"## D\d+", l)]
    out = []
    for n, i in enumerate(heads):
        end = heads[n + 1] if n + 1 < len(heads) else len(lines)
        m = re.match(r"## (D\d+)\s*[\u2014\u2013-]\s*(.*)$", lines[i])
        if not m:
            m2 = re.match(r"## (D\d+)\s*(.*)$", lines[i])
            if not m2:
                continue
            did, title = m2.group(1), m2.group(2)
        else:
            did, title = m.group(1), m.group(2)

        meta = ""
        for j in range(i + 1, min(i + 6, end)):
            if lines[j].startswith("**Date:**"):
                meta = lines[j]
                break

        e = {"id": did, "title": title.strip(), "line": i + 1,
             "date": "", "status": "", "rel": {}, "evidence": ""}
        d = re.search(r"\*\*Date:\*\*\s*([0-9]{4}-[0-9]{2}-[0-9]{2}|unknown)", meta)
        if d:
            e["date"] = d.group(1)
        parts = [p.strip() for p in re.split(u"[\u00b7\u2022]", meta) if p.strip()]
        for p in parts:
            s = re.match(r"\*\*Status:\*\*\s*(.*)$", p)
            if s:
                e["status"] = s.group(1).strip()
                continue
            for f in DISPLACING + CLOSING + ADDITIVE:
                r = re.match(r"\*\*%s:\*\*\s*(.*)$" % re.escape(f), p)
                if r:
                    e["rel"][f] = re.findall(r"D\d{3}", r.group(1))
            ev = re.match(r"\*\*Evidence:\*\*\s*(.*)$", p)
            if ev:
                e["evidence"] = ev.group(1).strip()
        out.append(e)
    return out


def build(entries):
    by = {e["id"]: e for e in entries}
    # who displaces whom
    displaced_by = {}
    for e in entries:
        for f in DISPLACING:
            for target in e["rel"].get(f, []):
                displaced_by.setdefault(target, []).append((e["id"], f))
    # a Status of "Superseded by Dxxx" counts too, even if the later entry is silent
    for e in entries:
        m = re.match(r"Superseded by (D\d+)", e["status"])
        if m and (m.group(1), "Supersedes") not in displaced_by.get(e["id"], []):
            displaced_by.setdefault(e["id"], []).append((m.group(1), "Supersedes"))
    return by, displaced_by


def threads(entries, by, displaced_by):
    """Lineages joined by **Supersedes only**, oldest -> newest.

    Corrects deliberately does NOT join a thread. A later entry often corrects one claim in
    an earlier one while answering a different question: D092 corrects a claim in D091 but is
    about RA8M2's first boot, not about which MCUboot backend to use. Merging on Corrects
    chained D075..D092 into a single "thread" and presented D092 as the current word on the
    flash map, which it is not. Supersedes means "this replaces that answer", and only that
    forms a lineage. Corrects edges appear per entry in the Displaced table instead.
    """
    parent = {e["id"]: e["id"] for e in entries}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[max(ra, rb)] = min(ra, rb)

    for tgt, srcs in displaced_by.items():
        if tgt not in parent:
            continue
        for sid, field in srcs:
            if sid in parent and field == "Supersedes":
                union(tgt, sid)
    groups = {}
    for e in entries:
        groups.setdefault(find(e["id"]), []).append(e["id"])
    return {k: sorted(v) for k, v in groups.items() if len(v) > 1}


def render(entries):
    by, displaced_by = build(entries)
    th = threads(entries, by, displaced_by)
    in_thread = {i for g in th.values() for i in g}
    # An entry is dead only if something SUPERSEDES it. Being corrected does not kill an
    # entry: D091 is corrected by D092 on one claim and is still the current word on which
    # MCUboot backend the port uses. Treating Corrects as fatal left that thread with no
    # standing entry at all, which is worse than useless - it hides the answer.
    superseded = {t: [(s, f) for s, f in v if f == "Supersedes"]
                  for t, v in displaced_by.items()}
    superseded = {t: v for t, v in superseded.items() if v}
    corrected = {t: [(s, f) for s, f in v if f == "Corrects"]
                 for t, v in displaced_by.items()}
    corrected = {t: v for t, v in corrected.items() if v}
    closed = {}
    for e in entries:
        for target in e["rel"].get("Closes", []):
            closed.setdefault(target, []).append(e["id"])
    live = [e for e in entries if e["id"] not in superseded]
    dead = [e for e in entries if e["id"] in superseded]

    L = []
    w = L.append
    w("# Settled positions")
    w("")
    w("**Generated from `DECISIONS.md` by `scripts/build_settled.py`. Do not edit"
      " \u2014 edits are overwritten and the pre-commit hook fails on drift.**")
    w("")
    w("`DECISIONS.md` is append-only, so the position on any question is stated by the"
      " newest entry in its thread and the earlier ones remain as the reasoning. This file"
      " says which entry that is. For the handful of questions that need a paragraph rather"
      " than a title, read the hand-written **Settled questions** table at the top of"
      " `DECISIONS.md`.")
    w("")
    w("| | |")
    w("|---|---|")
    w("| Entries | **%d** |" % len(entries))
    w("| Standing | **%d** |" % len(live))
    w("| Superseded | **%d** |" % len(dead))
    w("| Standing but corrected on some point | **%d** |"
      % len([e for e in live if e["id"] in corrected]))
    w("| Standing, but the question they left open is closed | **%d** |"
      % len([e for e in live if e["id"] in closed]))
    w("| Supersede lineages | **%d** |" % len(th))
    w("")
    w("---")
    w("")

    w("## Threads \u2014 read the entry in bold")
    w("")
    w("A later entry **supersedes** an earlier one: same question, newer answer. Citing"
      " anything but the bold entry means citing an answer that has been replaced."
      " *Corrections* are a different thing and do not appear here — they fix a claim"
      " without replacing the entry, and are listed against each entry below.")
    w("")
    w("| Thread | Stands | What moved |")
    w("|---|---|---|")
    for key in sorted(th, key=lambda k: min(th[k])):
        ids = th[key]
        cur = [i for i in ids if i not in superseded]
        chain = " \u2192 ".join(("**%s**" % i) if i in cur else i for i in ids)
        moves = []
        for i in ids:
            e = by[i]
            for f in DISPLACING:
                if e["rel"].get(f):
                    moves.append("%s %s %s" % (i, f.lower(),
                                               ", ".join(e["rel"][f])))
        w("| %s | %s | %s |" % (chain,
                                ", ".join("`%s`" % c for c in cur) or "\u2014",
                                "; ".join(moves) or "\u2014"))
    w("")
    w("---")
    w("")

    w("## Standing (%d)" % len(live))
    w("")
    w("Nothing supersedes these. The title is the position. Where a later entry corrects"
      " one, the correction is named - the entry stands apart from that. **Where the Closed"
      " by column is filled, read the status as historical:** the entry describes a problem"
      " that a later entry shut, so its own \"Open\" or \"Provisional\" is no longer true.")
    w("")
    w("| # | Date | Position | Status | Corrected by | Closed by |")
    w("|---|---|---|---|---|---|")
    for e in sorted(live, key=lambda x: x["id"]):
        corr = ", ".join("`%s`" % c for c in
                         sorted({s for s, _ in corrected.get(e["id"], [])}))
        shut = ", ".join("`%s`" % c for c in sorted(set(closed.get(e["id"], []))))
        st = e["status"] or "Accepted"
        if not st.startswith("Accepted"):
            st = "**%s**" % st
        if shut:
            st = "~~%s~~" % st          # struck through: it was true when written
        w("| `%s` | %s | %s | %s | %s | %s |"
          % (e["id"], e["date"], e["title"], st, corr or "—", shut or "—"))
    w("")
    w("---")
    w("")

    w("## Superseded (%d)" % len(dead))
    w("")
    w("Kept for the reasoning. **Do not cite one of these without reading what replaced"
      " it** \u2014 in several cases the later entry reverses the earlier claim outright.")
    w("")
    w("| # | Date | Position as stated then | Superseded by |")
    w("|---|---|---|---|")
    for e in sorted(dead, key=lambda x: x["id"]):
        sup = {s for s, _ in superseded[e["id"]]}
        who = ", ".join("`%s`" % s for s in sorted(sup))
        # D091 both supersedes D082/D079 and corrects D090 ("the configuration is superseded,
        # not the mechanism"). Both relations are real, but printing "superseded by D091 (also
        # corrected by D091)" says nothing the first half did not.
        also = sorted({s for s, _ in corrected.get(e["id"], [])} - sup)
        if also:
            who += " (also corrected by %s)" % ", ".join("`%s`" % c for c in also)
        w("| `%s` | %s | %s | %s |" % (e["id"], e["date"], e["title"], who))
    w("")
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--check", action="store_true",
                    help="report drift, write nothing")
    ap.add_argument("--staged", action="store_true",
                    help="read DECISIONS.md from the git index, not the working tree, and "
                         "stage the result; for the pre-commit hook")
    a = ap.parse_args()

    # From the INDEX under --staged. A partially staged DECISIONS.md would otherwise
    # generate a SETTLED.md describing content that is not in the commit.
    if a.staged:
        r = subprocess.run(["git", "show", ":DECISIONS.md"], cwd=ROOT,
                           capture_output=True)
        if r.returncode != 0:
            print("build_settled: DECISIONS.md is not staged; nothing to do")
            return 0
        src_text = r.stdout.decode("utf-8")
    else:
        src_text = io.open(SRC, encoding="utf-8", newline="").read()

    try:
        entries = parse(src_text)
    except Exception as exc:                                   # noqa: BLE001
        print("build_settled: cannot parse DECISIONS.md: %s" % exc)
        return 2
    if not entries:
        print("build_settled: parsed zero entries - refusing to write")
        return 2

    new = render(entries)
    old = ""
    if os.path.exists(OUT):
        old = io.open(OUT, encoding="utf-8", newline="").read().replace("\r\n", "\n")

    if a.check:
        if old != new:
            print("SETTLED.md is stale - run: python scripts/build_settled.py")
            return 1
        print("SETTLED.md up to date (%d entries)" % len(entries))
        return 0

    if old != new:
        io.open(OUT, "w", encoding="utf-8", newline="\n").write(new)
        print("wrote SETTLED.md  (%d entries)" % len(entries))
    else:
        print("SETTLED.md already current (%d entries)" % len(entries))

    if a.staged:
        # Stage it, so the commit cannot contain DECISIONS.md without the index that
        # describes it. Same contract the hook already applies to docs/learning/ref/.
        r = subprocess.run(["git", "add", "SETTLED.md"], cwd=ROOT,
                           capture_output=True, text=True)
        if r.returncode != 0:
            print("build_settled: could not stage SETTLED.md: %s" % r.stderr.strip())
            return 2
        print("staged SETTLED.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
