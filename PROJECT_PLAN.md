# TF-M on Renesas RA — RA6E1 → RA6M5 → RA8x2 (single-core), FSP 6.6, GNUARM + IAR

**Project plan · Firmware security · revised 2026-09-14**

RA6E1 is **complete on both toolchains** and validated well beyond the original
bar. The remaining work is three sequential pieces: **RA6M5** (the device
intended for upstream, and the first with hardware crypto wired in), a **TF-M
2.3 update**, and **RA8x2 single-core**.

**Scope change — RA8x2 is single-core.** The previous revision built the whole
RA8x2 leg around dual-core operation and binding FSP's inter-core comms to
TF-M's mailbox HAL. That is **descoped**: RA8x2 work is now the TrustZone
configuration and BSP update for a single-core part. This removes an entire
phase and **both High risks** from the register — see *Descoped* below.

**All dates below are targets, not commitments.** An overrun shifts subsequent
dates rather than cutting scope.

> A rendered version of this plan is in [`PROJECT_PLAN.html`](PROJECT_PLAN.html).

| | |
|---|---|
| **RA6E1 (GNUARM + IAR)** | **done 2026-09-14** (target was ~09-25) |
| **RA6M5 — upstream vehicle** | **~2026-10-16 (target)** |
| **TF-M 2.3 update** | **~2026-11-06 (target)** |
| **Primary goal — RA8x2 single-core** | **~2026-12-18 (target)** |
| Revised | 2026-09-14 |
| Toolchains | GNUARM + IAR |
| Validation | boot + crypto NSC app; PSA Arch suites where available |
| Resourcing | 1 engineer |

---

## Snapshot

**Done — RA6E1, both toolchains**
- Full secure boot chain **BL2 → S → NS** on silicon, GNUARM and IAR.
- **PSA Arch suites pass on both toolchains** — attestation 1/1, storage 17
  (11 passed, 6 optional-PS skips), crypto 64/64, zero failures. This is
  conformance evidence the original plan did not ask for.
- Split SPE/NSPE build, OFS brick-guard, DDSC bridge, SCE9 TRNG as the PSA
  entropy source.
- Three upstream TF-M defects found and fixed along the way (IAR stack seal,
  CMSE veneer placement, vendor-section hooks) — see `UPSTREAM_CHANGES.md`.

**Next — RA6M5 (~mid Oct)**
- Port to the device intended for upstream submission.
- **SCE9 hardware crypto wired in** — the first platform here to use it for
  ciphers rather than entropy alone.

**Then — TF-M 2.3 (~early Nov)**
- Rebase from the v2.2.0 fork point onto 2.3.x. **2287 commits**, with the
  churn concentrated in the files this port patches.

**Primary goal — RA8x2 single-core (~mid Dec)**
- TrustZone configuration + BSP update on FSP 6.6, GNUARM + IAR.

**Out of scope**
- **Dual-core / inter-core mailbox** — descoped 2026-09-14.
- ARMCLANG toolchain.

---

## Timeline

| Phase | Work | Start | End | Track |
|---|---|---|---|---|
| **P1** | RA6E1 secure image (tfm_s) — GNUARM | 2026-07-28 | 2026-08-14 | ✅ done |
| **P2** | RA6E1 non-secure · full boot · crypto NSC app (GNUARM) | 2026-08-17 | 2026-09-04 | ✅ done |
| **P3** | IAR toolchain for RA6E1 | 2026-09-07 | **2026-09-14** | ✅ done, 11d early |
| **P4** | RA6M5 port + SCE9 crypto acceleration | 2026-09-15 | 2026-10-16 | RA6M5 |
| **P5** | TF-M 2.3 update | 2026-10-19 | 2026-11-06 | Shared |
| **P6** | RA8x2 single-core — TrustZone cfg + BSP | 2026-11-09 | 2026-12-18 | RA8x2 (key) |
| **P7** | *Stretch* — upstream to Arm TF-M | 2027-01-11 | 2027-03-26 | Stretch |

Critical path: **P4 → P5 → P6** (sequential under one engineer).

The primary-goal date holds at ~Dec 18 despite adding RA6M5 and the 2.3 update,
because descoping dual-core returned roughly four weeks and P3 finished early.

---

## Phases

### P4 · RA6M5 port + SCE9 crypto acceleration (Sep 15 – Oct 16)
- RA6M5 RASC solution projects on FSP 6.6 (BL2 / secure / non-secure), partitioned,
  MCUboot dual-image — the RA6E1 pattern.
- `platform/ext/target/renesas/ra6m5`: memory map, `region_defs.h`, linker scripts
  (`.ld` + `.icf`), OFS guard.
