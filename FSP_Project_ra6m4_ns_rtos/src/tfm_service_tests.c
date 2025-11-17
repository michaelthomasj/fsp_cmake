/*
 * Copyright (c) 2024, Renesas Electronics Corporation. All rights reserved.
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * TF-M Service Tests Implementation
 *
 * This file implements comprehensive tests for TF-M PSA services:
 * - Initial Attestation
 * - Internal Trusted Storage (ITS)
 * - Crypto (Random, SHA-256)
 * - HUK (Hardware Unique Key) Derivation
 */

#include "tfm_service_tests.h"

#ifdef TFM_NS_CLIENT

#include "psa/error.h"
#include "psa/initial_attestation.h"
#include "psa/internal_trusted_storage.h"
#include "psa/crypto.h"
#include "tfm_ns_interface.h"
#include "tfm_platform_api.h"
#include "tfm_ioctl_api.h"
#include "tfm_crypto_defs.h"
#include <string.h>

/* Key derivation variables for HUK test */
static const uint8_t derivedKey1Label[] = "key_1";
static psa_key_attributes_t derivedKey1Attributes = PSA_KEY_ATTRIBUTES_INIT;
static psa_key_handle_t derivedKey1Handle;
static psa_key_derivation_operation_t derivedKey1Operation = PSA_KEY_DERIVATION_OPERATION_INIT;
static uint8_t g_exportedDerivedKey1[PSA_BITS_TO_BYTES(256)];
static size_t g_exportedDerivedKey1Length = 0;

int tfm_ns_interface_init_wrapper(void)
{
    uint32_t result = tfm_ns_interface_init();
    return (result == 0) ? 0 : -1;
}

int test_tfm_attestation(void)
{
    uint8_t challenge[33] = {0x2a};
    size_t size = 0;
    size_t token_buf_size = 800;
    uint8_t token_buf[800] = {0x3b};
    size_t token_size = 0;

    /* Get token size */
    if (PSA_SUCCESS != psa_initial_attest_get_token_size(32, &size))
    {
        return -1;  /* Attestation service get token size failed */
    }

    /* Get attestation token */
    if (PSA_SUCCESS != psa_initial_attest_get_token(challenge, 32, token_buf,
                                                     token_buf_size, &token_size))
    {
        return -2;  /* Attestation service get token failed */
    }

    return 0;  /* Test passed */
}

int test_tfm_storage(void)
{
    uint8_t data1[10] = {0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa};
    uint8_t read_buf[10];
    psa_storage_uid_t uid = 1;
    size_t data_length = 10;
    psa_storage_create_flags_t flags = PSA_STORAGE_FLAG_NO_CONFIDENTIALITY |
                                       PSA_STORAGE_FLAG_NO_REPLAY_PROTECTION;

    /* Write data to storage */
    if (PSA_SUCCESS != psa_its_set(uid, data_length, (const void *)&data1[0], flags))
    {
        return -1;  /* Storage service set failed */
    }

    /* Read data from storage */
    size_t read_length;
    if (PSA_SUCCESS != psa_its_get(uid, 0, data_length, (void *)read_buf, &read_length))
    {
        return -2;  /* Storage service get failed */
    }

    /* Verify data matches */
    if (memcmp(data1, read_buf, data_length) != 0)
    {
        return -3;  /* Data mismatch */
    }

    return 0;  /* Test passed */
}

int test_tfm_crypto_random(void)
{
    uint8_t random_data[10];
    size_t data_length = 10;

    if (PSA_SUCCESS != psa_generate_random(random_data, data_length))
    {
        return -1;  /* Crypto random generation failed */
    }

    return 0;  /* Test passed */
}

