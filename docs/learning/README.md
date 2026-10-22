# Cortex-M, TrustZone and TF-M on Renesas RA — a course

Open `index.html` in a browser. Plain HTML, no build step, no server, no network.

## Who it is for

- A new engineer who knows C and has read a datasheet, but has not met privilege levels, an MPU,
  TrustZone or a secure partition manager.
- Goal: able to work on, or port, the TF-M port in this repository.

## What it assumes

- C, pointers, linker sections at a basic level, reading hex.
- Access to this repository and the TF-M checkout at
  `C:\Users\Michael\Documents\GitHub\trusted-firmware-m` — citations point into both.

## Structure

| Page | Content |
|---|---|
| `index.html` | audience, how to read, the four claim tags, hardware summary |
| `part0-primer.html` | Cortex-M from scratch, with RA addresses; forward links to where each idea is tested |
| `part1-privilege-mpu-faults.html` | privilege, MSP/PSP, MPU encoding, stacking, EXC_RETURN, SVC/PendSV, fault decoding with real dumps |
| `part2-trustzone.html` | security states, SAU/IDAU, NSC/SG, banking, NVIC target state, RA's ICUSARG/PSAR/PSCU |
| `part3-tfm.html` | PSA-FF-M, `psa_call`, isolation levels, SPM, SFN vs IPC, FLIH, the isolation HAL, the D113–D122 case study |
| `part4-porting.html` | platform contract, RASC/FSP inputs, MCUboot layout, hazards, verification gates, upstream divergence |
| `glossary.html` | terms, decisions cited, files cited |

Every claim is tagged **Armv8-M** (architecture), **TF-M** (implementation choice), **RA** (Renesas
silicon/FSP) or **This port**.

## What it leaves out, deliberately

- Crypto: SCE9/RSIP acceleration, the ALT integration, PSA Arch crypto results.
- Storage internals (ITS/PS file system), attestation token format.
- Build and flash procedure — see `GETTING_STARTED.md`; this course explains why, not how.
- Multi-core TF-M topology, RA8x2 dual-core design.
- Armv8.1-M features beyond PXN (MVE, PACBTI).
- Dormant parts (RA6M4, RA6E1) except where their history is the example.
- Non-secure RTOS internals.

## Corrections the course teaches from

Discrepancies found while writing the first edition, all since resolved in the record (D115–D117)
and kept in the pages as worked examples:

- D114 said `TFM_PXN_ENABLE` never becomes a compile definition; it has since 2021 (`d839593bf`).
- Three RA6 `target_cfg.c` files denied the IDAU exists; fixed in TF-M `b1b9078ff`.
- D113 over-generalised FLIH Thread-mode dispatch; D116 closed the L1+IPC mechanism unanswered.
- `CONFIGURATION.md` §3 and `RA8M2_SOLUTION.md` predated D091.
- The accuracy review of 2026-10-22 (`docs/artifacts/`, findings F156–F214) found 59 errors in the
  course itself, all fixed. The largest: the missing `TFM_ISOLATION_LEVEL` is not an upstream
  defect at all. Every upstream platform compiles the shared isolation HAL in `tfm_spm`, which
  always receives the macro; the RA ports compile it in `platform_s`, which does not. The review
  blamed `PLATFORM_DEFAULT_ATTEST_HAL`, but that is only a contributor: mps4 sets it OFF and is
  unaffected. Measured on `C:\b\an519chk`; recorded as D120, which withdraws UPSTREAM_CHANGES
  item 15. D121 then moved the HAL to `tfm_spm`; D122 ran RA6M5 after the move.
- The rerun review (`docs/artifacts_v2/`, F222–F252) found the course stale against D121/D122 and
  five smaller errors (F224, F227, F228, F240, F242); all fixed. Findings against DECISIONS.md and the
  TF-M port comments are outside the course and left to those owners.

## Reference documents (`ref/`)

The course links to the repository's design record — `DESIGN.md`, `DECISIONS.md` and the rest —
through HTML renderings in `ref/`, not the raw Markdown.

- **Generated. Do not edit `ref/*.html`.** Edit the Markdown; the pre-commit hook re-renders
  from the staged Markdown and stages the HTML in the same commit (`scripts/build_doc_html.py`,
  documented in `scripts/README.md` §"Rendered documents for the course").
- Install the hook once per clone: `sh scripts/install_hooks.sh`.
- Course pages must link `ref/<NAME>.html`, never `../../<NAME>.md`; the hook refuses the commit
  otherwise.
- Deep links: `ref/DECISIONS.html#d113` for an entry, `ref/DESIGN.html#s8-4` for a numbered
  section.

## Maintenance

- Line numbers: TF-M `addc59f54`, fsp_cmake `b821e3f` (2026-10-22).
- Upstream TF-M citations drift only on a TF-M uprev. Port citations
  (`platform/ext/target/renesas/…`) move with port commits — recheck those first. An FSP bump moves
  only the FSP citations.
- Run status (Part 3 §3.3 coverage table, Part 1 §1.9 status) is a snapshot of D122; update it when
  RA6M5 L3, the RA8M2 trees and RA6M5 IAR L2/L3 are run after the D121 move.
- Assets: `assets/style.css` (light/dark tokens), `assets/site.js` (theme toggle, narrow-screen menu;
  the pages work without it).
