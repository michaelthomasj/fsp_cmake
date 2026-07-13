/*
 * Copyright (c) 2026 Renesas Electronics Corporation. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * mbedTLS USER config for the TF-M BL2 build (software crypto).
 *
 * The RASC-generated mbedTLS config (ra_cfg/arm/mbedtls/config.h) enables a set
 * of MBEDTLS_*_ALT macros that route crypto to the RA6M4 SCE9 hardware. mbedTLS
 * includes THIS file (via MBEDTLS_USER_CONFIG_FILE) AFTER the main config, so we
 * disable those ALT macros here to fall back to the portable software
 * implementations - WITHOUT editing the RASC-generated config.
 *
 * This keeps BL2 on software crypto for bring-up. To switch BL2 to hardware
 * crypto later, stop passing this user config (or drop the #undef lines) so the
 * SCE9 ALT path in the RASC config takes effect again.
 *
 * Do NOT set MBEDTLS_USER_CONFIG_FILE to this file for a hardware-crypto build.
 */
#ifndef RA6M4_BL2_MBEDTLS_USER_CONFIG_H
#define RA6M4_BL2_MBEDTLS_USER_CONFIG_H

/* --- AES (whole module + per-function ALTs) --- */
#undef MBEDTLS_AES_ALT
#undef MBEDTLS_AES_SETKEY_ENC_ALT
#undef MBEDTLS_AES_SETKEY_DEC_ALT
#undef MBEDTLS_AES_ENCRYPT_ALT
#undef MBEDTLS_AES_DECRYPT_ALT

/* --- Symmetric / AEAD / MAC --- */
#undef MBEDTLS_CCM_ALT
#undef MBEDTLS_CMAC_ALT
#undef MBEDTLS_GCM_ALT
#undef MBEDTLS_CIPHER_ALT

/* --- Hash --- */
#undef MBEDTLS_SHA256_ALT

/* --- Public key: RSA / ECP / ECDSA / ECDH --- */
#undef MBEDTLS_RSA_ALT
#undef MBEDTLS_ECP_ALT
#undef MBEDTLS_ECDSA_VERIFY_ALT
#undef MBEDTLS_ECDSA_SIGN_ALT
#undef MBEDTLS_ECDH_ALT

/* --- RNG: use software DRBG. KEEP MBEDTLS_ENTROPY_HARDWARE_ALT: mbedTLS needs
 *     it to pull entropy from the RA TRNG (the entropy source stays hardware even
 *     though the crypto algorithms are software). --- */
#undef MBEDTLS_CTR_DRBG_C_ALT

/* --- Platform hooks tied to the SCE9 setup/teardown --- */
#undef MBEDTLS_PLATFORM_SETUP_TEARDOWN_ALT

#endif /* RA6M4_BL2_MBEDTLS_USER_CONFIG_H */
