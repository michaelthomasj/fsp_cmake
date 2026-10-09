# Bringing the rsip7 CM driver into peaks-working

**Audience:** the engineer who will do this work, and the reviewers deciding whether to fund it.
**Status:** plan only — nothing below has been implemented.
**Written:** 2026-10-09, against `rsip7@develop_cm_ra` (`2178edb`) and `peaks-working@develop`
(`b1423628f0`).

**Goal.** Ship TF-PSA-Crypto 1.1.1 with RSIP hardware acceleration from an FSP package, selectable
and configurable in RASC, in the same way Mbed TLS 3.x is shipped today — **without** touching
MCUboot, TF-M or any other consumer. Those come later, and only once they can choose which crypto
library they build against.

---

## 1. What exists today

### `rsip7` — the driver

| Path | What it is |
|---|---|
| `cm/src/arm/tf-psa-crypto/` | TF-PSA-Crypto **1.1.1**, vendored (`core/ dispatch/ drivers/ extras/ include/ platform/ utilities/`) |
| `cm/src/r_rsip_cm/src/common/psa/` | **The transparent driver.** One file per PSA entry-point family: `hash`, `mac`, `aead`, `unauthenticated_ciphers`, `key_management`, `key_agreement`, `asymmetric_signature`, `random`, `ecc_scalar_multi`, `init`, `common` |
| `cm/src/r_rsip_cm/src/ra/private/ra_rsip_e5xx/` | **RA support exists** — `hw_sce_ra_private.h`, `r_rsip_hal.c` for the E5xx family |
| `cm/src/r_rsip_cm/src/rzt_rzn/` | RZ/T and RZ/N support |
| `cm/src/rm_tf_psa_crypto/` | The dispatch glue: `psa_crypto.c`, `psa_crypto_driver_wrappers.h`, `psa_crypto_driver_wrappers_no_static.c`, and `psa/crypto_config.h` + the two `crypto_driver_contexts_*.h` |
| `cm/test/` | A PowerShell script that **copies `cm/src/` into e2 project `src/` folders**. Test projects exist for `rzn2l_cr52` only — GCC and IAR |
| `pack/` | `Renesas.RZx_rsip.pdsc.j2` — a CMSIS-pack template for RZ. Not FSP. |

**The driver is in good shape; the packaging is not.** There is no FSP module, no RASC
configuration, no `.module_descriptions` XML, and no RA test project. Consumption today is a file
copy.

### `peaks-working` — how Mbed TLS 3.x is packaged

Four mechanisms, and the new work has to supply all four.

```
ra/arm/mbedtls/                                      the library sources
ra/arm/!dsn/mbed_crypto_module.xml                   manifest: sources + include folders
   -> <cfg_xml_file> points at
ra/arm/.module_descriptions/
        Arm##PSA##Crypto##mbedCrypto####x.xx.xx.xml  5008 lines: RASC properties, templates
ra/fsp/src/rm_psa_crypto/                            the *_alt.c acceleration sources
ra/fsp/src/rm_psa_crypto/!dsn/module.xml             13 lines: whole directory as one source
ra/fsp/src/rm_psa_crypto/.module_descriptions/
        Renesas##HAL Drivers##all##rm_psa_crypto####x.xx.xx.xml
ra/fsp/src/bsp/mcu/<part>/.module_descriptions/
        Renesas##BSP##<part>##fsp####x.xx.xx.xml     per-MCU <enum> blocks
```

**The manifest (`!dsn/*.xml`) is a file list.** Description, `<sources>`, `<include_folders>`,
and `<cfg_xml_file>` naming the module description. A Renesas module can list a whole directory
as one `<source>`; the Arm one enumerates all 214 files individually.

**The module description is where the work is.** For mbedCrypto: `<config id="config.driver.psa_crypto"
path="arm/mbedtls/config.h">` — so RASC generates `ra_cfg/arm/mbedtls/config.h` — then 301
`<property>`, 457 `<option>`, 48 `<template>` (code generation), 49 `<moduleRef>`/`<platform>`
(gating), 40 `<constraint>`, and `<requires>`/`<provides>` for dependencies.

**Per-MCU capability lives in the BSP module description**, as `<enum>` blocks the module's
`<select enum="…"/>` properties point at. This is how one module serves parts with different
engines:

```xml
<enum id="enum.mcu.psa_crypto.rsa_format" default="…rsa_format.vendor_plaintext_wrapped">
  <option display="Plaintext and Wrapped (Vendor)" id="…vendor_plaintext_wrapped" value="3"/>
  <option display="Plaintext Only"                 id="…plaintext"                value="1"/>
</enum>
```

**This pattern is the single most important thing to copy**, and the place a naive port goes
wrong: put capability in the module and every part gets the union of everything.

---

## 2. Target shape

