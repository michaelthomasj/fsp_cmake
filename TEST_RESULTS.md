# Test results — every hardware run, with its result and its source

What has run on silicon, on which part and toolchain, and what it returned. Each row cites the
`DECISIONS.md` entry that recorded the run. That log is the primary record; this document is an
index into it and adds no result of its own.

For what has **not** run, read §9 below. It lists every suite that no run has covered.

---

## How to read this

**"Pass" means both halves were captured.** From [D113] onward an entry says "green" only when
the secure and non-secure suites both completed with zero failures and both logs were read back.
Where only one half was captured, the cell says so rather than reading "pass". Three cells carry
that qualification, and §7 lists them.

**Suite counts differ between eras**, because the trees differ. The isolation-1 regression trees
report 14 or 15 suites ([D067], [D072]); the isolation-2 and isolation-3 trees report secure 9/9
and non-secure 7/7 ([D113] onward). A changed count is not a changed result.

**PSA Arch tallies read pass / fail / skip.**

### Build-tree names

Entries cite trees by short name. They live in `C:\b`, 67 of them, and are not in this
repository. The name is positional:

| Segment | Meaning |
|---|---|
| `m5`, `m2` | RA6M5, RA8M2 |
| `g`, `i` | GNUARM, IAR |
| `l1i`, `l2`, `l3` | isolation 1 with the IPC backend, isolation 2, isolation 3 |
| `flih`, `slih` | the FF-M interrupt handling model under test |
| `cry`, `att`, `sto` | the PSA Arch suite: crypto, attestation, storage |
| `rs`, `rn` | the isolation-1 regression pair, secure and non-secure |
| `ns` suffix | the non-secure half of a pair |

So `m5il3` is RA6M5 under IAR at isolation 3, and `m2gl2ns` is the non-secure half of RA8M2
under GNUARM at isolation 2. There is no `m5il1i` or `m2il1i`: no IAR tree exists at
isolation 1 with IPC ([D124]).

---

## 1. TF-M regression suite (`tf-m-tests`), by isolation level

This is the regression-plus-FLIH configuration. Every pre-[D113] run is isolation 1 with the SFN
backend — [D113] established that "every `tests_reg` build in `C:\b` is L1/SFN and every L3 build
is PSA Arch".

| | L1 + SFN | L1 + IPC | L2 | L3 |
|---|---|---|---|---|
| RA6M5 GNUARM | pass ([D067], [D091]) | secure only ([D122]) | pass ([D113]), re-confirmed post-move ([D122]) | pass ([D114]), re-confirmed post-move ([D123] §1) |
| RA6M5 IAR | pass ([D070], [D072]) | no tree exists | secure reported, not captured ([D123] §2) | pass ([D124]) |
| RA8M2 GNUARM | pass ([D095]) | pass ([D116] §1) | pass ([D115] §1) | secure partial ([D115] §1), non-secure pass ([D116] §3) |
| RA8M2 IAR | pass ([D105]) | no tree exists | pass ([D118]) | pass ([D119]) |

[D124] declared this matrix complete, and it is, in the sense that every cell with a tree has
run. Three cells rest on a partial capture; §7 states each one.

### The isolation-1 runs in detail

| Run | Date | Result | Entry |
|---|---|---|---|
| RA6M5 GCC, `MinSizeRel`, SFN, SCE9, `m5rs` + `m5rn` | 2026-09-29 | 14 suites, zero failures — first full regression pass on hardware | [D067] |
| RA6M5 GCC and IAR, FLIH | 2026-09-30 | 8 secure + 7 non-secure, zero failures, both on `TF-M v2.2.0+ca55cf5c1` | [D070] |
| RA6M5 GCC and IAR, FLIH and SLIH | 2026-10-01 | 15 suites each, zero failures | [D072] |
| RA6M5 GCC, under Option 3 | 2026-10-05 | full suite, secure and non-secure, zero failures, `TF-M v2.2.0+e75582eac` | [D091] |
| RA8M2 GCC, `ra8m2_TFM_flih_gcc` | 2026-10-06 | every secure and non-secure suite, zero failures — first complete run on this part | [D095] |
| RA8M2 IAR, `ra8m2_TFM_flih_iar` | 2026-10-09 | all 7 non-secure suites, FLIH IRQ included | [D105] |

