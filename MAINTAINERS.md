# Maintainer notes

Shipped as an appendix, not on the customer path. The scripts documented here ship with the
port, so whoever maintains them needs this; nobody integrating TF-M on an RA part does.

What is here: the internals of the launch generator, the documentation checkers, the git hooks
and the reference renderer. Everything a customer runs is in
[GETTING_STARTED.md](GETTING_STARTED.md) and [scripts/README.md](scripts/README.md).

---

## Launch files: host projects and what the generator rewrites

The host project in `PROJECT_ATTR` differs between the two parts, on purpose:

| | host project |
|---|---|
| RA6M5, both toolchains | `ra6m5_gcc_nonsecure` |
| RA8M2 GCC | `ra8m2_gcc_CPU0_nonsecure` |
| RA8M2 IAR | `ra8m2_iar_CPU0_nonsecure` |

`serverParam` builds the J-Link settings path from `${ProjName}`:

```
-uJLinkSetting= "${workspace_loc:/${ProjName}}/${LaunchConfigName}.jlink"
```

so hosting both toolchains in one project makes them share a directory for those sidecars. Giving
each toolchain its own host keeps them apart. `ATTR_BUILD_BEFORE_LAUNCH_ATTR` is `2`,
`USE_WORKSPACE_SETTING` in Eclipse CDT rather than `DISABLED` (`0`), so whether the host project
is built follows the workspace preference. Keep `MAPPED_RESOURCE_PATHS` in step with
`PROJECT_ATTR`.

`PROJECT_BUILD_CONFIG_AUTO_ATTR` is `false` in every IAR launch. Only the RA8M2 GCC launches
have `true`; every RA6M5 GCC launch has `false`, so it cannot be inherited either way.

`mk_iar_launches.py` derives each IAR launch from its GCC twin by swapping build-tree names and
the three project attributes above. It
refuses to write a launch that still names a GCC tree or the GCC project, or that has
`setTZBoundaries` true anywhere. Run `--check` first: it reports `same` when the generator
reproduces what is on disk, which is how a hand edit gets folded back in rather than lost.

---

## Packaging a release archive

`docs/learning/ref/` is generated and not committed, and 71 course links resolve into it, so
the archive has to carry it. From a clean clone of the tag:

```sh
python scripts/build_doc_html.py          # writes docs/learning/ref/
python scripts/check_docs.py --clean-clone
git archive --prefix=ra_fsp_cmake_tfm/ -o ../release.tar HEAD
tar -rf ../release.tar --transform 's,^,ra_fsp_cmake_tfm/,' docs/learning/ref
```

Build `ref/` from a clean clone rather than a working tree, so a withheld document cannot be
rendered into the archive. `build_doc_html.py --check` fails if any page is stale.

## Documentation checks — maintainer tooling

```sh
python scripts/check_docs.py                 # verify every D-citation and .md reference resolves
sh scripts/install_hooks.sh                  # install it as a pre-commit hook (once per clone)
python scripts/decision_threads.py           # candidate threads for the Settled questions table
python scripts/decision_threads.py --status   # entries needing a Status back-annotation
```

`decision_threads.py` finds threads mechanically and over-merges them, so the Settled questions
table in [DECISIONS.md](DECISIONS.md) is grouped by hand from its output. Regenerate at each
milestone.

Checks nine things, in two groups. **References:**

- every `D###` cited anywhere exists in `DECISIONS.md`;
- every relative `.md` link resolves;
- every `.md` filename named in a comment in the port tree resolves and is tracked;
- a cited *section* exists in the document the citation names (`FILE.md §6`,
  `FILE.md §"Some heading"`);
- the course's links resolve, within `docs/learning/` and into the generated pages in `ref/`. **Customer readiness:** no local
user path; every link target tracked in git rather than merely present on disk; decision-ID
density under 15 per 1000 words; no launch setting `setTZBoundaries` true for any probe. Pass
`--no-customer` to skip the second group.

`DECISIONS.md` is exempt from the link checks because it is append-only - a reference there to
a since-retired file is a historical fact, not a defect.
Review snapshots under `docs/artifacts*/` are exempt from every check: they cite entries a
review proposes before anyone has written them.

Bypass with `git commit --no-verify` when a commit breaks a reference on purpose, such as the
first half of a rename spanning both repositories.

```sh
python scripts/check_arch_lines.py          # BUILD_ARCHITECTURE.md's line citations
python scripts/check_arch_lines.py --list   # show what each cited line holds
```

73 citations, each paired with a regex the cited line must match: the RA port `CMakeLists.txt`
and module files, upstream TF-M, and this repository's own build scripts. The table covers
`BUILD_ARCHITECTURE.md`'s citations only. Line citations in the other documents - `DESIGN.md`,
the solution documents, the course pages - are not checked, which is why `DESIGN.md` §8.4 cites
`ra6m5_add_ofs_check()` by function name rather than by line. `check_docs.py`
cannot catch this class: the file exists and the D-numbers resolve, so a reference stays
"valid" while pointing at the wrong line.

The port citations went stale twice in one day, both times from a comment edit above the
block with no CMake change. The table keeps them in two lists for that reason: `CITES` and
`PORT_PATHS` are port files and move with a port commit, `UPSTREAM` is TF-M's own code and
moves only on a TF-M uprev.

Fail-on-stale, not regenerate: the numbers sit in prose that explains each block, so a human
has to look. The pre-commit hook skips it when `trusted-firmware-m` is not beside this repo;
run by hand in that case it exits 2. `scripts/pre-commit-tfm` runs the same check from the
TF-M side, where the drift originates. Adding a citation to `BUILD_ARCHITECTURE.md` means
adding a row to the table in the script.

`install_hooks.sh` installs two hooks, not one: `scripts/pre-commit` into this repository and
`scripts/pre-commit-tfm` into `../trusted-firmware-m/.git/hooks/pre-commit`. An existing hook
is copied to `<name>.bak` first. It is safe to re-run, and it has to be re-run after either
hook script changes, because the hooks are copies rather than symlinks.

### Rendered documents for the course — maintainer tooling

```sh
python scripts/build_doc_html.py           # regenerate docs/learning/ref/ from the working tree
python scripts/build_doc_html.py --check   # exit 1 if ref/ is stale, orphaned, or the course links raw .md
```

The course in `docs/learning/` links to HTML renderings of every root `*.md` and this file, in
`docs/learning/ref/`. **The Markdown is the source; never edit `ref/*.html`.** That directory is
generated and is not committed: run the command above once per clone to make the course links
resolve, and again at packaging time. It also fails when a course page links a raw `.md` instead
of `ref/<NAME>.html`, which is worth running after editing the course.

- Stdlib only - a small renderer for the subset these documents use. Raw HTML in Markdown is
  escaped, not passed through.
- `[D113]` becomes a link to `DECISIONS.html#d113`; a numbered heading (`### 8.4 ...`) gets the
  id `s8-4`, so the course can link `DESIGN.html#s8-4` for "DESIGN.md §8.4". Renumbering a
  section therefore breaks inbound course links. `--check` here does not catch that;
  `check_docs.py` does, by computing the same anchors from the Markdown and resolving every
  course link against them.
- Output is deterministic, so `--check` is a byte comparison and diffs show only real changes.
- Adding or removing a document rewrites every page, because each sidebar lists them all.
- `--no-verify` skips the render too. Run the script by hand afterwards, or the next
  documentation commit will pick it up.
