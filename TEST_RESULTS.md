# Test results — every hardware run, with its result and its source

What has run on hardware, per part and toolchain; §9 lists what has never run. Each result cites
the [DECISIONS.md](DECISIONS.md) entry that recorded it.

---

## How to read this

"Pass" means both the secure and non-secure suites completed with zero failures and both logs
were read back; partial captures are labelled in the cell. Suite counts differ between
isolation-1 trees (14–15) and isolation-2/3 trees (9 + 7). PSA Arch tallies read pass / fail /
skip.

---

## 1. TF-M regression suite (`tf-m-tests`), by isolation level

**The L1 + SFN column is the configuration the build scripts produce, and every cell in it
predates the isolation-HAL move.** Those runs are marked `pass (pre-change)`: they passed, and
they passed against a secure image whose isolation HAL was compiled in `platform_s` rather than
`tfm_spm`. The L2 and L3 cells were re-run after the move. Nothing in the shipped default
configuration has been through a hardware regression since.

| | L1 + SFN | L1 + IPC | L2 | L3 |
|---|---|---|---|---|
| RA6M5 GNUARM | pass (pre-change) ([D067], [D091]) | secure only ([D122]) | pass ([D113]), re-confirmed post-move ([D122]) | pass ([D114]), re-confirmed post-move ([D123] §1) |
| RA6M5 IAR | pass (pre-change) ([D070], [D072]) | no tree exists | secure reported, not captured ([D123] §2) | pass ([D124]) |
| RA8M2 GNUARM | pass (pre-change) ([D095]) | pass ([D116] §1) | pass ([D115] §1) | secure partial ([D115] §1), non-secure pass ([D116] §3) |
| RA8M2 IAR | pass (pre-change) ([D105]) | no tree exists | pass ([D118]) | pass ([D119]) |

Two tf-m-tests crypto cases pass without testing: 1056 (P-384) self-skips off CryptoCell, so
P-384 is untested; 1044/1045 (deterministic ECDSA) run verification only.

---

## 2. PSA Arch suites

All of these ran at `profile_large`, isolation 3, with the IPC backend.

Runs used the `psa-arch-tests` fork at tag `renesas-ra-tfm-2.2.0`
([GETTING_STARTED.md](GETTING_STARTED.md) §3); an unpatched tree is not comparable.

| Suite | RA6M5 GCC | RA6M5 IAR | RA8M2 GCC | RA8M2 IAR |
|---|---|---|---|---|
| crypto (64 tests) | 63 / 0 / 1 ([D046]) | 63 / 0 / 1 ([D046]) | 62 / 1 / 1 ([D097], [D099]) | 62 / 1 / 1 ([D104]) |
| attestation | 1 / 0 / 0 ([D046]) | 1 / 0 / 0 ([D046]) | 1 / 0 / 0 — see §7 | 1 / 0 / 0 ([D105]) |
| storage, ITS + PS (17 tests) | 11 / 0 / 6 ([D046]) | 11 / 0 / 6 ([D046]) | 11 / 0 / 6 ([D097]) | 11 / 0 / 6 ([D105]) |

**Isolation 3 was configured, not enforced, in these runs:** the level-3 MPU table was not
exercised (first exercised by the §1 L3 runs).

### The one failure and the skips

| | What it is | Status |
|---|---|---|
| crypto 216, RA8M2 only | `psa_generate_key` check 4, RSA-2048, returns `-134` | genuine gap. **There is no config switch for it**: the guard is on the engine, not on a key-format setting ([D111], which supersedes the earlier reading). Fails identically under both toolchains ([D104]) |
| crypto 252, both parts | deterministic ECDSA, code `0x2d` | FSP does not support RFC 6979, by design ([D038]) |
| storage 411, 412, 413, 415, 416, 417 | `psa_ps_create` / `psa_ps_set_extended`, code `0x2b` | optional PSA APIs TF-M does not implement. Test 414 passes by confirming they refuse ([D097]) |

---

## 3. Interrupt handling: FLIH and SLIH

| | FLIH | SLIH |
|---|---|---|
| RA6M5 GNUARM | pass at L1 ([D070], [D072]), and at L1+IPC, L2 and L3 as part of §1 | pass at L1 only ([D072]) |
| RA6M5 IAR | pass at L1 ([D070], [D072]), and at L2 and L3 as part of §1 | pass at L1 only ([D072]) |
| RA8M2 GNUARM | pass at every level in §1 | **never run** |
| RA8M2 IAR | pass at every level in §1 | **never run** |