[D067] also recorded two suites that report PASSED without testing anything. Do not read either
as coverage:

- `TFM_S_CRYPTO_TEST_1056` / `TFM_NS_CRYPTO_TEST_1056` (ECDSA-SECP384R1-SHA384) self-skip on
  every platform that is not Arm CryptoCell, because the gate tests `CC3XX_RUNTIME_ENABLED`.
  `PSA_WANT_ECC_SECP_R1_384` is not disabled here, so **P-384 is untested on this port and
  probably works.** It needs a standalone check before anyone claims P-384 support.
- `TFM_S_CRYPTO_TEST_1045` / `TFM_NS_CRYPTO_TEST_1044` (deterministic ECDSA) report a partial
  pass by design. `sce9/crypto_accelerator_config.h:34` undefines
  `PSA_WANT_ALG_DETERMINISTIC_ECDSA` because SCE9 has no RFC 6979 path. Verification did run.

---

## 2. PSA Arch suites

All of these ran at `profile_large`, isolation 3, with the IPC backend.

The tree was the `psa-arch-tests` fork at tag `renesas-ra-tfm-2.2.0`, which carries the
`renesas_ra` target and tf-m-tests' ten `fetch_repo` patches. An unpatched tree fails
`psa_verify_hash` check 13 on any platform, so a run against one is not comparable to these
([D014]). `GETTING_STARTED.md` §3 has the clone.

| Suite | RA6M5 GCC | RA6M5 IAR | RA8M2 GCC | RA8M2 IAR |
|---|---|---|---|---|
| crypto (64 tests) | 63 / 0 / 1 ([D046]) | 63 / 0 / 1 ([D046]) | 62 / 1 / 1 ([D097], [D099]) | 62 / 1 / 1 ([D104]) |
| attestation | 1 / 0 / 0 ([D046]) | 1 / 0 / 0 ([D046]) | 1 / 0 / 0 — see §7 | 1 / 0 / 0 ([D105]) |
| storage, ITS + PS (17 tests) | 11 / 0 / 6 ([D046]) | 11 / 0 / 6 ([D046]) | 11 / 0 / 6 ([D097]) | 11 / 0 / 6 ([D105]) |

**Read "isolation 3" narrowly here.** It says the SPM was configured at level 3, not that
level-3 isolation was enforced. The shared isolation HAL compiled with `TFM_ISOLATION_LEVEL`
undefined until [D113], so none of these runs exercised the level-3 MPU table. The first runs
that do are [D114] and [D123].

### The one failure and the skips

| | What it is | Status |
|---|---|---|
| crypto 216, RA8M2 only | `psa_generate_key` check 4, RSA-2048, returns `-134` | genuine gap. RSIP-E50D cannot generate RSA-2048 keys on the plaintext path the config selects ([D097], refined by [D098]). Fails identically under both toolchains ([D104]) |
| crypto 252, both parts | deterministic ECDSA, code `0x2d` | FSP does not support RFC 6979 ([D040]) |
| storage 411, 412, 413, 415, 416, 417 | `psa_ps_create` / `psa_ps_set_extended`, code `0x2b` | optional PSA APIs TF-M does not implement. Test 414 passes by confirming they refuse ([D097]) |

The two toolchains agree test for test on both parts — same tally, same failing test, same skip
([D104] on RA8M2, [D046] on RA6M5). The two parts differ by one test out of 64 ([D099]).

---

## 3. Interrupt handling: FLIH and SLIH

| | FLIH | SLIH |
|---|---|---|
| RA6M5 GNUARM | pass at L1 ([D070], [D072]), and at L1+IPC, L2 and L3 as part of §1 | pass at L1 only ([D072]) |
| RA6M5 IAR | pass at L1 ([D070], [D072]), and at L2 and L3 as part of §1 | pass at L1 only ([D072]) |
| RA8M2 GNUARM | pass at every level in §1 | **never run** |
| RA8M2 IAR | pass at every level in §1 | **never run** |

`TFM_NS_IRQ_TEST_FLIH_1101` and `_1102` are included in every §1 cell that reads "pass".

**SLIH has never run on RA8M2 on either toolchain.** The `m2gslih` and `m2gslihns` trees were
built and never got a launch ([D102], [D126] §4). SLIH has also never run above isolation 1 on
any part: the only SLIH launches are RA6M5's two at L1, `ra6m5_TFM_slih_{gcc,iar}.launch`. The
SLIH service declares the same `mmio_region` as FLIH, so the region is exercised — but not
through the SLIH path above L1.

