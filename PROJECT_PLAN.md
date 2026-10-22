# TF-M on Renesas RA — RA6E1 → RA6M5 → RA8x2 (single-core), FSP 6.7, GNUARM + IAR

**Project plan · Firmware security · revised 2026-10-12**

RA6E1, **RA6M5 and RA8M2 are all complete on both toolchains**, validated well
beyond the original bar — RA6M5 was the first platform here with hardware crypto
doing the work rather than only supplying entropy, and RA8M2 adds RSIP-E50D,
measured boot verified from the boot record, and MCUboot secondary-slot upgrade.
**M5 was met 2026-10-09, 49 days early** (D106). What remains on the primary
track is FWU on RA6M5.

**TF-M 2.3 is future work (revised 2026-09-21).** TF-M 2.3 replaces Mbed TLS with
TF-PSA-Crypto, which has no `*_ALT` mechanism. It moves to the end of the plan,
after the rsip7 update — SCE9 acceleration is built on the 3.6 ALT route now and
redone as a PSA driver then.

> **This does not match [[D035]], which should be read first.** [[D035]] is Accepted and says
> the 2.3 rebase is **cancelled** and "P5 of PROJECT_PLAN.md is cancelled" — not deferred. No
> later entry records the reopening this paragraph assumes. Either the position changed without
> a decision entry, or this paragraph is wrong; it needs an entry that supersedes [[D035]]
> before anyone plans against it.

**Scope change — RA8x2 is single-core.** The previous revision built the whole
RA8x2 leg around dual-core operation and binding FSP's inter-core comms to
TF-M's mailbox HAL. That is **descoped**: RA8x2 work is now the TrustZone
configuration and BSP update for a single-core part. This removes an entire
phase and **both High risks** from the register — see *Descoped* below.

**All dates below are targets, not commitments.** An overrun shifts subsequent
dates rather than cutting scope.

> [`PROJECT_PLAN.html`](PROJECT_PLAN.html) is a **hand-made summary page**, not a render of
> this file, and it drifts. For an HTML view that is generated from this document and checked
> for staleness on every commit, use
> [`docs/learning/ref/PROJECT_PLAN.html`](docs/learning/ref/PROJECT_PLAN.html)
> (`scripts/build_doc_html.py --check` enforces it).

| | |
|---|---|
| **RA6E1 (GNUARM + IAR)** | **done 2026-09-14** (target was ~09-25) |
| **RA6M5 — upstream vehicle** | **done 2026-09-23** (target was ~10-16) |
| **Primary goal — RA8x2 single-core** | **done 2026-10-09** (target was ~11-27) |
| TF-M 2.3 / TF-PSA-Crypto | future — after the rsip7 update |
| Revised | 2026-10-12 |
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

**Done — RA8M2 single-core, both toolchains (2026-10-09, M5 met 49 days early)**
- Started ~3.5 weeks before its Oct 19 window, because P4 finished 23 days early.
- **BL2, `tfm_s` and `tfm_ns` all build and link, on BOTH toolchains** (IAR then GNUARM).
- Memory map, OFS placement and M85 TCM attribution verified pre-silicon; the OFS brick
  guard passes on both toolchains with six discrete per-word segments.
- Full chain **BL2 → S → NS** on an EK-RA8M2, GNUARM and IAR, on FSP 6.7.
- **PSA Arch identical on both toolchains** — crypto 62/1/1, attestation 1/0/0,
  storage 11/0/6. The single failure is crypto 216, plaintext RSA-2048 keygen,
  which RSIP-E50D has no primitive for (D111) — not a port defect.
- **Measured boot verified from the boot record**, not inferred from a passing
  attestation suite — both SHA-256 TLVs matched (D096, D105).
- **MCUboot secondary-slot upgrade proven** on both toolchains, install and erase
  (D100, D106).
- RSIP-E50D active; **RA8M2 image 0's slot order is reversed** — secondary sits
  below primary.
- Still carried, neither gating M5: the `BSP_TZ_CFG_MSAR=0` workaround pending an
  e2 generator fix (D093), and FWU on RA6M5.