```
ra/arm/tf-psa-crypto/                                    NEW  library, from rsip7 cm/src/arm/
ra/arm/!dsn/tf_psa_crypto_module.xml                     NEW  manifest
ra/arm/.module_descriptions/
        Arm##PSA##Crypto##TF-PSA-Crypto####x.xx.xx.xml   NEW  properties -> ra_cfg/arm/tf-psa-crypto/crypto_config.h
ra/fsp/src/rm_tf_psa_crypto/                             NEW  dispatch glue, from rsip7 cm/src/rm_tf_psa_crypto/
ra/fsp/src/rm_tf_psa_crypto/!dsn/module.xml              NEW
ra/fsp/src/rm_tf_psa_crypto/.module_descriptions/…       NEW
ra/fsp/src/r_rsip_cm/                                    NEW  the transparent driver, from rsip7 cm/src/r_rsip_cm/
ra/fsp/src/r_rsip_cm/!dsn/module.xml                     NEW
ra/fsp/src/r_rsip_cm/.module_descriptions/…              NEW
ra/fsp/src/bsp/mcu/<part>/.module_descriptions/…         EDIT per-MCU <enum> for RSIP capability
```

Three modules, not one. The split mirrors the existing one (library / acceleration / BSP) and
keeps the library replaceable.

---

## 3. Task list

Effort is rough: **S** ≤ 1 day, **M** 2–4 days, **L** 1–2 weeks.

### Phase A — get it building at all (no RASC)

| # | Task | Size |
|---|---|---|
| A1 | Import `cm/src/arm/tf-psa-crypto/` to `ra/arm/tf-psa-crypto/`. Record the exact upstream tag and the rsip7 commit in a `VERSION` note — this is the single most important provenance fact in the whole exercise. | S |
| A2 | Import `cm/src/rm_tf_psa_crypto/` to `ra/fsp/src/rm_tf_psa_crypto/`. | S |
| A3 | Import `cm/src/r_rsip_cm/` to `ra/fsp/src/r_rsip_cm/`, dropping `src/rzt_rzn/` from the RA package. Decide now whether rsip7 stays the upstream of record (preferred) or peaks-working forks it — see §5. | M |
| A4 | **Create an RA test project.** rsip7 has `rzn2l_cr52` only. Build an EK-RA8M2 (E50D) or EK-RA8P1 project that compiles the three trees together and runs TF-PSA-Crypto's own tests. **This is the first real checkpoint** — everything after it is packaging. | M |
| A5 | Establish how `psa_crypto_driver_wrappers*.{h,c}` are produced. In TF-PSA-Crypto these are **generated from Jinja templates** driven by driver JSON; rsip7 carries them pre-generated. Either vendor the generator and run it at package build, or own them as sources with a documented regeneration step. **Decide before A6 — it determines who owns dispatch.** | M |

### Phase B — FSP packaging

| # | Task | Size |
|---|---|---|
| B1 | `ra/arm/!dsn/tf_psa_crypto_module.xml`. Follow `mbed_crypto_module.xml`: enumerate sources, include folders (`library`, `include/`, `ra_cfg/arm/`), and `<cfg_xml_file>`. | S |
| B2 | `Arm##PSA##Crypto##TF-PSA-Crypto####x.xx.xx.xml`. **The big one.** `<config path="arm/tf-psa-crypto/crypto_config.h">` plus a `<property>` per `PSA_WANT_*` / `MBEDTLS_PSA_*` knob worth exposing. Do **not** transcribe all 301 mbedCrypto properties — TF-PSA-Crypto's config surface is `PSA_WANT_*`, a different and smaller vocabulary. | L |
| B3 | `rm_tf_psa_crypto/!dsn/module.xml` + its module description. Small — mirrors the 13-line `rm_psa_crypto` manifest. | S |
| B4 | `r_rsip_cm/!dsn/module.xml` + its module description, with the properties that select which RSIP capabilities are compiled in. | M |
| B5 | **Per-MCU `<enum>` blocks** in each supporting part's BSP module description, declaring which RSIP the part has and which key formats it supports. **Model them on the existing `enum.mcu.psa_crypto.*` blocks and get the defaults right** — [D111] is a worked example of what a wrong capability assumption costs downstream. | M |
| B6 | `<requires>` / `<provides>` so RASC enforces the dependency chain, and `<constraint>`s that make an unsupported combination un-selectable rather than a link error. | M |
| B7 | Mutual exclusion with `rm_psa_crypto`. Both provide `psa_crypto_init()`. Selecting both must be refused in RASC, not discovered at link. | S |

### Phase C — validation

| # | Task | Size |
|---|---|---|
| C1 | TF-PSA-Crypto's own test suite on RA hardware, driver enabled and disabled, results compared. | M |
| C2 | PSA Arch `CRYPTO` suite against the new stack. **This is the comparable number** — the Mbed TLS 3.x stack scores 62/1/1 of 64 on RA8M2 and 63/0/1 on RA6M5 ([D099], [D104]). Anything below that is a regression with a name. | M |
| C3 | Size and performance against the Mbed TLS 3.x stack. The flash budget is the live constraint on RA8M2 — 670 B spare in the secure slot today. | S |
| C4 | Both toolchains. IAR has already produced two console defects this port had to fix ([D107], [D108]); assume it will produce more. | M |

