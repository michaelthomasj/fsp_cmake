# Prompt: professional, concise style edit of the fsp_cmake documentation

Edit the documentation for style, not substance. Repository: `C:\Users\Michael\Documents\GitHub\fsp_cmake`; TF-M checkout: `C:\Users\Michael\Documents\GitHub\trusted-firmware-m`.

## Scope
- Root `*.md` (except `DECISIONS.md` and the generated `SETTLED.md`), `scripts/README.md`, and the course pages `docs/learning/*.html`.
- Do not edit `docs/learning/ref/*.html`; the pre-commit hook regenerates them.
- `DECISIONS.md` is append-only. Change only text the log's rules permit to be repaired in place; propose anything else as a new entry.

## Style rules
1. Write in plain technical English. Use one claim per sentence, and keep sentences short.
2. Use declarative statements. Remove rhetorical questions, dramatic framing ("the single most instructive episode", "lethal", "cost two boards" used as a hook), metaphors, and intensifiers that carry no information ("really", "simply", "crucially", "actually").
   **Keep qualifiers that carry meaning.**
   - Intent markers: keep "deliberately" or "intentionally" when the sentence records a design choice that a reader might otherwise reverse, or when it contrasts intentional with accidental (for example "a deliberate SPM panic"). Replace it with "by design" only if the sentence still says the choice is intentional.
   - Precision: keep "exactly" when it means precisely equal (a size, an address, a boundary).
   - Scope and condition: never remove "only", "never", "always", "if", "when", or "on RA6M5 / RA8M2 / both parts".
   - Severity: keep "brick" or "permanent" only where the record supports it. Do not upgrade a recoverable hazard to "brick".
3. Remove filler and restatement: "Note that", "It is worth noting", "In other words", and repeated summaries of the paragraph above.
4. Use active voice where the agent is known. Example: "The port compiles the HAL in `tfm_spm`", not "The HAL is compiled by the port in `tfm_spm`".
5. Use present tense for current behaviour. Use past tense, with the D-number, for history.
6. Use bold sparingly: at most one emphasis per paragraph, and only for a warning or a hazard. Do not use bold for rhythm.
7. Prefer tables or lists for parallel facts. Prefer prose for a causal chain.
8. Keep the claim tags (Armv8-M / TF-M / RA / This port) and every heading anchor (`s8-4`, `d113`) unchanged. Course pages and other documents link to them.

## Invariants (must not change)
- Every technical fact, number, address, register name, macro, file path, `file:line` citation, D-number, command line and code block.
- Hazard and safety statements: brick warnings, OFS rules, setTZBoundaries, flashing order. Shorten their wording only. Never weaken or remove them.
- Section numbering, heading text that carries an anchor, and table columns that are referenced elsewhere.

## Procedure
1. Work one document per commit.
2. After each document run:
   `python scripts/check_docs.py`, `python scripts/check_arch_lines.py`, `python scripts/build_doc_html.py --check`, `python scripts/build_course_glossary.py --check`.
3. List every removed instance of "deliberate(ly)", "intentionally", "exactly", "only", "never", "always", "brick" or "permanent", with the replacement sentence. Produce a word-count delta per document, and a diff that touches no line containing a number, path, register, macro or citation unless that line also has a style change. Flag every such line in the commit message.
4. If a sentence is ambiguous, leave it and list it under "Needs author decision". Do not resolve ambiguity by guessing.
5. Stop and report if a rewrite would require changing a fact.

## Output
- A commit per document.
- A summary table: document, words before, words after, number of sentences changed, lines flagged under rule 3, and items needing an author decision.
