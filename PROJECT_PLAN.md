# TF-M on Renesas RA — RA6E1 → RA6M5 → RA8x2 (single-core), FSP 6.7, GNUARM + IAR

**Project plan · Firmware security · revised 2026-09-23**

RA6E1 and **RA6M5 are both complete on both toolchains**, validated well beyond
the original bar — RA6M5 is also the first platform here with hardware crypto
actually doing the work rather than only supplying entropy. The remaining piece
is **RA8x2 single-core**, which opens 2026-10-19.

**TF-M 2.3 is future work (revised 2026-09-21).** TF-M 2.3 replaces Mbed TLS with
TF-PSA-Crypto, which has no `*_ALT` mechanism. It moves to the end of the plan,
after the rsip7 update — SCE9 acceleration is built on the 3.6 ALT route now and
redone as a PSA driver then. See DECISIONS D035.

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
| **Primary goal — RA8x2 single-core** | **~2026-11-27 (target)** |
| TF-M 2.3 / TF-PSA-Crypto | future — after the rsip7 update |
| Revised | 2026-09-21 |
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

**Done — RA6M5, both toolchains (2026-09-23, M4 met ~3 weeks early)**
- Full chain **BL2 → S → NS** on a CK-RA6M5 V2, GNUARM and IAR, on FSP 6.7.0-beta0.
- **SCE9 hardware crypto active** — the first platform here to use it for ciphers,
  hashes and ECC rather than entropy alone. BL2 hashes images on the engine too.
- TF-M's crypto is built from **FSP's own Mbed TLS**, not upstream, because FSP's
  `*_ALT` sources depend on its PSA core (DECISIONS D042).
- **PSA Arch on both toolchains** — crypto 63/0/1, attestation 1/0/0, storage 11/0/6,
  identical results, zero failures (D046).
- Three defects found in FSP's `*_ALT` sources, two now fixed in the pack
  (D041, D043, D044).

**Next — RA8x2 single-core (P5 opens Oct 19)**
- Hardware procurement is the gating item; the board must be in hand before P5.

**Primary goal — RA8x2 single-core (~late Nov)**
- TrustZone configuration + BSP update on FSP 6.7, GNUARM + IAR.

**Future — TF-M 2.3 / TF-PSA-Crypto (after the rsip7 update)**
- Rebase from the v2.2.0 fork point; SCE9 redone as a PSA transparent driver.

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
| **P4** | RA6M5 port + SCE9 crypto acceleration | 2026-09-15 | **2026-09-23** | ✅ done, 23d early |
| **P5** | RA8x2 single-core — TrustZone cfg + BSP | 2026-10-19 | 2026-11-27 | RA8x2 (key) |
| **P6** | *Stretch* — upstream to Arm TF-M | 2027-01-11 | 2027-03-26 | Stretch |
| **P7** | *Future* — TF-M 2.3 / TF-PSA-Crypto | after rsip7 | — | Future |

Critical path: **P4 → P5** (sequential under one engineer).

The primary goal moves forward three weeks, to ~Nov 27, because the TF-M 2.3
rebase that sat ahead of RA8x2 is now future work. P7 is undated.

---

## Phases

### P4 · RA6M5 port + SCE9 crypto acceleration (Sep 15 – Oct 16)
- RA6M5 RASC solution projects on FSP 6.7 (BL2 / secure / non-secure), partitioned,
  MCUboot dual-image — the RA6E1 pattern.
- `platform/ext/target/renesas/ra6m5`: memory map, `region_defs.h`, linker scripts
  (`.ld` + `.icf`), OFS guard.
