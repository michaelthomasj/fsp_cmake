# Known limitations

What this port does not do, what has not been tested, and what is known to be broken. Read it
with [README.md](README.md) §"Security status", which lists what must change before production, and
[TEST_RESULTS.md](TEST_RESULTS.md), which records what has run on hardware.

Everything here is a current statement about the delivered code. [DECISIONS.md](DECISIONS.md)
holds the reasoning and the history.

---

## 1. Before production

The shipped configuration is a development configuration. [README.md](README.md) §"Security
status" is the list; [DESIGN.md](DESIGN.md) §13 says how to address each item. In short: the
signing keys are the public TF-M sample keys, provisioning supplies dummy HUK and IAK values,
anti-rollback counters are left at `1`, the clock and low-power registers are writable from the
non-secure world, and the device lifecycle and secure debug are not enforced.

**None of these is a defect in the port.** They are the settings a development board needs and a
product must not keep.

---

## 2. Crypto

Both parts route PSA crypto through FSP's Mbed TLS `*_ALT` sources, so what the hardware
accelerates depends on the engine fitted to the part.

### Accelerated

| Part | Engine | Accelerated |
|---|---|---|
| RA6M5 | SCE9 | AES (128/192/256, ECB/CBC/CTR), AES-GCM, CMAC, SHA-256, ECP and ECDSA, RSA |
| RA8M2 | RSIP-E50D | the same set, with the RSA key-generation exception below |

BL2 also hashes images on the engine rather than in software.

### In software, by choice

**AES-CCM.** FSP's SCE9 CCM caps associated data at 110 bytes and Protected Storage exceeds
that, so CCM is built from software. It still reaches the engine block by block through the
cipher and AES paths, so the cost is the mode logic rather than the block operation.

### Unavailable

These are turned off in the accelerator configuration for both engines
(`platform/ext/accelerator/renesas/{sce9,rsip_e50d}/crypto_accelerator_config.h`):

| Algorithm | Why |
|---|---|
| `PSA_WANT_ALG_DETERMINISTIC_ECDSA` | neither engine implements RFC 6979. The attestation key signs with plain `PSA_ALG_ECDSA`. PSA Arch crypto test 252 skips for this reason |
| `PSA_WANT_ECC_SECP_R1_521` | not supported by the engines |
| `PSA_WANT_ECC_MONTGOMERY_255` | not supported by the engines |

**RSA-2048 key generation in plaintext format is unavailable on RA8M2, and there is no switch
for it.** The guard is in FSP's `rsa_alt_process.c`: `mbedtls_rsa_gen_key()` returns
`MBEDTLS_ERR_PLATFORM_FEATURE_UNSUPPORTED` unless the part is SCE7, SCE9 or RSIP-E51A, and E50D
is not in that list. RA6M5 passes because SCE9 is. Every other RSA-2048 operation works on both
parts. Hardware RSA key generation on E50D requires the caller to request a wrapped key.
Raising `PSA_CRYPTO_CFG_RSA_FORMAT` does not help, because it is already `3` and is not what
selects the failing path. This is the single PSA Arch crypto failure on RA8M2, test 216 check 4.

### Untested

**ECDSA P-384 is untested here and probably works.** `PSA_WANT_ECC_SECP_R1_384` is not
disabled, so the algorithm is built, but the regression test that would exercise it
(`TFM_S_CRYPTO_TEST_1056` / `TFM_NS_CRYPTO_TEST_1056`) self-skips on every platform that is not
Arm CryptoCell — its gate tests `CC3XX_RUNTIME_ENABLED`. The test reports PASSED without
testing anything. **Do not read a passing regression run as P-384 coverage.** It needs a
standalone check before anyone claims P-384 support.

**The multi-part engine lock.** While a multi-part AES, GCM or CMAC operation is open it holds
the engine, and `psa_generate_random` fails for every caller until that operation completes or
is aborted. This comes from reading the driver, not from an observed failure, and no suite run
here exercises the pattern.

**A software CTR defect no suite here can reach.** FSP 6.7's `mbedtls_aes_crypt_ctr()` ignores
`nc_off` and `stream_block` and mishandles partial blocks. PSA Arch tests 236 and 237 pass on
both parts, short-input CTR checks included, because the PSA cipher layer never reaches that
function with a partial block. A direct Mbed TLS CTR caller still hits it. Closing this needs a
unit test against the function itself, not another PSA-level suite.

---

## 3. Boot and upgrade

**The MCUboot upgrade path has been exercised on RA8M2 only.** Both images install from their
secondary slots and a second reset erases the secondary, under both toolchains. RA6M5 has no
upgrade launch and the path has never run there. RA6E1 sets `MCUBOOT_ALIGN_VAL` to 128 to match
its code-flash write unit, and that fix has never been exercised, because it only takes effect
once BL2 writes code flash.

**Image alignment is not interchangeable.** Images signed at one alignment are rejected by a BL2
built at another, because the trailer magic differs. Reflash every slot after changing it and do
not mix.

**Slot order is reversed for image 0 on RA8M2.** The secure secondary sits below the secure
primary, so `rsp.br_image_off` of `0x68000` is the primary. Image 1 is the usual way round.
Anything that reads a `boot_rsp` or computes a flash row must account for this.

