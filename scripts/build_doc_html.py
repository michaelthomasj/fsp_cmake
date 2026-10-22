#!/usr/bin/env python3
"""Render the repository's Markdown documents to HTML for the docs/learning course.

    python scripts/build_doc_html.py            # regenerate docs/learning/ref/ from the working tree
    python scripts/build_doc_html.py --staged   # regenerate from the git index (what the hook uses)
    python scripts/build_doc_html.py --check    # exit 1 if anything in ref/ is stale or orphaned

Exit codes:  0 up to date / written   1 --check found stale output   2 bad usage

WHY THIS EXISTS
---------------
The course in docs/learning/ is plain HTML opened from disk, and it cites the design record
(DESIGN.md, DECISIONS.md, ...) constantly. Linking to the .md files sends a reader to raw
Markdown. A one-time conversion would go stale the first time a document changed - and these
documents change daily. So the Markdown drives the HTML: the pre-commit hook re-runs this
whenever a source document is staged, and --check reports any drift.

THE MARKDOWN IS THE SOURCE. Never edit docs/learning/ref/*.html by hand; the next commit that
touches the Markdown overwrites it.

WHAT IT RENDERS
---------------
Every *.md at the repository root plus scripts/README.md. The archive/ tree is not rendered.

It is a deliberately small renderer for the subset these documents use - ATX headings, pipe
tables, fenced code, nested and task lists, block quotes, rules, emphasis, code spans, links.
Raw HTML is NOT passed through: every '<' is escaped, because these documents write `<part>`
and `<booleanAttribute ...>` as text. Stdlib only, so the hook has no dependency to install.

Two additions over plain Markdown, both for linking from the course:
  * [D113] and [[D113]] become links to DECISIONS.html#d113 when that entry exists.
  * A numbered heading ("## 8. ...", "### 8.4 ...") gets the id s8 / s8-4, so the course can
    link to "DESIGN.md §8.4" directly. Other headings get the GitHub-style slug.

Output is deterministic - no timestamps - so --check is a byte comparison.
"""
import argparse
import html
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "docs", "learning", "ref")
COURSE_DIR = os.path.join(ROOT, "docs", "learning")
EXTRA_SOURCES = ["scripts/README.md"]
GENERATOR = "scripts/build_doc_html.py"


# --------------------------------------------------------------------------- sources

def source_list():
    names = sorted(f for f in os.listdir(ROOT) if f.endswith(".md"))
    return names + [p for p in EXTRA_SOURCES if os.path.exists(os.path.join(ROOT, p))]


def out_name(src):
    """Repo-relative .md path -> file name in ref/. Flat: scripts/README.md -> scripts_README.html."""
    return src.replace("/", "_")[:-3] + ".html"


def read_source(src, staged):
    if not staged:
        with open(os.path.join(ROOT, src), encoding="utf-8") as f:
            return f.read()
    r = subprocess.run(["git", "show", ":" + src], cwd=ROOT, capture_output=True)
    if r.returncode != 0:          # not in the index: fall back to the working tree
        return read_source(src, False)
    return r.stdout.decode("utf-8")


# --------------------------------------------------------------------------- inline

RE_CODE = re.compile(r"(`+)(.+?)\1", re.S)
RE_LINK = re.compile(r"\[((?:[^\[\]]|\[[^\[\]]*\])+)\]\(([^)\s]+)(?:\s+&quot;[^)]*&quot;)?\)")
RE_DREF = re.compile(r"\[\[?(D\d{3})\]?\]")
RE_AUTOLINK = re.compile(r"&lt;(https?://[^\s&]+)&gt;")
RE_URL = re.compile(r"(?<![\"'=/\w])(https?://[^\s<)\]]+[^\s<)\].,;:])")
RE_BOLD = re.compile(r"\*\*(?=\S)(.+?)(?<=\S)\*\*")
RE_ITAL = re.compile(r"(?<![\*\w])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![\*\w])")
RE_UITAL = re.compile(r"(?<![\w])_(?=\S)([^_]+?)(?<=\S)_(?![\w])")
RE_STRIKE = re.compile(r"~~(?=\S)(.+?)(?<=\S)~~")