- Full boot chain + crypto NSC app on silicon, **GNUARM and IAR**.
- PSA Arch suites, both toolchains.
- **SCE9 crypto acceleration** — RA6M5 has SCE9, the same engine as RA6E1/RA6M4
  (FSP namespaces it `BSP_FEATURE_RSIP_SCE9_SUPPORTED`; true RSIP parts are RA8).
  - **Route: FSP `rm_psa_crypto` `*_ALT` sources**, in
    `platform/ext/accelerator/renesas/sce9/` against TF-M's `crypto_hw.h`, with `cc312`
    as the structural template. **Per-engine directory on purpose** — RA8's RSIP is a
    different driver API and lands beside it as `renesas/rsip`. The Renesas wrapped-key
    vendor driver stays out: it depends on FSP's patched Mbed TLS.
  - **Built against FSP's Mbed TLS 3.6.6, not upstream** (D042). Pairing the ALT sources
    with upstream left multi-part GCM broken — FSP's changes live in the PSA core its
    ALTs are written against — so the port overlays FSP's `include/` and `library/` on
    upstream scaffolding of the same version.
  - Accelerated: cipher, AES, GCM, CMAC, SHA-256, ECP/ECDSA, RSA, and SHA-256 for BL2's
    image hash. **CCM stays in software** — FSP's SCE9 CCM caps associated data at
    110 B and Protected Storage exceeds it (D043).
  - `FSP_MODULES_NEVER_BUILT` (`r_sce`, `rm_psa_crypto`, FSP's mbedTLS) untangled, which
    was the substance of the work rather than a flag flip.
  - Regression gate met: PSA Arch crypto 63 passed / 0 failed / 1 skipped, the skip being
    deterministic ECDSA, which FSP does not support (D040).
- ✅ **Exit M4 met 2026-09-23** — RA6M5 full chain + crypto app on silicon, GNUARM and
  IAR, SCE9 ciphers active, all three PSA Arch suites passing on both toolchains (D046).
  Built and validated on FSP 6.7.0-beta0 ([[D047]]).

> **Sequencing note.** The ALT route is Mbed TLS 3.6-only. It is built now because
> TF-M 2.3 is deferred to P7, where SCE9 is redone as a PSA transparent driver.

### P5 · RA8x2 single-core — TrustZone cfg + BSP (Oct 19 – Nov 27)
- New `platform/ext/target/renesas/ra8x2`; RASC projects on FSP 6.7 ([[D047]]).
- TrustZone configuration (`target_cfg.c` — SAU/PPC/MPC), isolation HAL, DDSC bridge.
- BSP update: memory map, RSIP crypto driver, entropy source, Cortex-M85
  PACBTI / FPU-in-SPE.
- Linker scripts for both toolchains; boot chain + crypto NSC app.
- **Exit M5** — RA8x2 single-core full chain + crypto app, GNUARM + IAR.

### P6 · Stretch — upstream to the Arm TF-M repository (Jan 11 – Mar 26, 2027)
- **Submission is via Gerrit** (`review.trustedfirmware.org`), not a GitHub PR —
  `docs/contributing/contributing_process.rst`. The GitHub repo is a mirror.
- The 12 shared-file fixes as individual Gerrit changes; several
  (BL2 signing dependency, `MCUBOOT_ALIGN_VAL` cap) are platform-independent and
  can go early.
- `psa-arch-tests` target via GitHub PR — that repo *does* take PRs.
- Docs tree; accept the deprecation policy's maintenance commitment.
- **Gerrit changes target `main`, which is TF-PSA-Crypto.** Platform-independent
  fixes can go on their own; the port itself — and its SCE9 ALT wiring — is
  submittable only after P7. Items 9 and 11 are already fixed upstream; item 10 is
  obsolete there.
- **Exit M6** — RA6M5 (+ RA8x2) merged upstream. The port waits on P7.

### P7 · Future — TF-M 2.3 / TF-PSA-Crypto (after the rsip7 update)
- TF-M 2.3.0 pins TF-PSA-Crypto v1.1.0, 2.3.1 pins v1.1.1 — no Mbed TLS, no
  `*_ALT`. CC312's legacy ALT path is gone in 2.3.0.
- SCE9 acceleration redone as a PSA transparent driver — the rsip7 CM driver
  model, which is why this follows that update.
- Rebase from `dd2b7de19`: 10 of 20 shared files conflict; SPM logging rewritten
  (`lib/tfm_log`), so the trace option and RTT backend need porting; item 6 still
  needed at the moved `scripts/wrapper.py`. Detail in DECISIONS D035.
- **Exit M7** — RA6E1, RA6M5 and RA8x2 on 2.3.x with PSA-driver acceleration,
  both toolchains, suites green.

---

## Milestones

| ID | Date (target) | Gate |
|---|---|---|
| M1 | 2026-08-14 | ✅ RA6E1 BL2 → tfm_s boots on silicon |
| M2 | 2026-09-04 | ✅ Full RA6E1 boot + crypto NSC app (GNUARM) |
| M3 | **2026-09-14** | ✅ RA6E1 full chain + crypto app, GNUARM **and** IAR |
| M4 | **2026-09-23** | ✅ RA6M5 full chain, both toolchains, SCE9 ciphers active — 23 days early |
| **M5** | **~2026-11-27** | **RA8x2 single-core full chain + crypto app, GNUARM + IAR** (primary goal) |
| M6 | ~2027 Q1–Q2 | *Stretch* — merged into Arm TF-M upstream (port waits on M7) |
| M7 | future | *Future* — TF-M 2.3 / TF-PSA-Crypto, after the rsip7 update |

---

## Risks & buffer

| Severity | Risk |
|---|---|
| **High** | **RA8x2 new silicon on FSP 6.7.** First bring-up — M85 PACBTI/FPU, RSIP-E51A, TrustZone config. Concentrated in P5. |
| ~~Med~~ | ~~**SCE9 cipher wiring.**~~ **Retired 2026-09-23.** FSP's crypto stack and TF-M's mbedcrypto now coexist; the port builds TF-M's crypto from FSP's Mbed TLS. The ALT route remains Mbed TLS 3.6-only — redone as a PSA driver in P7, and every FSP ALT fix carried here is debt against that rebase. |
| Med | **IAR replication, round 2.** RA8x2 `.icf` / startup. Materially de-risked — the RA6E1 round is done and the patterns, hooks and three upstream fixes transfer. |
| Med | **Hardware.** An EK-RA8x2 must be procured before P5 — **Oct 19**, three weeks earlier than the previous plan. The RA6M5 board is in hand. 2× EK-RA6M4 bricked (RA6E1 was the RA6 vehicle). |
| Med | **TF-M 2.3 debt grows while deferred.** Every change to a shared file adds to the eventual P7 rebase, and upstream submission of the port waits on it. |
| ~~Low~~ | ~~**Open defects.**~~ **Both closed 2026-09-23.** `.ram_from_flash` now relocates at every isolation level under both toolchains ([[D048]]); the IAR NS toolchain emits `.srec` ([[D049]]). Remaining: the IAR NS build produces no `.map`. |

### Descoped 2026-09-14 — dual-core

The previous revision made **RA8x2 dual-core** the primary goal, with P5 dedicated
to binding FSP inter-core communication to TF-M's `tfm_hal_multi_core_*` /
`platform_mailbox`, an NS mailbox agent, and PSA call marshaling across cores.
It carried the two highest risks in the register: the mailbox integration itself
("no RA reference exists") and the unexamined core-topology question.

All of it is removed. RA8x2 is a single-core part for this project. Retained from
that leg: the base port, TrustZone config, BSP, and the NS + IAR + crypto-app work,
now consolidated into P5.

**Buffer.** Dates are targets. The RA8x2 leg holds Nov 30 – Dec 18 as contingency.
Everything is sequential under one engineer.

---

*Revised 2026-09-21 · RA6E1 done · RA6M5 ~2026-10-16 · RA8x2 single-core ~2026-11-27 · TF-M 2.3 after rsip7*
