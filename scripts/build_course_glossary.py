#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate the "Decisions cited" table in docs/learning/glossary.html.

    python scripts/build_course_glossary.py            # rewrite the table
    python scripts/build_course_glossary.py --check    # exit 1 if it is stale, write nothing

Rows are every D### the course pages cite. Columns:

  * Subject  - a short course-oriented label from SUBJ below; an entry cited for the first
               time falls back to its DECISIONS.md title, with a warning to write a label.
  * Standing - taken from SETTLED.md (scripts/build_settled.py): "stands", "stands; corrected
               by ...", or "superseded by ...". This is why the table must be regenerated
               when SETTLED.md changes - build_doc_html.py warns when it is stale.
  * Used in  - which pages cite it.

Deterministic, so --check is a string comparison.
"""
import argparse
import collections
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COURSE = os.path.join(ROOT, "docs", "learning")
GLOSSARY = os.path.join(COURSE, "glossary.html")
PAGES = [("Start", "index.html"), ("0", "part0-primer.html"), ("1", "part1-privilege-mpu-faults.html"),
         ("2", "part2-trustzone.html"), ("3", "part3-tfm.html"), ("4", "part4-porting.html")]
HEAD = '<div class="table-wrap"><table>\n<tr><th>Entry</th><th>Subject</th>'
CAPTION = ('<p class="src">Generated from the D-numbers each page cites by '
           '<code>scripts/build_course_glossary.py</code>; "Standing" is from SETTLED.md. '
           '"Start" is the landing page; 0–4 are the parts.</p>')

SUBJ = {
    "D002": "OFS: one linker region per option group",
    "D034": "<code>BSP_CFG_EARLY_INIT</code> asserted at build time",
    "D054": "sector-size mismatch failing as <code>BOOT_EFLASH</code>",
    "D058": "the flat <code>.bin</code> as a second route to the brick",
    "D061": "secure interrupts on RA; ITNS + ICUSARG; vector table",
    "D063": "pinned CMSE veneers get their own MEMORY region",
    "D064": "BL2 masking interrupts; masked SVC → <code>HFSR.FORCED</code>",
    "D065": "flat-binary brick guard on every port",
    "D069": "weak symbol silently unrouting every secure interrupt",
    "D073": "RA8M2 MRAM alias chosen per offset",
    "D075": "BL2 must enable the SAU on RA8M2",
    "D076": "D075's code had been reverted",
    "D079": "BL2 took FSP's MCUboot flash backend",
    "D080": "attestation passing with no measurements",
    "D081": "measured boot confirmed on RA6M5 from the boot record",
    "D083": "PSA Arch builds: two fixes, one a stale IAR install path",
    "D087": "secure-slot headroom 1,693 B / 670 B",
    "D089": "D083's IAR path fix had covered only RA6M5",
    "D091": "TF-M's MCUboot backend, FSP's HAL behind <code>fa_driver</code>",
    "D092": "RA8M2 first boot: the <code>MSAR</code> BusFault",
    "D093": "<code>BSP_TZ_CFG_MSAR=0</code> workaround",
    "D094": "the RA6M4 brick: the killed field is unknown",
    "D096": "measured boot confirmed on RA8M2",
    "D100": "secondary slot below primary; BL2 and secure image share RAM",
    "D102": "RA8M2 IAR launches; <code>setTZBoundaries</code> appears twice",
    "D107": "BL2 silent under IAR: DLIB buffers stdout",
    "D108": "the real IAR console hook is <code>__dwrite</code>",
    "D112": "azone parity",
    "D113": "isolation 2 on silicon; measured MPU; four port defects; costs",
    "D114": "isolation 3; the second missing macro",
    "D115": "RA8M2 MPU measured at 8; corrects D114 on PXN; the hook that broke L1+IPC",
    "D116": "L1+IPC green on RA8M2",
    "D117": "six corrections: FLIH dispatch, L1+IPC mechanism, IDAU comments, PXN provenance, stale docs, upstream count",
    "D118": "RA8M2 isolation 2 green under IAR",
    "D119": "RA8M2 isolation 3 green under IAR; coverage table",
    "D120": "the isolation-macro gap is this port's, not upstream's; item 15 withdrawn; D065 vs D094 on the brick",
    "D121": "the isolation HAL moves to <code>tfm_spm</code>; the hand-defines are deleted",
    "D122": "the move is MPU-neutral on RA6M5 L2; RA6M5 L1+IPC green, cause unexplained",
    "D123": "RA6M5 L3 confirms D121's predicted +32 B shift; RA6M5 IAR L2 green",
    "D124": "the run matrix is complete; <code>TFM_SP_META_PTR</code> identical across toolchains",
    "D125": "six corrections to D120–D123; the HAL never left the PSA RoT code region",
    "D126": "eighteen corrections to D110–D125; SFN reaches the hook too; diagnostics stay; PXN parked",
}


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def link(e):
    return '<a href="ref/DECISIONS.html#%s">%s</a>' % (e.lower(), e)


def standing():
    out, mode = {}, None
    for line in read(os.path.join(ROOT, "SETTLED.md")).splitlines():
        if line.startswith("## "):
            mode = "s" if line.startswith("## Standing") else "x" if line.startswith("## Superseded") else None
        m = re.match(r"\| `(D\d{3})` \|", line)
        if not (mode and m):
            continue
        refs = re.findall(r"`(D\d{3})`", line.strip().strip("|").split("|")[-1])
        if mode == "s":
            out[m.group(1)] = "stands" + ("; corrected by " + ", ".join(map(link, refs)) if refs else "")
        else:
            out[m.group(1)] = "<strong>superseded</strong> by " + ", ".join(map(link, refs))
    return out


def titles():
    return dict(re.findall(r"^## (D\d{3}) — (.*)$", read(os.path.join(ROOT, "DECISIONS.md")), re.M))


def table(warnings):
    use = collections.defaultdict(list)
    for label, f in PAGES:
        for n in sorted(set(re.findall(r"\bD(\d{3})\b", read(os.path.join(COURSE, f))))):
            use["D" + n].append(label)
    stand, title = standing(), titles()
    rows = []
    for e in sorted(use):
        if e not in SUBJ:
            warnings.append("%s has no course label in SUBJ; using its DECISIONS.md title" % e)
        subj = SUBJ.get(e) or title.get(e, "?")
        if e not in stand:
            warnings.append("%s is not in SETTLED.md" % e)
        name = link(e)
        if int(e[1:]) >= 113:
            name = "<strong>%s</strong>" % name
        rows.append("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>"
                    % (name, subj, stand.get(e, "?"), ", ".join(use[e])))
    return (HEAD + "<th>Standing</th><th>Used in</th></tr>\n" + "\n".join(rows)
            + "\n</table></div>\n" + CAPTION)


def render(page, warnings):
    start = page.index(HEAD)
    end = page.index("</table></div>", start) + len("</table></div>")
    while page[end:].lstrip().startswith('<p class="src">Generated from the D-numbers'):
        end = page.index("</p>", end) + len("</p>")
    return page[:start] + table(warnings) + page[end:]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--check", action="store_true", help="report a stale table, write nothing")
    args = ap.parse_args()
    warnings = []
    cur = read(GLOSSARY)
    new = render(cur, warnings)
    for w in warnings:
        print("  warning: " + w)
    if args.check:
        if new != cur:
            print("stale:   docs/learning/glossary.html decisions table; run: python scripts/build_course_glossary.py")
            return 1
        return 0
    if new != cur:
        with open(GLOSSARY, "w", encoding="utf-8", newline="\n") as f:
            f.write(new)
        print("  wrote   docs/learning/glossary.html decisions table")
    return 0


if __name__ == "__main__":
    sys.exit(main())