class Ctx:
    """Per-document state the inline renderer needs."""
    def __init__(self, src, sources, entries):
        self.src = src
        self.sources = sources
        self.entries = entries

    def href(self, url):
        """Rewrite a Markdown link target to work from docs/learning/ref/."""
        if re.match(r"^[a-z]+:", url) or url.startswith("#"):
            return url
        path, _, frag = url.partition("#")
        target = os.path.normpath(os.path.join(os.path.dirname(self.src), path)).replace("\\", "/")
        if target in self.sources:
            return out_name(target) + ("#" + frag if frag else "")
        # Anything else (code, scripts, archive) - point back into the repository.
        rel = os.path.relpath(os.path.join(ROOT, target), OUT_DIR).replace("\\", "/")
        return rel + ("#" + frag if frag else "")

    def dref(self, num):
        return "DECISIONS.html#" + num.lower() if num in self.entries else None


def inline(text, ctx):
    slots = []

    def keep(fragment):
        slots.append(fragment)
        return "\x00%d\x00" % (len(slots) - 1)

    text = RE_CODE.sub(lambda m: keep("<code>%s</code>" % html.escape(m.group(2).strip(), quote=False)), text)
    text = text.replace("\\|", "|").replace("\\*", keep("*")).replace("\\_", keep("_"))
    text = html.escape(text, quote=True)

    def dref(m):
        url = ctx.dref(m.group(1))
        return keep('<a href="%s">%s</a>' % (url, m.group(1))) if url else m.group(0)
    text = RE_DREF.sub(dref, text)

    def link(m):
        label, url = m.group(1), html.unescape(m.group(2))
        return keep('<a href="%s">%s</a>' % (html.escape(ctx.href(url)), inline_restore(label, slots, ctx)))
    text = RE_LINK.sub(link, text)
    text = RE_AUTOLINK.sub(lambda m: keep('<a href="%s">%s</a>' % (m.group(1), m.group(1))), text)
    text = RE_URL.sub(lambda m: keep('<a href="%s">%s</a>' % (m.group(1), m.group(1))), text)

    text = RE_BOLD.sub(r"<strong>\1</strong>", text)
    text = RE_ITAL.sub(r"<em>\1</em>", text)
    text = RE_UITAL.sub(r"<em>\1</em>", text)
    text = RE_STRIKE.sub(r"<del>\1</del>", text)
    return restore(text, slots)


def inline_restore(label, slots, ctx):
    # Link labels are already escaped and may hold code-span slots; only emphasis is left to do.
    t = RE_BOLD.sub(r"<strong>\1</strong>", label)
    t = RE_ITAL.sub(r"<em>\1</em>", t)
    return t


def restore(text, slots):
    while "\x00" in text:
        text = re.sub(r"\x00(\d+)\x00", lambda m: slots[int(m.group(1))], text)
    return text


def plain(text):
    """Heading text as a reader sees it, for slugs and the sidebar."""
    t = RE_CODE.sub(lambda m: m.group(2), text)
    t = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", t)
    t = t.replace("**", "").replace("\\", "")
    return t.strip()


# --------------------------------------------------------------------------- blocks

RE_FENCE = re.compile(r"^(\s*)(```+|~~~+)\s*([\w+-]*)\s*$")
RE_HEAD = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
RE_HR = re.compile(r"^\s{0,3}([-*_])(\s*\1){2,}\s*$")
RE_ITEM = re.compile(r"^(\s*)([-*+]|\d+[.)])\s+(.*)$")
RE_TSEP = re.compile(r"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$")
RE_QUOTE = re.compile(r"^\s{0,3}>\s?(.*)$")


def indent_of(line):
    return len(line) - len(line.lstrip(" "))


def starts_block(line):
    return bool(RE_FENCE.match(line) or RE_HEAD.match(line) or RE_HR.match(line)
                or RE_ITEM.match(line) or RE_QUOTE.match(line) or line.lstrip().startswith("|"))


def split_row(line):
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|") and not s.endswith("\\|"):
        s = s[:-1]
    cells, cur, in_code, i = [], "", False, 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s) and s[i + 1] == "|":
            cur += "\\|"
            i += 2
            continue
        if c == "`":
            in_code = not in_code
        if c == "|" and not in_code:
            cells.append(cur.strip())
            cur = ""
        else:
            cur += c
        i += 1
    cells.append(cur.strip())
    return cells


