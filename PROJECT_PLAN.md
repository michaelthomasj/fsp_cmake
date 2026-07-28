# TF-M on Renesas RA — RA6 → RA8x2 (dual-core), FSP 6.6, GNUARM + IAR

**Project plan · Firmware security · revised after stakeholder review**

Stakeholders are primarily interested in **RA8x2 (dual-core)** running Trusted
Firmware-M. TF-M supports a multi-core topology, but RA8x2 requires binding
**FSP's inter-core communication to TF-M's mailbox HAL** — the project's biggest
technical unknown. IAR is required. A working demo is needed by **mid-September**.

Because the engineer is out the **first and last weeks of August**, the mid-Sept
window is only ~5 working weeks, so the plan splits into two horizons and
**defers psa-arch-tests**.

> A rendered version of this plan is in [`PROJECT_PLAN.html`](PROJECT_PLAN.html).

| | |
|---|---|
| **Mid-Sept checkpoint** | **2026-09-15 — RA6 full chain, GNUARM + IAR** |
| **Primary goal (RA8x2 dual-core)** | **2026-12-18** |
| Revised | 2026-07-28 |
| Toolchains | GNUARM + IAR |
| Deferred | psa-arch-tests → Q1 2027 |
| Stretch — upstream | Q2 2027 |
| Resourcing | 1 engineer (out Aug 3–7 and Aug 24–28) |

---

## Snapshot

**Done — baseline**
- **RA6E1 BL2 boots on silicon** (TF-M v2.2, FSP 6.1): flash init, NV-counter init, MCUboot image search.
- **Flash driver** ported (data-flash NV counters working); OFS brick-guard in place.
- Modular CMake consuming RASC output; RTT logging.

**Mid-Sept checkpoint (Sep 15)**
- **RA6** full secure boot chain (BL2 → S → NS) on silicon.
- **GNUARM + IAR**, both building/booting.
- Stays on the current **FSP 6.1** baseline (no rebase) to protect the date.

**Primary goal — RA8x2 dual-core (~Dec 18)**
- **RA8x2** on **FSP 6.6**: SPE on one core, NSPE on the other.
- **FSP inter-core comms bound to TF-M's mailbox HAL** (`tfm_hal_multi_core_*` / `platform_mailbox`); PSA calls marshaled across cores.
- GNUARM + IAR.

**Deferred / not now**
- psa-arch-tests → Q1 2027 (dropped from the near-term).
- Upstream merge to Arm TF-M → stretch, Q2 2027.
- ARMCLANG toolchain.

---

## Timeline

Engineer out: **Aug 3–7** and **Aug 24–28** (reflected in the phase dates below).

| Phase | Work | Start | End | Track |
|---|---|---|---|---|
| **P1** | RA6 secure image (tfm_s) — GNUARM, FSP 6.1 | 2026-07-28 | 2026-08-14 | RA6 |
| **P2** | RA6 non-secure · full boot chain (GNUARM) | 2026-08-17 | 2026-08-21 | RA6 |
| **P3** | IAR toolchain for RA6 → **mid-Sept demo** | 2026-08-31 | 2026-09-11 | Key deliverable |
| **P4** | RA8x2 base port — BL2 + SPE on primary core (FSP 6.6) | 2026-09-16 | 2026-10-16 | RA8x2 |
| **P5** | Dual-core — FSP ICC ↔ TF-M mailbox HAL | 2026-10-19 | 2026-11-20 | RA8x2 |
| **P6** | RA8x2 NS + IAR + consolidation → **primary goal** | 2026-11-23 | 2026-12-18 | Key deliverable |
| **P7** | *Deferred* — psa-arch-tests (RA6 + RA8x2) | 2027-01-05 | 2027-02-05 | Deferred |
| **P8** | *Stretch* — upstream to Arm TF-M | 2027-02-15 | 2027-04-24 | Stretch |

Critical path: **P1 → P2 → P3** (to the Sept 15 demo) **→ P4 → P5 → P6** (to the RA8x2 dual-core goal).

---

## Phases