**Firmware Update is off and untested.** `TFM_PARTITION_FIRMWARE_UPDATE` is `OFF` on all parts.
Turning it on brings advisory TFMV-9 (CVE-2025-53022) into scope and you should move to
TF-Mv2.2.2 first.

**Measured boot is on, and a passing attestation suite does not prove it works.** With no
software components recorded, `attest_add_all_sw_components()` emits `IAT_NO_SW_COMPONENTS` and
returns success, so the attestation suite passes either way. Read the boot record directly to
confirm it.

---

## 4. Open hazards

### Flashing a flat binary can destroy the board

The option-setting words live in discrete flash regions. A plain `objcopy -O binary` coalesces
them into one segment and zero-fills the reserved bytes between, which writes `0x00` into
defined option registers. Two EK-RA6M4 boards were lost this way; no recovery is known.

**Flash `bl2.elf`, `bl2.hex` or `bl2.srec` — never `bl2.bin`.**

The full build re-emits a safe flat binary and verifies it, but **building the `bl2_bin` target
on its own still writes the coalesced image.** The rule that follows is: build everything, never
`bl2_bin` alone. If you must look at a flat binary, a safe one is tens of kilobytes and a
coalesced one is about 16.8 MB. Do not use any single byte count as the test — the safe size
differs between build configurations.

### The debugger will program the TrustZone boundaries wrongly

Every launch configuration must keep `setTZBoundaries` `false` for every probe it names.
Launched against BL2, the debugger derives the boundaries from the wrong symbols.

Every shipped launch now carries `false` for every probe it names, not only for the selected
one, so switching probe cannot arm the setting. The two `Debug_SSD` launches under
`e2_baseline/` keep `true` deliberately, because that directory shows the unmodified e2 output.
**Do not launch from `e2_baseline/`.**

### Re-partitioning erases the part

Programming the TrustZone boundaries with RDPM erases both code and data flash. Reflash all three
images afterwards. [RECONFIGURING_THE_LAYOUT.md](RECONFIGURING_THE_LAYOUT.md) is the procedure.

### The secure slot is nearly full

RA6M5 has about 1.7 KB spare and RA8M2 about 0.7 KB, measured against the signed payload rather
than the raw image. Enabling a diagnostic option that costs a few kilobytes will fail to link.
[README.md](README.md) §"Freeing space in the secure image" gives the measured cost of each.

---

## 5. Debug and logging

**RTT is unreliable across the boot chain by construction.** BL2, the secure image and the
non-secure image each initialise their own RTT control block, and the address differs per build.
A capture can also truncate silently: if output stops after a result line and the next test is
never announced, suspect the capture rather than the target.

**Most launches do not load what the build scripts produce.** Four do, one per part and
toolchain: `ra6m5_TFM_sce9_{gcc,iar}` and `ra8m2_TFM_app_{gcc,iar}`, whose load entries are the
default build directories of the four application scripts. Every other launch names a build tree
of its own by absolute path, so running an application build and then one of those flashes
different images or fails on missing files. [GETTING_STARTED.md](GETTING_STARTED.md) §6 has the
table.

All nineteen RA6M5 launches additionally take their debug program from the e2 project —
`Debug/ra6m5_gcc_nonsecure.elf` — rather than from a TF-M image, so the symbols e2 loads are
not those of the image being flashed. The fifteen RA8M2 launches name a `bl2.elf` instead.

---

## 6. Platform scope

| Part | Status |
|---|---|
| RA6M5 | supported, both toolchains |
| RA8M2 | supported, both toolchains. CPU1 is unused; the port is single-core |
| RA6E1 | reference only. It is the port the two supported parts derive from, and it is not maintained against the current build |

RA6M4 is not part of this delivery.

**The RA8M2 project sets target different board revisions between toolchains.** The GCC projects
select `ra8m2_ek` and the IAR projects `ra8m2_ek_v2`. Both have passed on hardware, so the
difference is tolerable, but regenerating either set against the other's board changes the
generated BSP. The RA6M5 projects differ similarly in pin configuration: the GCC solution
selects `RA6M5_2 CK` and the IAR solution `RA6M5 CK`, which changes the security attribution of
16 pins.

---

## 7. Planned work

Listed without dates, because none is committed.

- **Mbed TLS v4 and TF-M 2.3.** Gated on FSP's own migration to Mbed TLS v4.1. The port stays on
  TF-Mv2.2.0 and Mbed TLS 3.6.3 until then.
- **Move the project set to RASC.** The delivered projects are generated by e2 studio. The
  standalone FSP Smart Configurator emits an equivalent CMake project set, and the layout and
  module configuration already match on RA6M5. What is not yet solved is the debug front end:
  RASC projects cannot be imported into e2 studio, and their own launch mechanism has not been
  shown to flash three images with the required erase and boundary settings.
- **Firmware Update.** The bootloader half is proven on RA8M2; what FWU adds is the API that
  places an image in the secondary slot.
- **SLIH above isolation 1, and on RA8M2 at all.** Never run. The trees and launches have to be
  made first.
- **PSA Arch Firmware Framework suite.** Only the crypto, attestation and storage suites have
  been built.
