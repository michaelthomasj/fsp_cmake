# TF-M on Renesas RA — RA6 → RA8x2 (dual-core), FSP 6.6, GNUARM + IAR

**Project plan · Firmware security · revised after stakeholder review**

Stakeholders want **RA8x2 (dual-core)** running Trusted Firmware-M — which means
binding **FSP's inter-core communication to TF-M's mailbox HAL**, the project's
biggest technical unknown. IAR is required. RA6 is finished first (both
toolchains) as the foundation.

**Validation is deliberately light: a simple boot test plus a basic-crypto app
that exercises a Non-Secure-Callable (NSC) entry** — enough to prove the
S → NS split and the veneer path end to end. No psa-arch-tests / formal
conformance suite in this plan.

**All dates below are targets, not commitments.** With the engineer out the
first and last weeks of August, and delivering real dual-core RA8x2 valued over
hitting a fixed date, an overrun shifts subsequent dates rather than cutting
scope.

> A rendered version of this plan is in [`PROJECT_PLAN.html`](PROJECT_PLAN.html).

| | |
|---|---|
| **RA6 working (GNUARM + IAR)** | **~2026-09-25 (target)** |
| **Primary goal — RA8x2 dual-core** | **~2026-12-18 (target)** |
| Revised | 2026-07-28 |
| Toolchains | GNUARM + IAR |
| Validation | boot test + basic-crypto NSC app |
| Resourcing | 1 engineer (out Aug 3–7 and Aug 24–28) |

---

## Snapshot

**Done — baseline**
- **RA6E1 BL2 boots on silicon** (TF-M v2.2, FSP 6.1): flash init, NV-counter init, MCUboot image search.
- **Flash driver** ported (data-flash NV counters working); OFS brick-guard in place.
- **DDSC blocker solved** — `bsp_security.c` compiles via a `gp_ddsc_*` bridge valued from `region_defs.h` (`ra6e1_ddsc.c`), no FSP `bsp_linker.c` / `__ddsc_*` needed.

**RA6 target (~late Sept)**
- Full secure boot chain **BL2 → S → NS** on silicon.
- **Basic-crypto NSC app** (existing test app) run to verify the veneer / NSC path.
- **GNUARM then IAR**, both building / booting.
- Stays on the current **FSP 6.1** baseline (no rebase) to save time.

**Primary goal — RA8x2 dual-core (~Dec)**
- **RA8x2** on **FSP 6.6**: SPE on one core, NSPE on the other.
- **FSP inter-core comms bound to TF-M's mailbox HAL** (`tfm_hal_multi_core_*` / `platform_mailbox`); PSA calls marshaled across cores.
- Same light validation (boot + crypto NSC app); GNUARM + IAR.

**Out of scope**
- psa-arch-tests / formal PSA conformance (validation is boot + the crypto NSC app).
- Upstream merge to Arm TF-M → stretch (P7).
- ARMCLANG toolchain.

---

## Timeline

Engineer out: **Aug 3–7** and **Aug 24–28** (reflected in the phase dates).

| Phase | Work | Start | End | Track |
|---|---|---|---|---|
| **P1** | RA6 secure image (tfm_s) — GNUARM, FSP 6.1 | 2026-07-28 | 2026-08-14 | RA6 |
| **P2** | RA6 non-secure · full boot · crypto NSC app (GNUARM) | 2026-08-17 | 2026-09-04 | RA6 |
| **P3** | IAR toolchain for RA6 | 2026-09-07 | 2026-09-25 | RA6 (key) |
| **P4** | RA8x2 base port — BL2 + SPE on primary core (FSP 6.6) | 2026-09-28 | 2026-10-23 | RA8x2 |
| **P5** | Dual-core — FSP ICC ↔ TF-M mailbox HAL | 2026-10-26 | 2026-11-20 | RA8x2 |
| **P6** | RA8x2 NS + IAR + crypto NSC app → **primary goal** | 2026-11-23 | 2026-12-18 | RA8x2 (key) |
| **P7** | *Stretch* — upstream to Arm TF-M | 2027-01-11 | 2027-03-26 | Stretch |

