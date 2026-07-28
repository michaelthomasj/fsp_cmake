# TF-M on Renesas RA — CMake Port for RA6 & RA8 (FSP 6.6)

**Project plan · Firmware security**

Deliver Trusted Firmware-M building on RA6 and RA8 from RASC-generated FSP 6.6
sources via the modular CMake framework, on both **GNUARM and IAR** toolchains,
validated against the PSA arch tests. Upstreaming to the Arm TF-M repository is
planned as a stretch goal.


| | |
|---|---|
| **MVP target** | **2027-01-30** |
| Prepared | 2026-07-28 |
| Duration | ~26 weeks (25% buffer added) |
| Toolchains | GNUARM + IAR |
| Stretch — upstream | Q2 2027 |
| Resourcing | 1 engineer |

---

## Snapshot

**Done — baseline**
- **RA6E1 BL2 boots on silicon** (TF-M v2.2, FSP 6.1): full boot through flash init, NV-counter init, MCUboot image search.
- **Flash driver** ported (data-flash NV counters working); OFS brick-guard in place.
- Modular CMake consuming RASC output; RTT logging.

**MVP scope**
- **RA6** full secure boot chain (BL2 → S → NS) on FSP 6.6.
- **RA8** port to the same chain on FSP 6.6.
- **GNUARM + IAR** toolchains, both platforms.
- Both pass **some or all** targeted PSA arch tests.

**Not in MVP**
- Upstream merge to Arm TF-M (planned as stretch, phase H).
- ARMCLANG toolchain.
- Full PSA test-suite green across every service (best-effort in MVP).

---

## Timeline

| Phase | Work | Start | End | Track |
|---|---|---|---|---|
| **A** | FSP 6.6 rebase · RA6 BL2 baseline | 2026-07-28 | 2026-08-14 | Cross-cutting |
| **B** | RA6 secure image (tfm_s) | 2026-08-17 | 2026-09-11 | RA6 |
| **C** | RA6 non-secure · full boot chain | 2026-09-14 | 2026-09-25 | RA6 |
| **D** | RA6 PSA arch tests (GNUARM) | 2026-09-28 | 2026-10-23 | RA6 |
| **E** | RA8 port · BL2 → S → NS (GNUARM) | 2026-10-26 | 2026-11-27 | RA8 |
| **F** | RA8 PSA arch tests (GNUARM) | 2026-11-30 | 2026-12-18 | RA8 |
| **G** | IAR toolchain · RA6 + RA8 → **MVP** | 2027-01-05 | 2027-01-30 | Cross-cutting |
| **H** | *Stretch* — upstream to Arm TF-M | 2027-02-09 | 2027-04-24 | Stretch |

Critical path: **A → B → C → D → E → F → G** (sequential under a single engineer).

---

## Phases

### A · Foundation — FSP 6.6 rebase & RA6 BL2 baseline (Jul 28 – Aug 14)
- Regenerate RA6E1/RA6M4 RASC projects on FSP 6.6.
- Re-apply hand-edits: data-flash programming, EARLY_INIT, per-word OFS, flash driver.
- Confirm BL2 still boots on RA6E1 silicon under 6.6.
- **Exit M1** — RA6 BL2 boots on FSP 6.6.

### B · Secure — RA6 secure image (tfm_s) (Aug 17 – Sep 11)
- Generate RA6 TrustZone-Secure RASC project; wire DDSC symbols (`fsp_gen.ld` + `bsp_linker_info.h`) into the tfm_s link.
- Resolve `bsp_security.c`; decide SAU ownership — `tfm_hal_isolation.c` / `target_cfg.c` vs FSP `R_BSP_SecurityInit`.
- Platform HAL: `tfm_hal_platform_init`, `tfm_platform_system.c` (reset / IOCTL / NV-counter API); OTP HAL + lifecycle-state so first-boot dummy provisioning runs.
- Build + sign tfm_s; BL2 validates & chainloads it.
- **Exit M2** — BL2 → tfm_s boots on silicon.

### C · Non-secure — RA6 non-secure & full boot chain (Sep 14 – Sep 25)
- NS RASC project downstream of secure; consume veneer / CMSE import library.
- `ns/CMakeLists.txt`, `cpuarch_ns.cmake`, S→NS transition.
- Full BL2 → S → NS boot, proven over RTT.
- **Exit M3** — full RA6 secure boot chain.

### D · Validate — RA6 PSA arch tests, GNUARM (Sep 28 – Oct 23)
- Integrate psa-arch-tests; split SPE/NSPE build; `TFM_DUMMY_PROVISIONING` (dummy IAK/ROTPK match the TF-M test keys).
- Wire service HALs the suites exercise: entropy / RSIP TRNG (crypto), `its_flash_fs` (ITS), `ps_nv_counters` (PS), boot-seed + device-ID + IAK (attestation).
- Run on RA6E1; iterate to green on targeted suites.
- **Exit M4** — RA6 passes targeted PSA tests.

### E · RA8 — RA8 port, new platform, GNUARM (Oct 26 – Nov 27)
- New `platform/ext/target/renesas/ra8`; RA8 RASC projects (BL2/S/NS) on FSP 6.6.
- RA8 specifics: SAU reach-to-NS (FSP 6.6 fix), TCM DDSC symbols, memory map, RSIP crypto driver.
- Cortex-M85: PACBTI / branch-protection + FPU-in-SPE config decisions.
- BL2 → S → NS boot on EK-RA8 silicon.
- **Exit M5** — RA8 full boot chain on silicon.