`TFM_NS_IRQ_TEST_FLIH_1101` and `_1102` are included in every §1 cell that reads "pass".

SLIH has run only on RA6M5 at isolation 1 (`ra6m5_TFM_slih_{gcc,iar}`); see §9.

---

## 4. MCUboot upgrade path

Only RA8M2 has run the upgrade path.

| Run | Date | Result | Entry |
|---|---|---|---|
| `ra8m2_TFM_update_gcc` | 2026-10-08 | both images install from their secondary slots; a second reset reports `Swap type: none`, so the secondary is erased and there is no re-install | [D100] |
| `ra8m2_TFM_update_iar` | 2026-10-09 | install confirmed from `rsp.br_hdr`: `ih_ver` 2.3.0 at `br_image_off 0x68000`, which the launch had flashed at 2.2.0 | [D106] |

The IAR run confirms the install only; the erase on second boot was shown under GCC. RA6M5 has no
upgrade launch.

Image-0 slot order is reversed on RA8M2 ([RA8M2_SOLUTION.md](RA8M2_SOLUTION.md)).

---

## 5. Measured boot

A passing attestation suite does not prove measured boot (it passes with no software components),
so each result below was read from the boot record.

| Part and toolchain | Date | Result | Entry |
|---|---|---|---|
| RA6M5 | 2026-10-02 | confirmed from the boot record | [D081] |
| RA8M2 GCC | 2026-10-06 | decoded from the record at `0x22000000`; [D095] had assumed it | [D096] |
| RA8M2 IAR | 2026-10-09 | decoded, both measurements matching the signed images' SHA-256 TLVs | [D105] |

---

## 6. RA6E1

Reference only and not re-run against the current build (README). Its last results — all 13
secure services and 5/5 non-secure regression suites — predate the isolation-HAL move.

---

## 7. Results without a full capture

Secure half only: RA6M5 GNU L1+IPC and its L2 post-move re-run. Secure half reported, not
captured: RA6M5 IAR L2. Secure half partial: RA8M2 GNU L3. No log entry behind the figure: RA8M2
GCC PSA Arch attestation 1/0/0.

## 8. A defect no suite reaches

The FSP 6.7 `mbedtls_aes_crypt_ctr()` partial-block defect:
[KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) §2.

---

## 9. Suites that have never run

Gaps in coverage, not known failures.

| Suite | Option | Why it has not run | Worth running? |
|---|---|---|---|
| Firmware Update | `TEST_S_FWU`, `TEST_NS_FWU` | `TFM_PARTITION_FIRMWARE_UPDATE` is OFF | Highest value: it exercises the PSA Firmware Update API over the MCUboot slots the port already has, and the bootloader half is proven on RA8M2. Whether the partition fits is a region question ([CONFIGURATION.md](CONFIGURATION.md) §6) |
| SLIH above isolation 1 | `CONFIG_TFM_SLIH_API` | No SLIH tree or launch exists above isolation 1, and none at all on RA8M2. The SLIH service declares the same MMIO region as FLIH, and that path has never been exercised above isolation 1 | Yes, once the trees and launches are made |
| PSA Arch Firmware Framework | `TEST_PSA_API=IPC` | Only the crypto, attestation and storage suites have been built | Yes. It is a different test body from the developer-API suites already run |
| FPU | `TEST_S_FPU`, `TEST_NS_FPU` | `CONFIG_TFM_ENABLE_CP10CP11` is OFF and the port is soft-float throughout | Only if floating point is enabled. RA8M2 is a Cortex-M85 with FP hardware, so this is a real gap for that part |
| Non-secure client ID management | `TEST_NS_MANAGE_NSID` | `TFM_NS_MANAGE_NSID` is not set | Yes, and cheap |
| QCBOR and t_cose self-tests | `TEST_NS_QCBOR`, `TEST_NS_T_COSE` | never enabled | Yes, and cheap. Both libraries already ship, linked for attestation |
| Multi-core | `TEST_NS_MULTI_CORE` | `TFM_MULTI_CORE_TOPOLOGY` is OFF and the second core is unused | Not applicable while the port is single-core |

Covered: PS, ITS, crypto, attestation, platform, SFN, FLIH on both parts and toolchains, and the
three PSA Arch suites. Not a suite but a gap: the shipped default, which §1 covers.