class Doc:
    def __init__(self, ctx):
        self.ctx = ctx
        self.used_ids = set()
        self.toc = []          # (level, id, text)

    def heading_id(self, text):
        t = plain(text)
        m = re.match(r"^(D\d{3})\b", t)
        if m:
            base = m.group(1).lower()
        else:
            m = re.match(r"^§?(\d+(?:\.\d+)*)\.?\s", t)
            if m:
                base = "s" + m.group(1).replace(".", "-")
            else:
                base = re.sub(r"[^\w\- ]", "", t.lower()).replace(" ", "-") or "section"
        # Suffix with "_n", not "-n": "s1-1" must keep meaning section 1.1.
        hid, n = base, 2
        while hid in self.used_ids:
            hid = "%s_%d" % (base, n)
            n += 1
        self.used_ids.add(hid)
        return hid

    def render(self, lines):
        out, i = [], 0
        while i < len(lines):
            line = lines[i]
            if not line.strip():
                i += 1
                continue

            m = RE_FENCE.match(line)
            if m:
                fence, lang, ind = m.group(2), m.group(3), len(m.group(1))
                body, i = [], i + 1
                while i < len(lines) and not (lines[i].strip().startswith(fence[0] * len(fence))
                                              and not lines[i].strip().strip(fence[0])):
                    body.append(lines[i][ind:] if lines[i][:ind].strip() == "" else lines[i])
                    i += 1
                i += 1
                cls = ' class="language-%s"' % lang if lang else ""
                out.append("<pre><code%s>%s</code></pre>" % (cls, html.escape("\n".join(body), quote=False)))
                continue

            m = RE_HEAD.match(line)
            if m:
                level, text = len(m.group(1)), m.group(2)
                hid = self.heading_id(text)
                self.toc.append((level, hid, plain(text)))
                out.append('<h%d id="%s">%s</h%d>' % (level, hid, inline(text, self.ctx), level))
                i += 1
                continue

            if RE_HR.match(line):
                out.append("<hr>")
                i += 1
                continue

            if "|" in line and i + 1 < len(lines) and RE_TSEP.match(lines[i + 1]):
                out.append(self.table(lines, i))
                i += 2
                while i < len(lines) and lines[i].strip() and "|" in lines[i]:
                    i += 1
                continue

            if RE_QUOTE.match(line):
                body = []
                while i < len(lines) and lines[i].strip() and RE_QUOTE.match(lines[i]):
                    body.append(RE_QUOTE.match(lines[i]).group(1))
                    i += 1
                out.append("<blockquote>%s</blockquote>" % self.render(body))
                continue

            if RE_ITEM.match(line):
                html_list, i = self.list_block(lines, i)
                out.append(html_list)
                continue

            para = []
            while i < len(lines) and lines[i].strip() and (not para or not starts_block(lines[i])):
                para.append(lines[i].lstrip())
                i += 1
            out.append("<p>%s</p>" % self.para_text(para))
        return "\n".join(out)

    def para_text(self, para):
        # A line ending in two spaces is a hard break. Split there, render each run, rejoin.
        runs, cur = [], []
        for p in para:
            cur.append(p.rstrip())
            if p.endswith("  "):
                runs.append(cur)
                cur = []
        if cur:
            runs.append(cur)
        return "<br>\n".join(inline("\n".join(r), self.ctx) for r in runs)

    def table(self, lines, i):
        head = split_row(lines[i])
        aligns = []
        for c in split_row(lines[i + 1]):
            c = c.strip()
            aligns.append("center" if c.startswith(":") and c.endswith(":") else
                          "right" if c.endswith(":") else "left" if c.startswith(":") else None)

        def cell(tag, text, k):
            a = aligns[k] if k < len(aligns) else None
            style = ' style="text-align:%s"' % a if a else ""
            return "<%s%s>%s</%s>" % (tag, style, inline(text, self.ctx), tag)

        rows = ["<tr>%s</tr>" % "".join(cell("th", c, k) for k, c in enumerate(head))]
        j = i + 2
        while j < len(lines) and lines[j].strip() and "|" in lines[j]:
            cells = split_row(lines[j])
            cells += [""] * (len(head) - len(cells))
            rows.append("<tr>%s</tr>" % "".join(cell("td", c, k) for k, c in enumerate(cells)))
            j += 1
        return '<div class="table-wrap"><table>\n%s\n</table></div>' % "\n".join(rows)

    def list_block(self, lines, i):
        first = RE_ITEM.match(lines[i])
        base = len(first.group(1))
        ordered = first.group(2)[0].isdigit()
        start = int(first.group(2)[:-1]) if ordered else 1
        items, loose = [], False

        while i < len(lines):
            m = RE_ITEM.match(lines[i])
            if not m or len(m.group(1)) != base or m.group(2)[0].isdigit() != ordered:
                break
            content_col = len(m.group(1)) + len(m.group(2)) + 1
            body = [m.group(3)]
            i += 1
            while i < len(lines):
                ln = lines[i]
                if not ln.strip():
                    # A blank line ends the item unless indented content follows.
                    k = i
                    while k < len(lines) and not lines[k].strip():
                        k += 1
                    if k < len(lines) and indent_of(lines[k]) >= content_col:
                        body.extend([""] * (k - i))
                        i = k
                        loose = loose or not RE_ITEM.match(lines[k])
                        continue
                    if k < len(lines):
                        nm = RE_ITEM.match(lines[k])
                        if nm and len(nm.group(1)) == base and nm.group(2)[0].isdigit() == ordered:
                            loose = True
                    i = k
                    break
                if indent_of(ln) >= content_col:
                    body.append(ln[content_col:])
                elif RE_ITEM.match(ln) and indent_of(ln) > base:
                    body.append(ln[min(indent_of(ln), content_col):])
                elif indent_of(ln) <= base and (RE_ITEM.match(ln) or starts_block(ln)):
                    break
                else:
                    body.append(ln.strip())        # lazy continuation
                i += 1
            items.append(body)

        rendered = []
        for body in items:
            task = re.match(r"^\[([ xX])\]\s+(.*)$", body[0])
            prefix = ""
            if task:
                prefix = '<input type="checkbox" disabled%s> ' % (" checked" if task.group(1) != " " else "")
                body = [task.group(2)] + body[1:]
            inner = self.render(body)
            if not loose and inner.startswith("<p>"):
                inner = re.sub(r"^<p>(.*?)</p>", r"\1", inner, count=1, flags=re.S)
            rendered.append("<li>%s%s</li>" % (prefix, inner))
        tag = "ol" if ordered else "ul"
        attr = ' start="%d"' % start if ordered and start != 1 else ""
        return "<%s%s>\n%s\n</%s>" % (tag, attr, "\n".join(rendered), tag), i