### Phase D — Zephyr consumption (the external dependency)

| # | Task | Size |
|---|---|---|
| D1 | Confirm what the Zephyr team actually needs: the FSP package, a CMSIS pack, or a source drop. The answer changes B1–B7 materially and should be settled **before** Phase B starts. | S |
| D2 | Whatever that is, produced from the same tree as the FSP package — not a parallel copy. A second copy is how this becomes throwaway work for real. | M |

### Phase E — upstreaming (explicitly deferred)

Not started until A–C are green. The requirement that **upstream modules choose their crypto
library** is the whole design constraint, and it is cheaper to meet if nothing has been
integrated yet:

| # | Task | Size |
|---|---|---|
| E1 | A selector (`RM_CRYPTO_BACKEND` = `mbedtls3` \| `tf_psa_crypto`) that MCUboot, TF-M and NetX consult. | M |
| E2 | Keep `rm_psa_crypto` fully supported alongside. **Both must work for at least one full FSP release.** | — |
| E3 | Only then, per-consumer enablement. | L |

---

## 4. Order, and the two checkpoints

```
A1 A2 A3 ──► A4 ──► A5 ──► B1 B3 B4 ──► B2 ──► B5 B6 B7 ──► C1 C2 C3 C4 ──► (E)
                 ▲                                                ▲
          CHECKPOINT 1                                     CHECKPOINT 2
      builds and runs on RA?                        matches the 3.x numbers?
      D1 must be answered by here
```

**Checkpoint 1 (after A4)** — does the driver work on RA silicon at all? rsip7 has RA sources but
no RA test project, so **this is unproven today**. If it slips, everything after it is unfunded
work. Do not start Phase B before it passes.

**Checkpoint 2 (after C2)** — does it match the Mbed TLS 3.x results? If not, the gap must be
named and accepted before upstreaming is discussed.

---

## 5. Decisions needed before starting

| # | Decision | Why it cannot wait |
|---|---|---|
| 1 | **Who owns `r_rsip_cm` going forward?** rsip7 as upstream with peaks-working importing, or a fork. | Determines whether every RZ fix reaches RA, and whether RA fixes flow back. A fork decided by default, late, is the expensive outcome. |
| 2 | **Generated or vendored driver wrappers?** (A5) | Determines who regenerates on a TF-PSA-Crypto uprev, and whether a driver capability change is a one-line JSON edit or a hand merge. |
| 3 | **What does the Zephyr team consume?** (D1) | B1–B7 differ materially between an FSP package and a CMSIS pack. |
| 4 | **Which parts are in scope for the first release?** | Each costs a B5 and a C-phase pass. RA8M2 and RA8P1 are both E50D; E51A (RA8D1) is a different capability set. |
| 5 | **Is `rm_psa_crypto` deprecated or maintained?** | If maintained, every ALT fix lands twice from now on. |

---

## 6. Risks

| Risk | Note |
|---|---|
| **RA path unproven** | rsip7's RA sources have no test project. A4 is the honest first task and could expose real work. |
| **Driver wrapper divergence** | `psa_crypto_driver_wrappers*.c` are generated upstream and checked in here. A TF-PSA-Crypto uprev produces a hand-merge unless A5 is settled properly. This is the same class of defect `BRIDGING_FILES.md` exists to catch. |
| **Module description scale** | mbedCrypto's is 5008 lines. B2 is the long pole and resists estimation until the property set is agreed. |
| **Flash budget** | TF-PSA-Crypto plus a transparent driver against Mbed TLS 3.x plus ALT files is an open question. 670 B spare on RA8M2 today. Measure at C3, not at the end. |
| **Throwaway risk, stated by the requester** | The mitigation is sequencing, not caution: A4 and C2 are the two points where the work can be stopped with most of its value already banked — a working RA driver, and a measured comparison. |
| **Two crypto stacks in one package** | B7 and E2 mean `rm_psa_crypto` and `rm_tf_psa_crypto` coexist for at least one release. Mutual exclusion must be enforced in RASC. |

---

## 7. What this plan deliberately does not do

- **No MCUboot, TF-M or NetX integration.** Phase E, after the standalone path works.
- **No removal of `rm_psa_crypto`.** It ships both active RA TF-M ports.
- **No RZ work.** `src/rzt_rzn/` and `pack/Renesas.RZx_rsip.pdsc.j2` stay with rsip7.
- **No commitment to the 5008-line property set.** TF-PSA-Crypto's config vocabulary is
  `PSA_WANT_*`; the mbedCrypto description is a structural model, not a content one.