[D126] §4 corrected [D116] and [D119] on this point. Their claim that "RA8M2 is complete: every
level this port supports" holds only for the regression-plus-FLIH configuration.

---

## 4. MCUboot upgrade path

Only RA8M2 has run this path. [D100] was the first execution on any part in the port.

| Run | Date | Result | Entry |
|---|---|---|---|
| `ra8m2_TFM_update_gcc` | 2026-10-08 | both images install from their secondary slots; a second reset reports `Swap type: none`, so the secondary is erased and there is no re-install | [D100] |
| `ra8m2_TFM_update_iar` | 2026-10-09 | install confirmed from `rsp.br_hdr`: `ih_ver` 2.3.0 at `br_image_off 0x68000`, which the launch had flashed at 2.2.0 | [D106] |

The IAR evidence covers the install only. The second boot reporting `Swap type: none` was not
observed under IAR; [D100] proved the erase half on GCC through the same `bootutil` code
([D106]).

Neither other part has run it. RA6M5 has no `*_TFM_update` launch. RA6E1 set
`MCUBOOT_ALIGN_VAL` to 128 to match its 128-byte code-flash write unit on 2026-08-29, and
and that fix has not been exercised on hardware: it only takes effect
once BL2 writes code flash, which is an upgrade. **Images signed at one alignment are rejected
by a BL2 built at another, because the trailer magic differs — reflash every slot and do not
mix.**

Slot order is reversed for image 0 on RA8M2. The secure secondary at `0x02020000` sits below the
secure primary at `0x02068000`, so `rsp.br_image_off = 0x68000` is the primary. Image 1 is the
usual way round ([D100]).

---

## 5. Measured boot

A passing attestation suite proves nothing about measured boot. With `component_cnt == 0` under
the default `ATTEST_TOKEN_PROFILE_PSA_IOT_1`, `attest_add_all_sw_components()` emits
`IAT_NO_SW_COMPONENTS` and returns success ([D080]). Every result below was obtained by reading
the boot record, not by inferring it from a 1/0/0 attestation pass.

| Part and toolchain | Date | Result | Entry |
|---|---|---|---|
| RA6M5 | 2026-10-02 | confirmed from the boot record | [D081] |
| RA8M2 GCC | 2026-10-06 | decoded from the record at `0x22000000`; [D095] had assumed it | [D096] |
| RA8M2 IAR | 2026-10-09 | decoded, both measurements matching the signed images' SHA-256 TLVs | [D105] |

Measured boot had never been enabled anywhere until 2026-10-02 ([D080], [D081]).

---

## 6. RA6E1

RA6E1 is the part RA6M5 and RA8M2 are derived from. It carries milestones M1 to M3 and is not
re-run against the current build.

| Run | Date | Result | Source |
|---|---|---|---|
| All 13 secure services, smoke-tested from non-secure | 2026-08-30 | pass | the RA6E1 bring-up record, not part of this delivery |
| `tf-m-tests` non-secure regression | 2026-09-02 | 5/5 suites | the RA6E1 bring-up record, not part of this delivery |
| PSA Arch crypto, `TFM_ISOLATION_LEVEL=3`, IPC, EK-RA6E1 | 2026-09-08 | every visible `TEST RESULT` read PASSED | [D015] |

[D015] states its own limit: the transcript has RTT dropouts and no end-of-suite summary was
captured, so "no failure appeared" is not a certified clean sweep. It is the evidence that
validated `PLATFORM_HAS_ISOLATION_L3_SUPPORT`, which [D008] had declared on a build and a static
region count alone.

RA6E1 is built with the [D121] `tfm_spm` move and will not be run against it ([D124]).

---

## 7. Where the wording outruns the evidence

Four places. Each is recorded in the log itself; none is a new finding here.