# --------------------------------------------------------------------------- page

def page(src, title, body, toc, sources, is_index=False):
    nav_docs = "\n".join(
        '      <li><a href="%s"%s>%s</a></li>' % (out_name(s), ' aria-current="page"' if s == src else "", s)
        for s in sources)
    toc_items = "\n".join(
        '          <li><a href="#%s">%s</a></li>' % (hid, html.escape(text))
        for level, hid, text in toc if level == 2)
    toc_block = "\n        <ol>\n%s\n        </ol>" % toc_items if toc_items else ""
    if is_index:
        note = ""
        comment = "GENERATED by %s." % GENERATOR
        desc = "Index of the repository documents rendered for the course."
        toc_label = "Contents"
    else:
        rel_src = os.path.relpath(os.path.join(ROOT, src), OUT_DIR).replace("\\", "/")
        note = ('<p class="src">Rendered from <a href="%s"><code>%s</code></a>. '
                'Edit the Markdown, not this page.</p>\n' % (rel_src, src))
        comment = ("GENERATED from %s by %s. Do not edit: the next commit touching the "
                   "Markdown overwrites it." % (src, GENERATOR))
        desc = "Rendered from %s by %s." % (src, GENERATOR)
        toc_label = src
    return PAGE.format(title=html.escape(title), desc=desc, comment=comment, nav_docs=nav_docs,
                       toc_label=toc_label, toc_block=toc_block, note=note, body=body)


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{desc}">
<link rel="stylesheet" href="../assets/style.css">
<script src="../assets/site.js"></script>
</head>
<body>
<!-- {comment} -->
<div class="layout">
<aside class="sidebar">
  <div class="brand"><a href="../index.html">Cortex-M, TrustZone &amp; TF-M on Renesas RA</a><button class="menu-toggle" aria-expanded="false">Menu</button></div>
  <nav>
    <ol>
      <li><a href="../index.html">← Course</a></li>
      <li><a href="index.html">Reference documents</a>
        <ol>
{nav_docs}
        </ol>
      </li>
    </ol>
    <ol class="doc-toc">
      <li><a href="#top">{toc_label}</a>{toc_block}
      </li>
    </ol>
    <button class="theme-toggle" type="button">Dark theme</button>
  </nav>