- Note the part is **RA8M2** (R7KA8M2JFLCAC) with **RSIP-E50D**, not SCE9; earlier revisions
  of this plan said RSIP-E51A.

**~~Primary goal — RA8M2 single-core (~late Nov)~~ — done 2026-10-09** ([[D106]])
- TrustZone configuration + BSP update on FSP 6.7, GNUARM + IAR. Both toolchains build, the
  full chain runs on hardware, and the PSA Arch suites pass on both. Isolation 1+IPC, 2 and 3
  followed on 2026-10-22 ([[D124]]).

**Future — TF-M 2.3 / TF-PSA-Crypto (after the rsip7 update)**
- Rebase from the v2.2.0 fork point; SCE9 redone as a PSA transparent driver.

**Future — NS image in OSPI, executed in place (last, after TF-M 2.3)**
- Relieves the RA8M2 MRAM budget: 1 MB cannot hold four slots plus the PSA Arch
  crypto suite with usable headroom.

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
| **P5** | RA8x2 single-core — TrustZone cfg + BSP | **2026-09-24** | **2026-10-09** | ✅ done, 49d early |
| **P6** | *Stretch* — upstream to Arm TF-M | 2027-01-11 | 2027-03-26 | Stretch |
| **P7** | *Future* — TF-M 2.3 / TF-PSA-Crypto | after rsip7 | — | Future |
| **P8** | *Future* — NS image in OSPI (XIP) | after P7 | — | Future |

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
    different driver API and lands beside it as `platform/ext/accelerator/renesas/rsip_e50d` ([[D050]]). The Renesas wrapped-key
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

### P5 · RA8x2 single-core — TrustZone cfg + BSP (Sep 24 – Oct 9)
- New `platform/ext/target/renesas/ra8m2` (the directory is `ra8m2`, not `ra8x2`); RASC projects on FSP 6.7 ([[D047]]).
- TrustZone configuration (`target_cfg.c` — SAU/PPC/MPC), isolation HAL, DDSC bridge.
- BSP update: memory map, RSIP crypto driver, entropy source, Cortex-M85
  PACBTI / FPU-in-SPE.
- Linker scripts for both toolchains; boot chain + crypto NSC app.
- ✅ **Exit M5 met 2026-10-09** — RA8M2 single-core full chain on silicon, GNUARM and
  IAR, all three PSA Arch suites identical across toolchains, measured boot verified
  from the record, MCUboot upgrade proven. 49 days early. Evidence table in D106.

### P6 · Stretch — upstream to the Arm TF-M repository (Jan 11 – Mar 26, 2027)
- **Submission is via Gerrit** (`review.trustedfirmware.org`), not a GitHub PR —
  `docs/contributing/contributing_process.rst`. The GitHub repo is a mirror.
- The shared-file fixes as individual Gerrit changes - 10 live defect fixes plus 2 additions per [[D117]]; several
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
- **Restore P-521 and Curve25519 on RA8M2.** Dropped in D059 for flash — the two
  curves cost 22,977 bytes of HW procedure tables. Deleting the two `#undef`s in
  `rsip_e50d/crypto_accelerator_config.h` is the whole change; then re-run the PSA
  Arch crypto suite at profile_large, which is what exercises them. E50D has the
  hardware; the port simply stops advertising it until there is room.
- **Exit M7** — RA6E1, RA6M5 and RA8x2 on 2.3.x with PSA-driver acceleration,
  both toolchains, suites green, and the RA8M2 curve set back to the engine's full
  capability.

### P8 · Future — NS image in OSPI, executed in place (after P7)

**Why.** RA8x2 has 1 MB of MRAM and no data flash. Four MCUboot slots, BL2 and the
ITS/PS/NV-counter area exhaust it, and the PSA Arch crypto suite is the largest NS
image we build. Moving image 1 out of MRAM returns both NS slots to the secure side
and removes the squeeze rather than trimming a configuration to fit it.

**Scope.**
- Image 1 primary + secondary slots move to OSPI; MRAM keeps BL2, the secure slots
  and the storage area.