int test_tfm_crypto_hash(void)
{
    psa_algorithm_t alg = PSA_ALG_SHA_256;
    psa_hash_operation_t operation = {0};

    /* Test vector 1: "abc" */
    uint8_t input_1[] = {'a', 'b', 'c'};
    uint8_t expected_hash_1[] =
    {
        0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea, 0x41, 0x41, 0x40, 0xde,
        0x5d, 0xae, 0x22, 0x23, 0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
        0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad
    };

    /* Test vector 2: "abcdddddddd" */
    uint8_t input_2[] = {'a', 'b', 'c', 'd', 'd', 'd', 'd', 'd', 'd', 'd', 'd'};
    uint8_t expected_hash_2[] =
    {
        0x7b, 0xd3, 0x40, 0xd0, 0x29, 0xf7, 0x61, 0xd7, 0xaf, 0x22, 0xaf, 0x96,
        0xeb, 0xaf, 0xba, 0x8f, 0xbe, 0x2b, 0xd6, 0xb3, 0x91, 0x58, 0xb6, 0xe2,
        0x13, 0x81, 0x64, 0x18, 0xad, 0xd4, 0x14, 0x3b
    };

    size_t expected_hash_len = PSA_HASH_LENGTH(alg);

    /* Test hash 1 */
    if (PSA_SUCCESS != psa_hash_setup(&operation, alg))
        return -1;
    if (PSA_SUCCESS != psa_hash_update(&operation, input_1, sizeof(input_1)))
        return -2;
    if (PSA_SUCCESS != psa_hash_verify(&operation, expected_hash_1, expected_hash_len))
        return -3;
    if (PSA_SUCCESS != psa_hash_abort(&operation))
        return -4;

    /* Test hash 2 */
    if (PSA_SUCCESS != psa_hash_setup(&operation, alg))
        return -5;
    if (PSA_SUCCESS != psa_hash_update(&operation, input_2, sizeof(input_2)))
        return -6;
    if (PSA_SUCCESS != psa_hash_verify(&operation, expected_hash_2, expected_hash_len))
        return -7;
    if (PSA_SUCCESS != psa_hash_abort(&operation))
        return -8;

    return 0;  /* Test passed */
}

int test_tfm_huk_derivation(void)
{
    psa_status_t status;

    /* Set the key attributes for the derived key */
    psa_set_key_usage_flags(&derivedKey1Attributes, PSA_KEY_USAGE_DERIVE | PSA_KEY_USAGE_EXPORT);
    psa_set_key_algorithm(&derivedKey1Attributes, PSA_ALG_HKDF(PSA_ALG_SHA_256));
    psa_set_key_type(&derivedKey1Attributes, PSA_KEY_TYPE_DERIVE);
    psa_set_key_bits(&derivedKey1Attributes, 256);

    /* Set up a key derivation operation with HUK derivation as the alg */
    status = psa_key_derivation_setup(&derivedKey1Operation, PSA_ALG_HKDF(PSA_ALG_SHA_256));
    if (status != PSA_SUCCESS)
        return -1;

    /* Setup a key derivation operation with HUK */
    status = psa_key_derivation_input_key(&derivedKey1Operation, PSA_KEY_DERIVATION_INPUT_SECRET,
                                          TFM_BUILTIN_KEY_ID_HUK);
    if (status != PSA_SUCCESS)
        return -2;

    /* Supply the key label as an input to the key derivation */
    status = psa_key_derivation_input_bytes(&derivedKey1Operation, PSA_KEY_DERIVATION_INPUT_INFO,
                                            derivedKey1Label, sizeof(derivedKey1Label));
    if (status != PSA_SUCCESS)
        return -3;

    /* Create the key from the key derivation operation */
    status = psa_key_derivation_output_key(&derivedKey1Attributes, &derivedKey1Operation,
                                           &derivedKey1Handle);
    if (status != PSA_SUCCESS)
        return -4;

    /* Free resources associated with the key derivation operation */
    status = psa_key_derivation_abort(&derivedKey1Operation);
    if (status != PSA_SUCCESS)
        return -5;

    /* Export the derived key for verification */
    status = psa_export_key(derivedKey1Handle, g_exportedDerivedKey1,
                           sizeof(g_exportedDerivedKey1), &g_exportedDerivedKey1Length);
    if (status != PSA_SUCCESS)
        return -6;

    /* Verify exported key length */
    if (g_exportedDerivedKey1Length != 32)  /* 256 bits = 32 bytes */
        return -7;

    return 0;  /* Test passed */
}

int run_all_tfm_tests(void)
{
    int result;

    /* Initialize TF-M interface */
    result = tfm_ns_interface_init_wrapper();
    if (result != 0)
        return -1;

    /* Run all tests */
    result = test_tfm_attestation();
    if (result != 0)
        return -10 + result;

    result = test_tfm_storage();
    if (result != 0)
        return -20 + result;

    result = test_tfm_crypto_random();
    if (result != 0)
        return -30 + result;

    result = test_tfm_crypto_hash();
    if (result != 0)
        return -40 + result;

    result = test_tfm_huk_derivation();
    if (result != 0)
        return -50 + result;

    return 0;  /* All tests passed */
}

#else /* TFM_NS_CLIENT not defined */

/* Stub implementations when not building with TF-M */
int tfm_ns_interface_init_wrapper(void) { return -1; }
int test_tfm_attestation(void) { return -1; }
int test_tfm_storage(void) { return -1; }
int test_tfm_crypto_random(void) { return -1; }
int test_tfm_crypto_hash(void) { return -1; }
int test_tfm_huk_derivation(void) { return -1; }
int run_all_tfm_tests(void) { return -1; }

#endif /* TFM_NS_CLIENT */