| Claim | What the evidence actually is | Source |
|---|---|---|
| [D122]'s RA6M5 L2 and L1+IPC cells read "green" | both captures are secure 9/9 with the non-secure half truncated. Every entry from [D113] onward means secure **and** non-secure by "green", so these two rows should read secure-only | [D125] §4 |
| [D123] §2's RA6M5 IAR L2 cell | non-secure 7/7 was captured; the secure suite "also passed" but its RTT output was not captured, so the secure half is reported rather than recorded. [D123] says so itself | [D128] §4 |
| [D115] §1's RA8M2 L3 secure half | "the secure suite passed as far as the captured log runs". The non-secure half was captured separately and cleanly | [D115] §1, [D116] §3 |
| RA8M2 GCC PSA Arch attestation, 1 / 0 / 0 | the figure appears in [D106]'s M5 table and in `RA8M2_SOLUTION.md`, in both cases without a citation. **No entry records that run.** [D096] confirms the attestation launch did boot `m2cry` / `m2att` on RA8M2 GCC, so the run happened; its tally has no entry behind it | [D106], [D096] |

### An RTT capture can truncate silently, and it looks like a hang

[D072] worked out the tell, and it is worth reusing before anyone reports a failure:

- Output stops **after** a result line and the next test is never announced — suspect the
  capture.
- Output stops **after** a `Description:` line — suspect the target, and the named test is where
  to look.

A target that hangs inside a test prints that test's header first, because the framework emits it
before the body runs. The non-secure RTT up-buffer is 4 KB against roughly 15 KB of log, which is
why the capture is the likelier suspect. The first IAR SLIH run looked like a hang and was not:
re-running the same binaries completed normally ([D072]).

---

## 8. One coverage note that no suite can reach

`mbedtls_aes_crypt_ctr()` in FSP 6.7's `aes_alt.c` ignores `nc_off` and `stream_block` and
mishandles partial blocks. PSA Arch 236 and 237 pass on both parts, short-input CTR checks
included, because the PSA cipher layer never reaches that function with a partial block. No suite
in this matrix can see the defect, and a direct Mbed TLS CTR caller still hits it. Closing it
needs a unit test against `mbedtls_aes_crypt_ctr()` itself, not another PSA-level suite
([D099]).

---

## 9. Suites that have never run

Enumerated from `tf-m-tests` and `psa-arch-tests` and checked against every build tree. These
are gaps in coverage, not known failures.

| Suite | Option | Why it has not run | Worth running? |
|---|---|---|---|
| Firmware Update | `TEST_S_FWU`, `TEST_NS_FWU` | `TFM_PARTITION_FIRMWARE_UPDATE` is OFF on both parts | The highest value of these. It exercises the PSA Firmware Update API over the MCUboot slots the port already has, and the bootloader half is proven on RA8M2. The RA8M2 secure slot has little spare room, so the partition may not fit without turning something off |
| SLIH above isolation 1 | `CONFIG_TFM_SLIH_API` | No SLIH tree or launch exists above isolation 1, and none at all on RA8M2. The SLIH service declares the same MMIO region as FLIH, and that path has never been exercised above isolation 1 | Yes, once the trees and launches are made |
| PSA Arch Firmware Framework | `TEST_PSA_API=IPC` | Only the crypto, attestation and storage suites have been built | Yes. It is a different test body from the developer-API suites already run |
| FPU | `TEST_S_FPU`, `TEST_NS_FPU` | `CONFIG_TFM_ENABLE_CP10CP11` is OFF and the port is soft-float throughout | Only if floating point is enabled. RA8M2 is a Cortex-M85 with FP hardware, so this is a real gap for that part |
| Non-secure client ID management | `TEST_NS_MANAGE_NSID` | `TFM_NS_MANAGE_NSID` is not set | Yes, and cheap |
| QCBOR and t_cose self-tests | `TEST_NS_QCBOR`, `TEST_NS_T_COSE` | never enabled | Yes, and cheap. Both libraries already ship, linked for attestation |
| Multi-core | `TEST_NS_MULTI_CORE` | `TFM_MULTI_CORE_TOPOLOGY` is OFF and the second core is unused | Not applicable while the port is single-core |

Covered, for contrast: Protected Storage, Internal Trusted Storage, Crypto, Attestation,
Platform, the SFN backend, FLIH interrupt handling on both parts and both toolchains, and the
PSA Arch crypto, attestation and storage suites. **SLIH is covered on RA6M5 at isolation 1
only**, which is why it appears in the table above as well.

One further gap is not a suite that could be run at all: §8 describes a defect that no
PSA-level suite can reach.