</aside>
<main id="top" class="ref-doc">
{note}{body}
</main>
</div>
</body>
</html>
"""


def index_page(sources, titles):
    rows = "\n".join('<tr><td><a href="%s"><code>%s</code></a></td><td>%s</td></tr>'
                     % (out_name(s), s, html.escape(titles[s])) for s in sources)
    body = """<h1>Reference documents</h1>
<p class="lede">The repository's design record, rendered from Markdown. The Markdown is the source: these pages are
regenerated by <code>{gen}</code> whenever a commit touches it.</p>
<div class="table-wrap"><table>
<tr><th>Source</th><th>Title</th></tr>
{rows}
</table></div>""".format(gen=GENERATOR, rows=rows)
    return page("index", "Reference documents", body, [], sources, is_index=True)


RE_CTRL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
WARNINGS = []


def visible_controls(src, text):
    """A stray control character in Markdown is almost always a mangled escape - PROJECT_PLAN.md once
    held a literal 0x08 where `C:\\b` was meant. Browsers drop it silently, so render it as its Unicode
    control picture (U+2400 + code, e.g. U+2408 for backspace) and report where it is."""
    for n, line in enumerate(text.split("\n"), 1):
        for m in RE_CTRL.finditer(line):
            WARNINGS.append("%s:%d: control character 0x%02X" % (src, n, ord(m.group(0))))
    return RE_CTRL.sub(lambda m: chr(0x2421 if m.group(0) == "\x7f" else 0x2400 + ord(m.group(0))), text)


def build(staged):
    sources = source_list()
    texts = {s: visible_controls(s, read_source(s, staged).replace("\r\n", "\n")) for s in sources}
    entries = set(re.findall(r"^## (D\d{3}) ", texts.get("DECISIONS.md", ""), re.M))
    outputs, titles = {}, {}
    for s in sources:
        ctx = Ctx(s, set(sources), entries)
        doc = Doc(ctx)
        body = doc.render(texts[s].replace("\r\n", "\n").split("\n"))
        titles[s] = next((t for lvl, _, t in doc.toc if lvl == 1), s)
        outputs[out_name(s)] = page(s, titles[s], body, doc.toc, sources)
    outputs["index.html"] = index_page(sources, titles)
    return outputs


# --------------------------------------------------------------------------- course link audit

def course_md_links():
    """Course pages must link to ref/*.html, not to raw .md - report any that do not."""
    bad = []
    for f in sorted(os.listdir(COURSE_DIR)):
        if f.endswith(".html"):
            with open(os.path.join(COURSE_DIR, f), encoding="utf-8") as fh:
                for n, line in enumerate(fh, 1):
                    for m in re.finditer(r'href="(\.\./\.\./[^"#]+\.md)', line):
                        bad.append("%s:%d links %s" % (f, n, m.group(1)))
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--staged", action="store_true", help="render from the git index")
    ap.add_argument("--check", action="store_true", help="report stale output, write nothing")
    args = ap.parse_args()

    outputs = build(args.staged)
    os.makedirs(OUT_DIR, exist_ok=True)
    existing = {f for f in os.listdir(OUT_DIR) if f.endswith(".html")}

    stale = []
    for name, text in outputs.items():
        path = os.path.join(OUT_DIR, name)
        cur = open(path, encoding="utf-8").read() if os.path.exists(path) else None
        if cur != text:
            stale.append(name)
            if not args.check:
                with open(path, "w", encoding="utf-8", newline="\n") as f:
                    f.write(text)
    orphans = sorted(existing - set(outputs))
    if not args.check:
        for name in orphans:
            os.remove(os.path.join(OUT_DIR, name))

    # Reported, not fatal: the fix belongs in the Markdown, which may be someone else's document.
    for w in WARNINGS:
        print("  warning: " + w)

    bad_links = course_md_links()
    if args.check:
        for n in stale:
            print("stale:   docs/learning/ref/" + n)
        for n in orphans:
            print("orphan:  docs/learning/ref/" + n)
        for b in bad_links:
            print("raw .md link in course: " + b)
        if stale or orphans or bad_links:
            print("run: python %s" % GENERATOR)
            return 1
        return 0

    for n in stale:
        print("  wrote   docs/learning/ref/" + n)
    for n in orphans:
        print("  removed docs/learning/ref/" + n)
    for b in bad_links:
        print("  error: raw .md link in course: " + b)
    return 1 if bad_links else 0


if __name__ == "__main__":
    sys.exit(main())