- NS executes in place from OSPI — `ospi_b` configured and the flash mapped before
  BL2 verifies image 1, so the OSPI bring-up moves into BL2, not just the SPE.
- A third `Driver_FLASH` instance for OSPI, and `flash_layout.h` gains a per-area
  driver mapping (one device per area is assumed in several places today).
- SAU/IDAU: the OSPI window is partitioned in the azone already
  (`OSPI0_CS1_CPU0_S` / `_N`) — image 1 sits in the NS half.
- XIP performance and cache behaviour on M85 are open: OSPI fetch latency against
  MRAM, and whether the NS image needs the I-cache warmed or a critical path copied
  to RAM.

**Why last.** It touches `flash_layout.h`, the flash driver layer and BL2 — all of
which P7 rewrites against TF-PSA-Crypto. Doing it first would be done twice.

- **Exit M8** — RA8x2 boots with image 1 resident in and executed from OSPI, both
  toolchains, PSA Arch suites green with MRAM headroom restored.

---

## Milestones

| ID | Date (target) | Gate |
|---|---|---|
| M1 | 2026-08-14 | ✅ RA6E1 BL2 → tfm_s boots on silicon |
| M2 | 2026-09-04 | ✅ Full RA6E1 boot + crypto NSC app (GNUARM) |
| M3 | **2026-09-14** | ✅ RA6E1 full chain + crypto app, GNUARM **and** IAR |
| M4 | **2026-09-23** | ✅ RA6M5 full chain, both toolchains, SCE9 ciphers active — 23 days early |
| **M5** | **2026-10-09** | ✅ RA8M2 single-core full chain, both toolchains, RSIP-E50D, measured boot + MCUboot upgrade verified — 49 days early |
| M6 | ~2027 Q1–Q2 | *Stretch* — merged into Arm TF-M upstream (port waits on M7) |
| M7 | future | *Future* — TF-M 2.3 / TF-PSA-Crypto, after the rsip7 update |
| M8 | future | *Future* — RA8x2 NS image in OSPI, executed in place (after M7) |

---

## Risks & buffer

| Severity | Risk |
|---|---|
| ~~High~~ | ~~**RA8x2 new silicon on FSP 6.7.**~~ **Retired 2026-10-09.** First bring-up carried M85 FPU/caches, RSIP-E50D and TrustZone config. All of it is now exercised on silicon on both toolchains, with the PSA Arch suites identical across them. The one first-boot surprise was MRAM's MRCPFB being non-secure (D092/D093), worked around and tracked. |
| ~~Med~~ | ~~**SCE9 cipher wiring.**~~ **Retired 2026-09-23.** FSP's crypto stack and TF-M's mbedcrypto now coexist; the port builds TF-M's crypto from FSP's Mbed TLS. The ALT route remains Mbed TLS 3.6-only — redone as a PSA driver in P7, and every FSP ALT fix carried here is debt against that rebase. |
| ~~Med~~ | ~~**IAR replication, round 2.**~~ **Retired 2026-09-25.** RA8M2 builds and links on **both** toolchains. IAR came first; GNUARM then found two defects IAR had masked — an archive-ordering dependency for the `gp_ddsc_*` TCM symbols, and `Debug` not fitting. The `.icf`/startup patterns transferred as expected. |
| ~~Med~~ | ~~**Hardware.**~~ **Retired 2026-09-25.** The EK-RA8M2 boards are in hand, ahead of the Oct 19 need-by. The RA6M5 board is in hand. 2× EK-RA6M4 remain bricked (RA6E1 was the RA6 vehicle) — the reason the OFS brick guard exists. |
| ~~Med~~ | ~~**RA8x2 MRAM budget.**~~ **Retired 2026-09-25 — measured.** `tfm_s` at profile_large/L3/IPC is 204 KB in a 293 KB region (**+87 KB**); GNUARM MinSizeRel leaves +26 KB; the PSA Arch crypto NS image fits with +1.5 KB. `Debug` is what was tight all along, and it does NOT fit on GNUARM at all (~414 KB) — so **MinSizeRel is a requirement, not a preference**. P8 (NS in OSPI) is no longer needed to make the budget work. |
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