Critical path: **P1 → P2 → P3 → P4 → P5 → P6** (sequential under one engineer).

---

## Phases

### P1 · RA6 secure image (tfm_s) — GNUARM, FSP 6.1 (Jul 28 – Aug 14, spans Aug 3–7 out)
- Generate the RA6E1 secure RASC project (full set); wire it as `FSP_S_APP_DIR`.
- **DDSC** resolved: `gp_ddsc_*` provided from `region_defs.h` (`ra6e1_ddsc.c`, force-included decls); FSP `bsp_linker.c` excluded — proven, `bsp_security.o` compiles.
- Resolve remaining secure-BSP wiring (crypto-stack includes from the generated `common_data`); build + sign tfm_s; BL2 chainloads it.
- **Exit M1** — RA6 BL2 → tfm_s boots on silicon.

### P2 · RA6 non-secure · full boot · crypto NSC app — GNUARM (Aug 17 – Sep 4, spans Aug 24–28 out)
- NS RASC project downstream of secure; veneer / CMSE import library; `ns/CMakeLists.txt`, `cpuarch_ns.cmake`.
- Full BL2 → S → NS boot, proven over RTT.
- **Run the basic-crypto NSC app** to verify a PSA crypto call across the veneer / NSC boundary.
- **Exit M2** — full RA6 boot + crypto NSC app verified (GNUARM).

### P3 · IAR toolchain for RA6 (Sep 7 – Sep 25)
- IAR linker `.icf` for BL2 / S / NS: replicate per-word OFS, veneer / NSC placement, TZ regions (GCC `.ld` → IAR `.icf`).
- IAR startup + toolchain CMake; build BL2 → S → NS under IAR; boot + crypto NSC app on RA6E1.
- **Exit M3** — RA6 full chain + crypto app on GNUARM **and** IAR.

### P4 · RA8x2 base port — BL2 + SPE on primary core, FSP 6.6 (Sep 28 – Oct 23)
- New `platform/ext/target/renesas/ra8x2`; RASC projects on FSP 6.6; reuse RA6 patterns (DDSC bridge, secure project, isolation, veneer).
- **Spike first: settle core topology** (never examined) — which core runs SPE vs NSPE; TZ-on-M85 + M33-as-NS vs pure multi-core (drives the mailbox design).
- RA8x2 specifics: memory map, RSIP crypto, Cortex-M85 PACBTI / FPU-in-SPE.
- **Exit M4** — RA8x2 SPE boots on the primary core.

### P5 · Dual-core — FSP ICC ↔ TF-M mailbox HAL (Oct 26 – Nov 20)
- Implement `tfm_hal_multi_core_*` / `platform_mailbox` over FSP inter-core communication (shared memory + semaphore/IPC).
- NS mailbox agent on the NSPE core; marshal PSA client calls across cores; boot both cores.
- **Exit M5** — a PSA call marshaled NSPE-core → SPE-core over FSP ICC completes.

### P6 · RA8x2 NS + IAR + crypto NSC app → primary goal (Nov 23 – Dec 18)
- NSPE application on the second core; end-to-end dual-core boot + the crypto NSC app.
- IAR `.icf` / startup for RA8x2 (both cores); build + boot under IAR.
- Consolidation + stakeholder sign-off.
- **Exit M6** — RA8x2 dual-core full chain + crypto app, GNUARM + IAR.

### P7 · Stretch — upstream to the Arm TF-M repository (Jan 11 – Mar 26, 2027)
- Docs tree (vendor + per-platform `index.rst`, `platform_introduction.rst`); accept the deprecation policy's ongoing-maintenance commitment; maintainer sign-off + CI.
- Submit via review.trustedfirmware.org (Gerrit). Not mandatory for this customer — bounded by external review latency.
- **Exit M7** — RA6 + RA8x2 merged upstream (review-latency dependent).

---

## Platform HAL surface — what each target must implement

