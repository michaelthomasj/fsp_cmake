/*
 * Copyright (c) 2024, Renesas Electronics Corporation. All rights reserved.
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * TF-M Service Tests Header
 *
 * This file provides test functions for validating TF-M PSA services
 * from a FreeRTOS-based non-secure application.
 */

#ifndef TFM_SERVICE_TESTS_H
#define TFM_SERVICE_TESTS_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Initialize TF-M Non-Secure Interface
 *
 * Must be called before using any TF-M services.
 * Call this at the beginning of your FreeRTOS task or main thread.
 *
 * @return 0 on success, non-zero on error
 */
int tfm_ns_interface_init_wrapper(void);

/**
 * @brief Test TF-M Initial Attestation Service
 *
 * Tests:
 * - psa_initial_attest_get_token_size()
 * - psa_initial_attest_get_token()
 *
 * @return 0 on success, non-zero on failure
 */
int test_tfm_attestation(void);

/**
 * @brief Test TF-M Internal Trusted Storage Service
 *
 * Tests:
 * - psa_its_set() - Write data to secure storage
 * - psa_its_get() - Read data from secure storage
 *
 * @return 0 on success, non-zero on failure
 */
int test_tfm_storage(void);

/**
 * @brief Test TF-M Crypto Service - Random Generation
 *
 * Tests:
 * - psa_generate_random() - Generate cryptographically secure random data
 *
 * @return 0 on success, non-zero on failure
 */
int test_tfm_crypto_random(void);

/**
 * @brief Test TF-M Crypto Service - SHA-256 Hash
 *
 * Tests:
 * - psa_hash_setup()
 * - psa_hash_update()
 * - psa_hash_verify()
 *
 * Uses known SHA-256 test vectors to validate hash computation.
 *
 * @return 0 on success, non-zero on failure
 */
int test_tfm_crypto_hash(void);

/**
 * @brief Test TF-M HUK (Hardware Unique Key) Derivation
 *
 * Tests:
 * - psa_key_derivation_setup() with HKDF-SHA256
 * - psa_key_derivation_input_key() with TFM_BUILTIN_KEY_ID_HUK
 * - psa_key_derivation_output_key()
 * - psa_export_key()
 *
 * Derives a 256-bit key from the Hardware Unique Key.
 *
 * @return 0 on success, non-zero on failure
 */
int test_tfm_huk_derivation(void);

/**
 * @brief Run All TF-M Service Tests
 *
 * Executes all test functions in sequence:
 * 1. Attestation
 * 2. Storage (ITS)
 * 3. Crypto Random
 * 4. Crypto Hash (SHA-256)
 * 5. HUK Derivation
 *
 * @return 0 if all tests pass, non-zero if any test fails
 */
int run_all_tfm_tests(void);

#ifdef __cplusplus
}
#endif

#endif /* TFM_SERVICE_TESTS_H */