- Full boot chain + crypto NSC app on silicon, **GNUARM and IAR**.
- PSA Arch suites, both toolchains.
- **SCE9 crypto acceleration** — RA6M5 has SCE9, the same engine as RA6E1/RA6M4
  (FSP namespaces it `BSP_FEATURE_RSIP_SCE9_SUPPORTED`; true RSIP parts are RA8).
  Today only the TRNG is hardware; ciphers run in TF-M's software mbedcrypto with
  `CRYPTO_HW_ACCELERATOR OFF`.
  - New `platform/ext/accelerator/renesas/sce9/` implementing TF-M's `crypto_hw.h`,
    with `cc312` as the structural template. **Per-engine directory on purpose** —
    RA8's RSIP is a different driver API and will land beside it as
    `renesas/rsip`, not as a variant of this one.
  - Untangle `FSP_MODULES_NEVER_BUILT` (`r_sce`, `rm_psa_crypto`, FSP's mbedTLS)
    so FSP's crypto stack can be built without colliding with TF-M's mbedcrypto.
    This exclusion is load-bearing today; it is the first real task, not a flag flip.
  - Regression gate: the PSA Arch crypto suite, against the existing 64/64
    software baseline.
- **Exit M4** — RA6M5 full chain + crypto app, both toolchains, SCE9 ciphers active.

> **Sequencing note.** `tfm_plat_crypto_keys.h` gains 58 lines between v2.2.0 and
> 2.3.1. If the cipher ALT wiring slips, prefer doing it *after* P5 rather than
> building it twice.

### P5 · TF-M 2.3 update (Oct 19 – Nov 6)
- Rebase from fork point `dd2b7de19` (v2.2.0, 2025-04-14) onto 2.3.x — **2287 commits**.
- Re-apply the 12 items in `UPSTREAM_CHANGES.md`. The churn lands squarely on them:
  `tfm_isolation_s.ld.template` +253, `toolchain_GNUARM.cmake` ±268,
  `config_base.cmake` +94, and `wrapper.py` (−145) / `keys.c` (−295) substantially
  rewritten upstream — both carry our patches.
- Platform HAL delta: `tfm_hal_isolation.h` +15/−2, `tfm_hal_platform.h` +29/−2,
  `tfm_plat_crypto_keys.h` +58, `tfm_plat_otp.h` +15.
- **Exit M5** — RA6E1 and RA6M5 on 2.3.x, both toolchains, all suites green.

### P6 · RA8x2 single-core — TrustZone cfg + BSP (Nov 9 – Dec 18)
- New `platform/ext/target/renesas/ra8x2`; RASC projects on FSP 6.6.
- TrustZone configuration (`target_cfg.c` — SAU/PPC/MPC), isolation HAL, DDSC bridge.
- BSP update: memory map, RSIP crypto driver, entropy source, Cortex-M85
  PACBTI / FPU-in-SPE.
- Linker scripts for both toolchains; boot chain + crypto NSC app.
- **Exit M6** — RA8x2 single-core full chain + crypto app, GNUARM + IAR.

### P7 · Stretch — upstream to the Arm TF-M repository (Jan 11 – Mar 26, 2027)
- **Submission is via Gerrit** (`review.trustedfirmware.org`), not a GitHub PR —
  `docs/contributing/contributing_process.rst`. The GitHub repo is a mirror.
- The 12 shared-file fixes as individual Gerrit changes; several
  (BL2 signing dependency, `MCUBOOT_ALIGN_VAL` cap) are platform-independent and
  can go early.
- `psa-arch-tests` target via GitHub PR — that repo *does* take PRs.
- Docs tree; accept the deprecation policy's maintenance commitment.
- **Exit M7** — RA6M5 (+ RA8x2) merged upstream.

---

## Milestones

| ID | Date (target) | Gate |
|---|---|---|
| M1 | 2026-08-14 | ✅ RA6E1 BL2 → tfm_s boots on silicon |
| M2 | 2026-09-04 | ✅ Full RA6E1 boot + crypto NSC app (GNUARM) |
| M3 | **2026-09-14** | ✅ RA6E1 full chain + crypto app, GNUARM **and** IAR |
| M4 | ~2026-10-16 | RA6M5 full chain, both toolchains, SCE9 ciphers active |
| M5 | ~2026-11-06 | Both platforms on TF-M 2.3.x, suites green |
| **M6** | **~2026-12-18** | **RA8x2 single-core full chain + crypto app, GNUARM + IAR** (primary goal) |
| M7 | ~2027 Q1–Q2 | *Stretch* — merged into Arm TF-M upstream |

---

## Risks & buffer

| Severity | Risk |
|---|---|
| **High** | **TF-M 2.3 rebase.** 2287 commits from the v2.2.0 fork point, with churn concentrated in the 12 files this port patches; `wrapper.py` and `keys.c` are substantially rewritten upstream. Concentrated in P5, and the cost grows the longer it is deferred. |
| **High** | **RA8x2 new silicon on FSP 6.6.** First bring-up — M85 PACBTI/FPU, RSIP-E51A, TrustZone config. Concentrated in P6. |
| Med | **SCE9 cipher wiring.** FSP's crypto stack and TF-M's mbedcrypto currently cannot coexist (`FSP_MODULES_NEVER_BUILT`); untangling that is the substance of the accelerator work. |
| Med | **IAR replication, round 2.** RA8x2 `.icf` / startup. Materially de-risked — the RA6E1 round is done and the patterns, hooks and three upstream fixes transfer. |
| Med | **Hardware.** An EK-RA8x2 must be procured before P6; an RA6M5 board before P4. Procurement lead time is not absorbed by schedule slack. 2× EK-RA6M4 bricked (RA6E1 was the RA6 vehicle). |
| Low | **Open defects.** `.ram_from_flash` not relocated at isolation 3 (DECISIONS D029 — the shipping isolation-1 build is correct); `.srec` rule missing from the IAR NS toolchain. |

### Descoped 2026-09-14 — dual-core

The previous revision made **RA8x2 dual-core** the primary goal, with P5 dedicated
to binding FSP inter-core communication to TF-M's `tfm_hal_multi_core_*` /
`platform_mailbox`, an NS mailbox agent, and PSA call marshaling across cores.
It carried the two highest risks in the register: the mailbox integration itself
("no RA reference exists") and the unexamined core-topology question.

All of it is removed. RA8x2 is a single-core part for this project. Retained from
that leg: the base port, TrustZone config, BSP, and the NS + IAR + crypto-app work,
now consolidated into P6.

**Buffer.** Dates are targets. The RA8x2 leg holds Dec 21 – Jan 2 as contingency.
Everything is sequential under one engineer.

---

*Revised 2026-09-14 · RA6E1 done · RA6M5 ~2026-10-16 · TF-M 2.3 ~2026-11-06 · RA8x2 single-core ~2026-12-18*
