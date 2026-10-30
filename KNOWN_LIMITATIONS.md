# Known limitations

What the port does not do, what is untested, and what is known to be broken. Test runs are in
[TEST_RESULTS.md](TEST_RESULTS.md).

---

## 1. Before production

The shipped configuration is for development only. [README.md](README.md) §"Security status"
lists what must change before production; [DESIGN.md](DESIGN.md) §13 says how.

---

## 2. Crypto

### Accelerated

| Part | Engine | Accelerated |
|---|---|---|
| RA6M5 | SCE9 | AES (128/192/256, ECB/CBC/CTR), AES-GCM, CMAC, SHA-256, ECP and ECDSA, RSA |
| RA8M2 | RSIP-E50D | the same set, with the RSA key-generation exception below |

BL2 also hashes images on the engine rather than in software.

### In software, by choice

**AES-CCM runs in software**, because FSP's SCE9 CCM caps associated data at 110 bytes and
Protected Storage exceeds that. The AES block operation underneath is still accelerated.

### Unavailable

These are turned off in the accelerator configuration for both engines
(`platform/ext/accelerator/renesas/{sce9,rsip_e50d}/crypto_accelerator_config.h`):

| Algorithm | Why |
|---|---|
| `PSA_WANT_ALG_DETERMINISTIC_ECDSA` | neither engine implements RFC 6979; attestation signs with plain `PSA_ALG_ECDSA` |
| `PSA_WANT_ECC_SECP_R1_521` | RA6M5: SCE9 has no procedure. RA8M2: RSIP-E50D supports it; it is disabled by configuration and costs about 23 KB of secure code. To enable, delete the `#undef` in `rsip_e50d/crypto_accelerator_config.h` and re-run the PSA Arch crypto suite |
| `PSA_WANT_ECC_MONTGOMERY_255` | as P-521: impossible on RA6M5, disabled by configuration on RA8M2 |

**RSA-2048 key generation in plaintext format fails on RA8M2** (PSA Arch crypto test 216). FSP's
`rsa_alt_process.c` permits it only on SCE7, SCE9 and RSIP-E51A, and no configuration changes
that; `PSA_CRYPTO_CFG_RSA_FORMAT` is already `3`. Request a wrapped key for hardware key
generation on RSIP-E50D. All other RSA-2048 operations work on both parts.

### Untested

**ECDSA P-384 is built but untested.** Its regression test (`TFM_S/NS_CRYPTO_TEST_1056`)
self-skips on platforms without Arm CryptoCell and still reports PASSED. Test P-384 yourself
before relying on it.

**FSP 6.7's `mbedtls_aes_crypt_ctr()` mishandles partial blocks** (it ignores `nc_off` and
`stream_block`). PSA cipher calls never reach it with a partial block, so the PSA suites pass;
direct Mbed TLS callers are affected and no suite here covers them.

---

## 3. Boot and upgrade

**The MCUboot upgrade path has run on RA8M2 only**: install confirmed on both toolchains,
secondary erase on GCC ([TEST_RESULTS.md](TEST_RESULTS.md) §4). It has never run on RA6M5 or
RA6E1.

Images signed at one `MCUBOOT_ALIGN_VAL` are rejected by a BL2 built at another; see
[CONFIGURATION.md](CONFIGURATION.md).

On RA8M2, image 0's secondary slot sits below its primary; see
[RA8M2_SOLUTION.md](RA8M2_SOLUTION.md).

**Firmware Update is off and untested** (`TFM_PARTITION_FIRMWARE_UPDATE=OFF`). Enabling it brings
TFMV-9 into scope; see [README.md](README.md) §"Security status" item 8.

**A passing attestation suite does not prove measured boot**: with no software components
recorded the token still verifies. Confirm by reading the boot record
([TEST_RESULTS.md](TEST_RESULTS.md) §5).

---

## 4. Open hazards

### Never build `bl2_bin` on its own

The full build re-emits and checks a safe flat binary. Building the `bl2_bin` target alone writes
the coalesced image (about 16.8 MB) that destroyed two boards. Flashing rule:
[GETTING_STARTED.md](GETTING_STARTED.md) §6; mechanism: [DESIGN.md](DESIGN.md) §8.4.

### Do not launch from `e2_baseline/`

Every shipped launch keeps `setTZBoundaries` false for every probe
([GETTING_STARTED.md](GETTING_STARTED.md) §6). The two `Debug_SSD` launches in `e2_baseline/`
keep `true` because they show unmodified e2 output.

### Secure-slot space

The signed image nearly fills the slot, but that does not limit added code; the secure region
does. Figures and method: [CONFIGURATION.md](CONFIGURATION.md) §6.

---

## 5. Debug and logging

**RTT**: each image has its own control block at a per-build address
([GETTING_STARTED.md](GETTING_STARTED.md) §6). A capture can truncate silently: output that stops
after a result line is the capture, not a hang.

**Only four launches load what the application scripts build**: `ra6m5_TFM_sce9_{gcc,iar}` and
`ra8m2_TFM_app_{gcc,iar}`. Every other launch flashes its own tree under `C:\b`, not your
build, so running an application build and then one of those flashes different images or
fails on missing files ([GETTING_STARTED.md](GETTING_STARTED.md) §6). RA6M5 launches take debug symbols from the e2
project's `Debug/ra6m5_gcc_nonsecure.elf`, not the flashed image. Each launch also records a
local SVD path and source-lookup entry from the author's machine; neither affects what is
flashed.

---

## 6. Platform scope

Part status: [README.md](README.md). RA6M4 is not part of this delivery.

**GCC and IAR projects target different boards.** RA8M2: `ra8m2_ek` (GCC), `ra8m2_ek_v2` (IAR).
RA6M5: `RA6M5_2 CK` (GCC), `RA6M5 CK` (IAR), which changes the security attribution of 16 pins.
Both pass on hardware; regenerating one set against the other's board changes the BSP.

---

## 7. Planned work

- **TF-M 2.3 and Mbed TLS v4**, after FSP migrates to Mbed TLS v4.1. Until then the port is TF-M
  v2.2.0 with FSP's Mbed TLS 3.6.6.
- **RASC-generated projects.** RASC already emits an equivalent CMake project set on RA6M5;
  debugging is unsolved, because RASC projects cannot be imported into e2 studio.
- **Suites never run** (Firmware Update, SLIH above isolation 1, PSA Arch Firmware Framework):
  [TEST_RESULTS.md](TEST_RESULTS.md) §9.
