#!/usr/bin/env python3
"""Extract supersession threads from DECISIONS.md.

    python scripts/decision_threads.py              # the thread worksheet
    python scripts/decision_threads.py --status     # propose Status-line back-annotations
    python scripts/decision_threads.py --status --apply

WHAT IT IS FOR
--------------
DECISIONS.md is append-only and 111 entries long. Two things get lost in it:

  1. Which entries are still live. Rule 2 says a superseded entry gets `Status: Superseded by
     Dyyy`, and ONE of twenty threads carries it (D001). --status fixes that.
  2. What the settled answer to a question is, without walking the chain. The worksheet feeds
     the `## Settled questions` table at the top of the file; the one-line answers are written
     by hand, see THE LIMIT below.

STRONG VERSUS WEAK CITATIONS
----------------------------
Only `supersedes` and `withdrawn` mean "that decision is no longer in force". `closes`,
`refines`, `corrects` and `extends` link entries without retiring them, so they build the
thread but never produce a Status change. Getting this wrong would mark live entries dead.

THE LIMIT, WHICH IS NOT FIXABLE HERE
------------------------------------
A thread is not a question. D092 says "**Corrects** a claim made about [D091]'s
`bsp_security.c` reading" - it fixes one sentence inside D091 and then discusses clock
security, an unrelated subject. D091's decision stands. Graph-walking cannot tell "this
reverses that decision" from "this fixes a sentence in that entry", because the record uses
the same verbs for both, so threads OVER-MERGE.

Treat the output as a worksheet of candidates. The unit of a table row is a QUESTION; where a
thread and a question disagree, the question wins and the thread gets split by hand.
"""
import argparse
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "DECISIONS.md")

STRONG = r"supersed\w*|withdraw\w*"
WEAK = r"corrects?|refines?|closes?|replaces?|obsolet\w*|extends?"
RE_ENTRY = re.compile(r"^## (D\d+) — (.+)$", re.M)


def parse():
    s = io.open(PATH, encoding="utf-8", errors="replace").read()
    parts = re.split(r"^## (D\d+) — (.+)$", s, flags=re.M)
    order, ents = [], {}
    for i in range(1, len(parts), 3):
        order.append(parts[i])
        ents[parts[i]] = (parts[i + 1], parts[i + 2])
    return s, order, ents


def edges_for(head, ents, self_id, verbs, want_partial=False):
    """Every D-number cited after a matching verb, not just the first.

    D091 reads '**Supersedes** [D079], [D082] and [D090]' - one verb, three targets. Taking
    only the first lost two edges and split one 8-entry thread into two, which is what made
    the first worksheet wrong.

    Two forms must NOT become a plain edge, and both were found by dry-running this:

      PASSIVE.  D001 reads 'Status: Superseded by D002'. Here self is the TARGET, not the
                source; reading it as an edge marked the live D002 as superseded BY the entry
                it replaced - exactly backwards.
      PARTIAL.  D044 reads 'Supersedes the second fix in [D041]'. D041's other fix is still
                in force, and a Status field cannot say 'half superseded'. An earlier version
                tried to DETECT this from the words between verb and citation; it misfired on
                D052, D075 and D085, which are clean. Detecting intent from prose is the wrong
                job for a script, so --status now PRINTS THE CITING TEXT for every proposed
                change and a human reads eleven lines.

    Returns (edges, [(target, citing text)]).
    """
    out, partial = [], []
    for m in re.finditer(verbs, head, re.I):
        # Passive: "superseded by Dxxx" - self is the target. Not an outgoing edge.
        if re.match(r"\w*\s+by\b", head[m.end():m.end() + 12], re.I):
            continue
        tail = head[m.end():m.end() + 120]
        tail = re.split(r"(?<=[.;])\s", tail)[0]
        for mt in re.finditer(r"\[?(D\d{3})\]?", tail):
            t = mt.group(1)
            if t not in ents or t == self_id:
                continue
            if t not in out:
                out.append(t)
                partial.append((t, re.sub(r"\s+", " ", (head[max(0, m.start()-0):m.end()]
                                                        + tail[:mt.end()]).strip())))
    return (out, partial) if want_partial else out


def build(ents, order):
    strong, weak, partials = [], [], []
    for d in order:
        title, body = ents[d]
        head = title + "\n" + "\n".join(body.strip().split("\n")[:3])
        s_e, s_p = edges_for(head, ents, d, STRONG, want_partial=True)
        for t in s_e:
            strong.append((d, t))
        for t in s_p:
            partials.append((d, t))
        w_e, _ = edges_for(head, ents, d, WEAK, want_partial=True)
        for t in w_e:
            if (d, t) not in strong:
                weak.append((d, t))
    return strong, weak, partials