### F · Validate — RA8 PSA arch tests, GNUARM (Nov 30 – Dec 18)
- RA8 provisioning / entropy / RSIP crypto wired up.
- Run psa-arch-tests on EK-RA8; iterate to targeted green.
- Cross-check RA6 + RA8 GNUARM regression before the toolchain fan-out.
- **Exit M6** — RA8 passes targeted PSA tests.

### G · IAR / MVP — IAR toolchain across RA6 + RA8 (Jan 5 – Jan 30, 2027)
- IAR linker `.icf` for BL2 / S / NS: replicate per-word OFS, veneer / NSC placement, TZ regions (GCC `.ld` → IAR `.icf`).
- IAR startup + toolchain CMake; build BL2 → S → NS on RA6 then RA8; boot on silicon.
- Run targeted PSA tests under IAR; MVP consolidation + stakeholder sign-off.
- **Exit M7** — MVP: RA6 + RA8, GNUARM + IAR, PSA tests.

### H · Stretch — upstream to the Arm TF-M repository (Feb 9 – Apr 24, 2027)
- Docs tree: vendor `index.rst` + per-platform entry + `platform_introduction.rst`, added to `docs/platform/index.rst`.
- Accept the deprecation policy's **ongoing-maintenance commitment** (owner keeps the platform building/running upstream); maintainer sign-off + CI.
- Submit via review.trustedfirmware.org (Gerrit); iterate through community review cycles.
- Not mandatory for this customer — timeline is bounded by external review latency.
- **Exit M8** — RA6 + RA8 merged upstream (review-latency dependent).

---

## Platform HAL surface — what each target must implement

| Area | Items |
|---|---|
| **Boot & isolation** | startup + linker, OFS (BL2); `target_cfg.c` (SAU/PPC/MPC); `tfm_hal_isolation.c` + static boundaries |
| **Storage** | `Driver_FLASH0/1` (code + data); `its_flash_fs` HAL (ITS); `ps_nv_counters` (PS) |
| **Crypto & entropy** | RSIP crypto driver; entropy / TRNG source; crypto key HAL |
| **Identity & provisioning** | OTP HAL + lifecycle state; IAK + BL2 ROTPKs (dummy for dev/tests); NV counters backend |
| **Platform service** | system reset; IOCTL entry point; NV-counter increment / read API |
| **Attestation & NS** | boot seed, implementation / device ID; NS `ns/CMakeLists` + `cpuarch_ns`; veneer / CMSE import library |

---

## Milestones

| ID | Date | Gate |
|---|---|---|
| M1 | 2026-08-14 | **RA6 BL2 boots on FSP 6.6** silicon (baseline re-established after regen) |
| M2 | 2026-09-11 | **BL2 → tfm_s** validated & chainloaded; DDSC/secure project + isolation resolved |
| M3 | 2026-09-25 | **Full RA6 boot chain** BL2 → S → NS on silicon |
| M4 | 2026-10-23 | **RA6 passes targeted PSA arch tests** (GNUARM) |
| M5 | 2026-11-27 | **RA8 full boot chain** on silicon (GNUARM) |
| M6 | 2026-12-18 | **RA8 passes targeted PSA arch tests** (GNUARM) |
| **M7** | **2027-01-30** | **MVP — RA6 + RA8 on FSP 6.6, GNUARM + IAR, passing targeted PSA arch tests** |
| M8 | ~2027 Q2 | *Stretch* — RA6 + RA8 merged into Arm TF-M upstream |

---

## Risks & buffer

| Severity | Risk |
|---|---|
| **High** | **FSP 6.6 regen churn.** Every hand-edit (DF programming, EARLY_INIT, OFS, flash driver, DDSC wiring) needs to be replicated; 6.6 is unlikely to have major changes in that regard. Mitigated by sticking with 6.1 but not recommended. |
| **High** | **RA8 SAU reach-to-NS.** Flat MCUboot can't reach NS on RA8 without the FSP 6.6 fix — unverified until phase E. If it slips, RA8 secure→NS needs a workaround. |
| **High** | **IAR linker replication.** Recreating OFS / veneer / TZ region placement + startup as IAR `.icf` across BL2/S/NS × 2 platforms; IAR TZ and veneer handling differs from GCC. On the MVP critical path (phase G). |
| Med | **SAU ownership decision.** FSP `R_BSP_SecurityInit` vs TF-M `sau_and_idau_cfg` (DESIGN §13.1/§13.2). Choosing TF-M-owns expands scope; folded into phase B. |
| Med | **PSA test depth.** Attestation / PS / ITS need entropy, provisioning, and RSIP crypto wired up. "Some or all" is deliberate — full green may exceed the MVP window per service. |
| Med | **Hardware.** 2× EK-RA6M4 bricked (RA6E1 is the RA6 vehicle); an EK-RA8 must be procured before phase E. |
| Med | **Upstream maintenance commitment.** The deprecation policy obliges the platform owner to keep RA6/RA8 building & running upstream after merge — an ongoing cost beyond the merge itself. |
| Ext | **Upstream review latency.** Phase H duration is set by trustedfirmware.org maintainer cycles — outside our control, hence stretch and off the MVP critical path. |

**Buffer model.** Each phase carries roughly 25–30% internal buffer. The
Dec 19 – Jan 2 year-end period is held as schedule contingency ahead of phase G.
Critical path runs A→B→C→D→E→F→G; phases D (RA6 tests), E (RA8), and G (IAR) are
the most likely to consume buffer, and with just one engineer, are sequential.

---