### P1 · RA6 secure image (tfm_s) — GNUARM, FSP 6.1 (Jul 28 – Aug 14, spans Aug 3–7 out)
- Generate RA6 TrustZone-Secure RASC project; wire DDSC symbols (`fsp_gen.ld` + `bsp_linker_info.h`) into the tfm_s link.
- Resolve `bsp_security.c`; decide SAU ownership — `tfm_hal_isolation.c` / `target_cfg.c` vs FSP `R_BSP_SecurityInit`.
- Platform HAL: `tfm_hal_platform_init`, `tfm_platform_system.c` (reset / IOCTL / NV-counter API); OTP HAL + lifecycle-state so first-boot dummy provisioning runs.
- Build + sign tfm_s; BL2 validates & chainloads it.
- **Exit M1** — RA6 BL2 → tfm_s boots on silicon.

### P2 · RA6 non-secure & full boot chain, GNUARM (Aug 17 – Aug 21)
- NS RASC project downstream of secure; consume veneer / CMSE import library.
- `ns/CMakeLists.txt`, `cpuarch_ns.cmake`, S→NS transition.
- Full BL2 → S → NS boot, proven over RTT.
- **Exit M2** — full RA6 boot chain (GNUARM).

### P3 · IAR toolchain for RA6 → mid-Sept demo (Aug 31 – Sep 11; after Aug 24–28 out)
- IAR linker `.icf` for BL2 / S / NS: replicate per-word OFS, veneer / NSC placement, TZ regions (GCC `.ld` → IAR `.icf`).
- IAR startup + toolchain CMake; build BL2 → S → NS under IAR; boot on RA6E1 silicon.
- **Exit M3 (Sep 15) — DEMO: RA6 full chain, GNUARM + IAR, on silicon.**

### P4 · RA8x2 base port — BL2 + SPE on primary core, FSP 6.6 (Sep 16 – Oct 16)
- New `platform/ext/target/renesas/ra8x2`; RA8x2 RASC projects on FSP 6.6; reuse RA6 patterns (DDSC, secure project, isolation, veneer).
- Settle the **core topology**: which core runs SPE vs NSPE; TZ-on-M85 + M33-as-NS-core vs pure multi-core (drives the whole mailbox design).
- RA8x2 specifics: memory map, RSIP crypto driver, Cortex-M85 PACBTI / branch-protection + FPU-in-SPE.
- **Exit M4** — RA8x2 SPE boots on the primary core.

### P5 · Dual-core — FSP ICC ↔ TF-M mailbox HAL (Oct 19 – Nov 20)
- Implement TF-M's multi-core mailbox HAL (`tfm_hal_multi_core_*`, `platform_mailbox`) on top of **FSP inter-core communication** (shared memory + semaphore/IPC).
- NS mailbox agent on the NSPE core; marshal PSA client calls across cores; boot both cores.
- **Exit M5** — a PSA call marshaled NSPE-core → SPE-core over FSP ICC completes.

### P6 · RA8x2 NS + IAR + consolidation → primary goal (Nov 23 – Dec 18)
- NSPE application on the second core; end-to-end dual-core boot + PSA services.
- IAR `.icf` / startup for RA8x2 (both cores); build + boot under IAR.
- Consolidation + stakeholder sign-off.
- **Exit M6 — RA8x2 dual-core full chain, GNUARM + IAR.**

### P7 · Deferred — psa-arch-tests, RA6 + RA8x2 (Jan 5 – Feb 5, 2027)
- Integrate psa-arch-tests; `TFM_DUMMY_PROVISIONING` (dummy IAK/ROTPK match the TF-M test keys); split SPE/NSPE build.
- Wire service HALs the suites exercise: entropy / RSIP TRNG (crypto), `its_flash_fs` (ITS), `ps_nv_counters` (PS), boot-seed + device-ID + IAK (attestation).
- Run on RA6E1 + RA8x2; iterate to targeted green.
- **Exit M7** — targeted PSA arch tests pass.

### P8 · Stretch — upstream to the Arm TF-M repository (Feb 15 – Apr 24, 2027)
- Docs tree: vendor `index.rst` + per-platform entry + `platform_introduction.rst`, added to `docs/platform/index.rst`.
- Accept the deprecation policy's **ongoing-maintenance commitment**; maintainer sign-off + CI; submit via review.trustedfirmware.org (Gerrit).
- Not mandatory for this customer — bounded by external review latency.
- **Exit M8** — RA6 + RA8x2 merged upstream (review-latency dependent).

---

## Platform HAL surface — what each target must implement