def threads(all_edges):
    nodes = {x for e in all_edges for x in e}
    seen, out = set(), []
    for r in sorted(nodes, key=lambda x: int(x[1:])):
        if r in seen:
            continue
        comp, stack = set(), [r]
        while stack:
            n = stack.pop()
            if n in comp:
                continue
            comp.add(n)
            for a, b in all_edges:
                if a == n and b not in comp:
                    stack.append(b)
                if b == n and a not in comp:
                    stack.append(a)
        seen |= comp
        out.append(sorted(comp, key=lambda x: int(x[1:])))
    out.sort(key=lambda c: (-len(c), int(c[-1][1:])))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--status", action="store_true", help="propose Status back-annotations")
    ap.add_argument("--apply", action="store_true", help="write them")
    ap.add_argument("--exclude", default="", metavar="D041,D0xx",
                    help="entries to leave alone - use for PARTIAL supersessions, which a "
                         "Status field cannot express")
    a = ap.parse_args()

    s, order, ents = parse()
    strong, weak, partials = build(ents, order)

    if not a.status:
        th = threads(strong + weak)
        print("| # | Thread | Settled by | Settled position — WRITTEN BY HAND |")
        print("|---|---|---|---|")
        for i, c in enumerate(th, 1):
            print(f"| {i} | {' -> '.join(c)} | **{c[-1]}** | |")
        print(f"\n{len(th)} threads, {sum(len(c) for c in th)} of {len(ents)} entries")
        print(f"{len(strong)} strong edges (retire), {len(weak)} weak (link only)")
        print("\nRemember: a thread is not a question. See the module docstring.")
        return 0

    # Status back-annotation, strong edges only.
    by_target = {}
    for src, tgt in strong:
        by_target.setdefault(tgt, []).append(src)

    changes, skipped = [], []
    for tgt, srcs in sorted(by_target.items(), key=lambda kv: int(kv[0][1:])):
        body = ents[tgt][1]
        m = re.search(r"\*\*Status:\*\*\s*Accepted", body)
        if not m:
            cur = re.search(r"\*\*Status:\*\*\s*([^·\n]+)", body)
            skipped.append((tgt, (cur.group(1).strip() if cur else "?")))
            continue
        if tgt in {x.strip() for x in a.exclude.split(",") if x.strip()}:
            skipped.append((tgt, "excluded by --exclude (partial supersession)"))
            continue
        newest = max(srcs, key=lambda x: int(x[1:]))
        changes.append((tgt, newest, sorted(srcs, key=lambda x: int(x[1:]))))

    ev = {}
    for src, (tgt, text) in partials:
        ev.setdefault(tgt, []).append((src, text))
    for tgt, newest, srcs in changes:
        extra = f"  (also cited by {', '.join(x for x in srcs if x != newest)})" if len(srcs) > 1 else ""
        print(f"  {tgt}: Accepted -> Superseded by {newest}{extra}")
        for src, text in ev.get(tgt, []):
            print(f"        {src} says: \"{text[:100]}\"")
        if len(ev.get(tgt, [])) == 1 and re.search(r"supersed\w*\s*\**\s*\[?D\d{3}",
                                                   ev[tgt][0][1], re.I):
            pass            # plain "Supersedes [Dxxx]" - nothing to weigh
        else:
            print("        ^ weigh this: is the WHOLE entry superseded, or only part of it?")
    for tgt, cur in skipped:
        print(f"  {tgt}: left alone, Status is already '{cur}'")

    print(f"\n{len(changes)} to change, {len(skipped)} already marked or non-standard")

    if not a.apply:
        print("\n(dry run — pass --apply to write)")
        return 0

    out = s
    for tgt, newest, _ in changes:
        pat = re.compile(r"(^## " + tgt + r" — .+?\*\*Status:\*\*\s*)Accepted", re.M | re.S)
        out, n = pat.subn(r"\1Superseded by " + newest, out, count=1)
        if n != 1:
            print(f"  FAILED to rewrite {tgt}", file=sys.stderr)
            return 1
    io.open(PATH, "w", encoding="utf-8", newline="").write(out)
    print(f"\napplied {len(changes)} Status updates")
    return 0


if __name__ == "__main__":
    sys.exit(main())