### Test coverage gaps — suites never run on ANY part (surveyed 2026-10-06)

Enumerated from `tf-m-tests` and `psa-arch-tests` and checked against every build tree in
`C:\b`. **Surveyed 2026-10-06; the IPC and isolation rows have since been closed.**

| Suite | Option | Why it has not run | Applicable? |
|---|---|---|---|
| **Firmware Update** | `TEST_S_FWU`, `TEST_NS_FWU` | `TFM_PARTITION_FIRMWARE_UPDATE` is OFF on both parts | **Yes - highest value.** Exercises the PSA FWU API over the MCUboot slots this port already has. RA8M2 secure slot has ~670 B spare, so the partition may not fit without turning something off. **The bootloader half is now proven** - BL2 installs both images from their secondary slots and erases them ([[D100]]) - so what FWU adds is the API that *places* an image there |
| **IPC model** | `TEST_S_IPC`, `TEST_NS_IPC` | **CLOSED 2026-10-22.** Ten regression trees now run the IPC backend at isolation 1, 2 and 3 on both parts and both toolchains, `TFM_S_IPC_TEST_1001`-`1012` included | Done - [[D113]] to [[D124]] |
| **Isolation 2 / 3** | `TFM_ISOLATION_LEVEL` | **CLOSED 2026-10-22.** The suite had never run above isolation 1 before [[D113]]; it is now green at L1+IPC, L2 and L3 on RA6M5 and RA8M2, GNUARM and IAR | Done - [[D124]] |
| **SLIH above isolation 1** | `CONFIG_TFM_SLIH_API` | only the FLIH fixture has been run above L1. The SLIH service declares the same `mmio_region` and has never been exercised there | **Yes, cheap** - the trees and launches already exist |
| **PSA Arch IPC suite** | `TEST_PSA_API=IPC` | only CRYPTO, INITIAL_ATTESTATION and STORAGE have been built. TF-M accepts `IPC`, and `psa-arch-tests/api-tests/ff/{ipc,partition}` exists | **Yes.** The Firmware Framework suite - different from the dev_apis ones already run |
| **FPU** | `TEST_S_FPU`, `TEST_NS_FPU` | `CONFIG_TFM_ENABLE_CP10CP11=OFF` - the port is soft-float throughout | Only if FP is ever enabled. RA8M2 is Cortex-M85 with FP hardware, so this is a real gap for that part |
| **NSID management** | `TEST_NS_MANAGE_NSID` | `TFM_NS_MANAGE_NSID` not set | Yes, cheap. Checks non-secure client ID handling |
| **QCBOR / t_cose** | `TEST_NS_QCBOR`, `TEST_NS_T_COSE` | never enabled | Yes, cheap. Both libraries are already linked for attestation, so this is self-test of code that already ships |
| **Multi-core** | `TEST_NS_MULTI_CORE` | `TFM_MULTI_CORE_TOPOLOGY=OFF`; dual-core was descoped 2026-09-14 | Not applicable while CPU1 is unused, but RA8M2 **is** dual-core - revisit with `RA8x2_DUAL_CORE_DESIGN.md` |

**Also uncovered, found 2026-10-08 ([[D099]]):** `mbedtls_aes_crypt_ctr()` in FSP 6.7's
`aes_alt.c` ignores `nc_off`/`stream_block` and mishandles partial blocks - the defect D041
fixed - yet PSA Arch 236/237 pass on both parts, short-input CTR checks included. The PSA cipher
layer never reaches that function with a partial block, so no suite we run can see the bug. A
direct Mbed TLS CTR caller still hits it. Needs a unit test against `mbedtls_aes_crypt_ctr()`
itself, not another PSA-level suite.

**Already covered, for contrast:** PS, ITS, Crypto, Attestation, Platform, SFN backend, FLIH IRQ
(`*_TFM_flih_*`) and SLIH IRQ (`*_TFM_slih_*`, `TEST_NS_SLIH_IRQ=ON` in the slih trees), plus
PSA Arch crypto / attestation / storage.