| Area | Items |
|---|---|
| **Boot & isolation** | startup + linker, OFS (BL2); `target_cfg.c` (SAU/PPC/MPC); `tfm_hal_isolation.c` + static boundaries |
| **Multi-core (RA8x2)** | `tfm_hal_multi_core_*` + `platform_mailbox` over FSP ICC; NS mailbox agent; PSA call marshaling |
| **Storage** | `Driver_FLASH0/1` (code + data); `its_flash_fs` HAL (ITS); `ps_nv_counters` (PS) |
| **Crypto & entropy** | RSIP crypto driver; entropy / TRNG source; crypto key HAL |
| **Identity & provisioning** | OTP HAL + lifecycle state; IAK + BL2 ROTPKs (dummy for dev/tests); NV counters backend |
| **Platform service** | system reset; IOCTL entry point; NV-counter increment / read API |
| **Attestation & NS** | boot seed, implementation / device ID; NS `ns/CMakeLists` + `cpuarch_ns`; veneer / CMSE import library |

---

## Milestones

| ID | Date | Gate |
|---|---|---|
| M1 | 2026-08-14 | RA6 BL2 → tfm_s boots on silicon |
| M2 | 2026-08-21 | Full RA6 boot chain BL2 → S → NS (GNUARM) |
| **M3** | **2026-09-15** | **DEMO — RA6 full chain, GNUARM + IAR, on silicon** (mid-Sept checkpoint) |
| M4 | 2026-10-16 | RA8x2 SPE boots on the primary core (FSP 6.6) |
| M5 | 2026-11-20 | RA8x2 dual-core: PSA call marshaled NSPE-core → SPE-core over FSP ICC |
| **M6** | **2026-12-18** | **RA8x2 dual-core full chain, GNUARM + IAR** (primary goal) |
| M7 | 2027-02-05 | *Deferred* — targeted psa-arch-tests pass (RA6 + RA8x2) |
| M8 | ~2027 Q2 | *Stretch* — RA6 + RA8x2 merged into Arm TF-M upstream |

---

## Risks & buffer

| Severity | Risk |
|---|---|
| **High** | **Mid-Sept is tight, with little slack.** RA6 secure-image (DDSC + SAU/isolation) is still an unknown and is compressed into ~5 working weeks around two absences, plus IAR. Any snag in P1 or P3 slips the Sep 15 demo directly — there is minimal buffer in this leg. |
| **High** | **Dual-core mailbox integration.** Binding FSP inter-core comms to TF-M's `tfm_hal_multi_core` / `platform_mailbox` is the project's biggest unknown; no RA reference exists. Concentrated in P5. |
| **High** | **RA8x2 core-topology decision.** Which core runs SPE vs NSPE, and TZ-on-M85 + M33-as-NS-core vs pure multi-core, sets the entire mailbox design. Must be settled at the start of P4. |
| **High** | **IAR replication.** OFS / veneer / TZ placement + startup as IAR `.icf`; IAR TZ/veneer handling differs from GCC. On the critical path for both the Sep 15 demo (RA6) and the Dec goal (RA8x2). |
| **High** | **FSP 6.6 for RA8x2.** First use for the dual-core + SAU-reach-NS + RA8 support; regen churn and unverified dual-core generation. |
| Med | **New silicon.** First RA8x2 bring-up (M85 PACBTI/FPU, RSIP, dual-core boot). |
| Med | **Hardware.** An EK-RA8x2 (dual-core) board must be procured before P4; 2× EK-RA6M4 bricked (RA6E1 is the RA6 vehicle). |
| Med | **No PSA conformance at the Dec goal.** psa-arch-tests are deferred to Q1 2027, so there is no formal PSA evidence at M6 — stakeholders have accepted this. |

**Buffer.** The mid-Sept leg (P1–P3) is **constraint-driven, not buffer-driven** — it is aggressive and carries little slack; the two August absences already consume the margin. The RA8x2 leg (P4–P6) carries ~20–25% internal buffer and holds the Dec 21 – Jan 2 year-end period as contingency. Everything is sequential under one engineer.

---

*Revised 2026-07-28 · Mid-Sept checkpoint 2026-09-15 · RA8x2 dual-core goal 2026-12-18 · GNUARM + IAR · psa-arch-tests deferred*