| Area | Items |
|---|---|
| **Boot & isolation** | startup + linker, OFS (BL2); `target_cfg.c` (SAU/PPC/MPC); `tfm_hal_isolation.c` + static boundaries; DDSC bridge (`gp_ddsc_*`) |
| **Multi-core (RA8x2)** | `tfm_hal_multi_core_*` + `platform_mailbox` over FSP ICC; NS mailbox agent; PSA call marshaling |
| **Storage** | `Driver_FLASH0/1` (code + data); `its_flash_fs` HAL (ITS); `ps_nv_counters` (PS) |
| **Crypto & entropy** | RSIP crypto driver; entropy / TRNG source; crypto key HAL (exercised by the NSC app) |
| **Identity & provisioning** | OTP HAL + lifecycle state; IAK + BL2 ROTPKs (dummy for dev); NV counters backend |
| **Platform service & NS** | system reset, IOCTL, NV-counter API; NS `ns/CMakeLists` + `cpuarch_ns`; veneer / CMSE import library |

---

## Milestones

| ID | Date (target) | Gate |
|---|---|---|
| M1 | ~2026-08-14 | RA6 BL2 → tfm_s boots on silicon |
| M2 | ~2026-09-04 | Full RA6 boot BL2 → S → NS + crypto NSC app verified (GNUARM) |
| **M3** | **~2026-09-25** | **RA6 full chain + crypto app on GNUARM and IAR** |
| M4 | ~2026-10-23 | RA8x2 SPE boots on the primary core (FSP 6.6) |
| M5 | ~2026-11-20 | RA8x2 dual-core: PSA call marshaled NSPE-core → SPE-core over FSP ICC |
| **M6** | **~2026-12-18** | **RA8x2 dual-core full chain + crypto app, GNUARM + IAR** (primary goal) |
| M7 | ~2027 Q1–Q2 | *Stretch* — RA6 + RA8x2 merged into Arm TF-M upstream |

---

## Risks & buffer

| Severity | Risk |
|---|---|
| **High** | **Dual-core mailbox integration.** Binding FSP inter-core comms to TF-M's `tfm_hal_multi_core` / `platform_mailbox` is the biggest unknown; no RA reference exists. Concentrated in P5. |
| **High** | **RA8x2 core-topology is an open unknown.** SPE vs NSPE core, and TZ-on-M85 + M33-as-NS vs pure multi-core, set the entire mailbox design — never examined. Needs an early spike (P4 start). |
| **High** | **IAR replication.** OFS / veneer / TZ placement + startup as IAR `.icf`; IAR TZ/veneer handling differs from GCC. Two rounds (RA6 P3, RA8x2 P6). |
| **High** | **FSP 6.6 for RA8x2.** First use for dual-core + SAU-reach-NS + RA8 support; regen churn and unverified dual-core generation. |
| Med | **RA6 secure/NS integration.** DDSC blocker is solved (`bsp_security.o` compiles); remaining is wiring the regenerated RA6E1 secure/NS projects (crypto-stack includes, veneer, NS transition). |
| Med | **New silicon.** First RA8x2 bring-up — M85 PACBTI/FPU, RSIP, dual-core boot. |
| Med | **Hardware.** An EK-RA8x2 (dual-core) board must be procured before P4; 2× EK-RA6M4 bricked (RA6E1 is the RA6 vehicle). |

**Validation is intentionally shallow** — boot + a single crypto NSC path, not conformance. Stakeholders have accepted this; psa-arch-tests remain a possible future addition beyond this plan.

**Buffer.** Dates are targets, not commitments — an overrun shifts subsequent dates rather than cutting scope. The RA8x2 leg (P4–P6) carries ~20–25% internal buffer and holds Dec 21 – Jan 2 as contingency. Everything is sequential under one engineer.

---

*Revised 2026-07-28 · RA6 (GNUARM+IAR) target ~2026-09-25 · RA8x2 dual-core goal ~2026-12-18 · validation: boot + crypto NSC app*