**Order I would take them:** FWU first - it is the one with a user-visible feature behind it, and
the MCUboot half beneath it is now run and passing ([[D100]]). Then PSA Arch IPC, then the cheap ones (NSID,
QCBOR, t_cose) as a single regression variant. FPU only if soft-float is revisited.

## TODO

- **FSP pack uprev for both ports, once both are ready.** RA6M5 and RA8M2 are each
  on the **same** 6.7.0-beta0 pack, `+20260925.818e720c`, since the regeneration in [[D057]]
  — all twelve projects and all four solutions. The "do it as one change" rationale still holds
  for the next uprev.
  When both ports are green, regenerate every project against the then-current FSP
  and re-run the suites on hardware. Do it as one change across both parts, not
  per-port: the two share `fsp_mbedtls.cmake`, the ALT overlay and the TF-M patch
  set, so staggering them means validating the shared layer twice.
  - Watch for: Mbed TLS version movement (3.6.6 has held across the last two
    uprevs), `rm_psa_crypto` ALT-source changes, and regenerated `configuration.xml`
    version stamps, which produce large but empty diffs.

- **Audit the port for values that override FSP-generated configuration.** The port's
  contract is that FSP config is *consumed*, not restated: the user configures in
  e2/RASC and the TF-M build follows. `FLASH_AREA_IMAGE_SECTOR_SIZE` broke that on
  RA8M2 — the port defined `0x1000` while FSP's generated
  `ra_cfg/mcu-tools/include/mcuboot_config/mcuboot_config.h` defines it as
  `RM_MCUBOOT_MRAM_BLOCK_SIZE` (`0x8000`), and that directory is on the include path,
  so it was a conflicting redefinition producing a layout that only fails on hardware.
  - Fixed by taking FSP's value, but as a **literal** — `flash_layout.h` is preprocessed
    into the BL2 linker script and cannot include `mcuboot_config.h` (which pulls
    `bsp_api.h`). The proper fix is to extract `RM_MCUBOOT_MRAM_BLOCK_SIZE` into the
    generated `bsp_partitions.h`, the mechanism already used for the partitions.
  - Then sweep for other instances, on **both** ports: anything the port `#define`s that
    FSP also generates. `MCUBOOT_ALIGN_VAL` / `MCUBOOT_BOOT_MAX_ALIGN` and
    `MCUBOOT_MAX_IMG_SECTORS` are the obvious neighbours; `MCUBOOT_MAX_IMG_SECTORS`
    legitimately differs, since TF-M has its own flash map, and that distinction should
    be recorded rather than left to be rediscovered.

- **~~Write `BRIDGING_FILES.md`~~ — done ([[D089]]); still run its checks before the pack uprev above, not after.** A number of files
  carry all or part of FSP's code, or restate FSP-generated configuration, but are not FSP
  files and do not move when the packs do. Nothing in the build compares them against their
  origin, so they drift silently into constants that link cleanly and are wrong at run time —
  which has already happened three times (D054, and the `sce9` path and `SCE9_SUPPORTED`
  errors found on 2026-09-24). The document must give, per file, its FSP origin, what was
  changed, and **the check that detects drift**. Inventory and categories are in
  [DOCUMENTATION_PLAN.md](DOCUMENTATION_PLAN.md).

- **Use the MRAM hardware rollback counter — after TF-M 2.3.** `R_MRAM` exposes
  `AntiRollbackCounterIncrement` / `Refresh` / `Read`. These are a better home for
  MCUboot's NV counters than the emulated-OTP region in `DF_EMULATION`, and would free
  part of it. Deferred past P7 deliberately: TF-M 2.3 reworks the platform NV-counter
  interface, so doing it first means doing it twice.

---

*Revised 2026-10-22 · RA6E1 done · RA6M5 done · RA8M2 single-core done 2026-10-09 · TF-M 2.3 after rsip7 · NS-in-OSPI last*
