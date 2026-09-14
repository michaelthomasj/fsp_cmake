# TF-M Execution Flow - Complete Technical Reference

## Overview

This document provides a complete trace of TF-M execution on the Renesas RA6M4 from hardware reset through secure service invocation, with references to actual source code locations.

---

## 1. BOOT SEQUENCE: Hardware Reset → Secure Main

### Reset Vector Entry

**File**: `platform/ext/target/renesas/ra6m4/startup_ra6m4.c`

**Vector Table** (Lines 103-140):
```c
__VECTOR_TABLE[496] = {
    (uint32_t)(&__INITIAL_SP),        // [0] Initial Stack Pointer
    (uint32_t)&Reset_Handler,         // [1] Reset Handler
    (uint32_t)&NMI_Handler,           // [2] NMI Handler
    (uint32_t)&HardFault_Handler,     // [3] Hard Fault Handler
    (uint32_t)&MemManage_Handler,     // [4] MPU Fault Handler
    (uint32_t)&BusFault_Handler,      // [5] Bus Fault Handler
    (uint32_t)&UsageFault_Handler,    // [6] Usage Fault Handler
    (uint32_t)&SecureFault_Handler,   // [7] Secure Fault Handler
    // ... 480 external interrupts
};
```

**Reset_Handler** (Lines 149-166):
```c
void Reset_Handler(void)
{
    __set_PSP((uint32_t)(&__INITIAL_SP));       // Set Process Stack Pointer

    __set_MSPLIM((uint32_t)(&__STACK_LIMIT));   // Set Main Stack Limit
    __set_PSPLIM((uint32_t)(&__STACK_LIMIT));   // Set Process Stack Limit

    __TZ_set_STACKSEAL_S((uint32_t *)(&__STACK_SEAL));  // Stack seal for security

    SystemInit();           // CMSIS system initialization
    __PROGRAM_START();      // C library startup → calls main()
}
```

**Stack Seal Pattern**: `0xFEF5EDA5` - Prevents stack overflow attacks

---

## 2. TF-M CORE INITIALIZATION

### Main Entry Point

**File**: `secure_fw/spm/core/main.c`

**main()** (Lines 95-136):
```c
int main(void)
{
    // 1. Configure MPU to allow access to NS memory (for NS interrupts)
    tfm_arch_config_branch_protection();

    // 2. Set Main Stack Limit for secure world
    tfm_arch_set_msplim((uint32_t)&REGION_NAME(Image$$, ARM_LIB_STACK, $$ZI$$Limit));

    // 3. Initialize Fault Injection Hardening delay counter
    fih_delay_init();

    // 4. Core initialization
    if (tfm_core_init() != TFM_SUCCESS) {
        tfm_core_panic();
    }

    // 5. Set secure exception priorities
    tfm_arch_set_secure_exception_priorities();

    // 6. Trigger SPM initialization via SVC
    BACKEND_SPM_INIT();  // Does not return - starts scheduler

    // Should never reach here
    tfm_core_panic();
}
```

**tfm_core_init()** (Lines 28-93):
```c
static enum tfm_status_e tfm_core_init(void)
{
    // 1. Set up static MPU boundaries (code, data regions)
    tfm_hal_set_up_static_boundaries(&PRIVILEGED_ACCESS_ONLY);

    // 2. Platform-specific initialization
    if (tfm_hal_platform_init() != TFM_HAL_SUCCESS) {
        return TFM_ERROR_GENERIC;
    }

    // 3. Log boot message
    SPMLOG_INFMSG("Booting TF-M "VERSION_FULLSTR"\r\n");

    // 4. Initialize OTP (One-Time Programmable) storage
    res = tfm_plat_otp_init();

    // 5. Platform provisioning if needed
    #ifdef PLATFORM_DEFAULT_PROVISIONING
        tfm_plat_provisioning_perform();
    #endif

    // 6. Configure CPU extensions (FPU, MVE, DSP)
    tfm_arch_config_extensions((void *)&PRIVILEGED_ACCESS_ONLY);

    return TFM_SUCCESS;
}
```

---

## 3. MEMORY PROTECTION SETUP

### MPU Configuration

**File**: `platform/ext/target/renesas/ra6m4/tfm_hal_isolation.c`

**tfm_hal_set_up_static_boundaries()** (Lines 12-50):
```c
enum tfm_hal_status_t tfm_hal_set_up_static_boundaries(uintptr_t *p_spm_boundary)
{
    // Disable MPU before configuration
    ARM_MPU_Disable();

    /* ========== MPU Region 0: Secure Code (Flash) ========== */
    ARM_MPU_SetRegion(
        0,                              // Region number
        ARM_MPU_RBAR(S_CODE_START,      // Base address (0x00020000)
                     ARM_MPU_SH_NON,    // Non-shareable
                     0,                 // Read-only
                     1,                 // Privileged
                     0),                // Execute allowed
        ARM_MPU_RLAR(S_CODE_LIMIT,      // Limit address
                     MPU_ARMV8M_MAIR_ATTR_CODE_IDX)  // Code attributes
    );

    /* ========== MPU Region 1: Secure RAM (Data) ========== */
    ARM_MPU_SetRegion(
        1,                              // Region number
        ARM_MPU_RBAR(S_DATA_START,      // Base address (0x20000000)
                     ARM_MPU_SH_NON,    // Non-shareable
                     0,                 // Read-write
                     1,                 // Privileged
                     1),                // Execute Never (XN)
        ARM_MPU_RLAR(S_DATA_LIMIT,      // Limit address
                     MPU_ARMV8M_MAIR_ATTR_DATA_IDX)  // Data attributes
    );

    // Enable MPU with default privileged access and HardFault/NMI enabled
    ARM_MPU_Enable(MPU_CTRL_PRIVDEFENA_Msk | MPU_CTRL_HFNMIENA_Msk);

    // Set SPM boundary (veneer region at top of secure code)
    *p_spm_boundary = (uintptr_t)(S_CODE_START + S_CODE_SIZE -
                                  CMSE_VENEER_REGION_SIZE);

    return TFM_HAL_SUCCESS;
}
```

### SAU Configuration

**File**: `platform/ext/target/renesas/ra6m4/fsp/ra/fsp/src/bsp/mcu/all/bsp_security.c`

**R_BSP_SecurityInit()** (Lines 199-533):
```c
void R_BSP_SecurityInit(void)
{
    /* ========== Configure SAU Regions ========== */

    // Region 0: Code Flash NSC (Non-Secure Callable)
    SAU->RNR  = 0;
    SAU->RBAR = BSP_FEATURE_BSP_FLASH_NSC_START;
    SAU->RLAR = (BSP_FEATURE_BSP_FLASH_NSC_END & SAU_RLAR_LADDR_Msk) |
                SAU_RLAR_NSC_Msk | SAU_RLAR_ENABLE_Msk;

    // Region 1: SRAM NSC
    SAU->RNR  = 1;
    SAU->RBAR = BSP_FEATURE_BSP_SRAM_NSC_START;
    SAU->RLAR = (BSP_FEATURE_BSP_SRAM_NSC_END & SAU_RLAR_LADDR_Msk) |
                SAU_RLAR_NSC_Msk | SAU_RLAR_ENABLE_Msk;

    // Region 2: Non-Secure Code Flash
    SAU->RNR  = 2;
    SAU->RBAR = BSP_FEATURE_BSP_FLASH_NS_START;  // 0x00080000
    SAU->RLAR = (BSP_FEATURE_BSP_FLASH_NS_END & SAU_RLAR_LADDR_Msk) |
                SAU_RLAR_ENABLE_Msk;  // No NSC bit = NS

    // Region 3: Non-Secure SRAM
    SAU->RNR  = 3;
    SAU->RBAR = BSP_FEATURE_BSP_SRAM_NS_START;   // 0x20020000
    SAU->RLAR = (BSP_FEATURE_BSP_SRAM_NS_END & SAU_RLAR_LADDR_Msk) |
                SAU_RLAR_ENABLE_Msk;

    /* ========== Configure Security Attribution Registers ========== */

    // Set peripheral security (example: UART, ADC, etc.)
    R_SYSTEM->PRCR = BSP_PRV_PRCR_UNLOCK;  // Unlock registers

    // Configure each peripheral's SAR (Security Attribution Register)
    // SAR = 0 → Secure, SAR = 1 → Non-Secure
    R_CPSCU->ICUSARA = 0xFFFFFFFF;  // All ICU events NS
    R_CPSCU->SARARB  = peripheral_security_settings;

    R_SYSTEM->PRCR = BSP_PRV_PRCR_LOCK;    // Lock registers

    /* ========== Enable SAU ========== */
    SAU->CTRL = SAU_CTRL_ALLNS_Msk | SAU_CTRL_ENABLE_Msk;

    /* ========== Configure SCB for TrustZone ========== */
    SCB->AIRCR = (0x05FA << SCB_AIRCR_VECTKEY_Pos) | SCB_AIRCR_SYSRESETREQS_Msk;
    SCB->NSACR = SCB_NSACR_CP10_Msk | SCB_NSACR_CP11_Msk;  // Allow NS to access FPU

    /* ========== FPU Configuration ========== */
    FPU->FPCCR = FPU_FPCCR_TS_Msk |       // Treat FP regs as Secure
                 FPU_FPCCR_CLRONRETS_Msk | // Clear FP regs on return
                 FPU_FPCCR_CLRONRET_Msk;   // Clear on exception return
}
```

---

## 4. SPM INITIALIZATION & PARTITION LOADING

### Trigger SPM Init via SVC

**File**: `secure_fw/spm/include/ffm/backend_ipc.h`

**BACKEND_SPM_INIT Macro** (Lines 18-20):
```assembly
#define BACKEND_SPM_INIT()                  \
    __ASM volatile(                          \
        "SVC %0           \n"  /* Trigger SVC exception */  \
        "BX LR            \n"  /* Return (unreachable) */   \
        : : "I" (TFM_SVC_SPM_INIT)          \
    )
```

### SVC Handler

**File**: `secure_fw/spm/core/arch/tfm_arch_v8m_main.c`

**SVC_Handler()** (Lines 68-88):
```c
void SVC_Handler(void)
{
    uint32_t *msp = (uint32_t *)__get_MSP();
    uint32_t *psp = (uint32_t *)__get_PSP();
    uint32_t exc_return = __get_LR();

    // Determine which stack was used
    bool ns_caller = (exc_return & EXC_RETURN_S) == 0;
    uint32_t *svc_args = (exc_return & EXC_RETURN_SPSEL) ? psp : msp;

    // Get SVC number from instruction
    uint8_t svc_number = ((uint8_t *)svc_args[6])[-2];

    // Handle SPM SVC
    spm_svc_handler(svc_number, svc_args, exc_return);
}
```

**File**: `secure_fw/spm/core/tfm_svcalls.c`

**spm_svc_handler()** (Lines 203-248):
```c
uint32_t spm_svc_handler(uint32_t svc_num, uint32_t *ctx, uint32_t lr)
{
    switch (svc_num) {
    case TFM_SVC_SPM_INIT:
        // Initialize SPM and partitions
        tfm_spm_init();

        // Change EXC_RETURN to Thread mode
        return tfm_arch_free_msp_and_exc_ret(
            lr,
            (uint32_t)SPM_BOOT_STACK_BOTTOM
        );

    case TFM_SVC_PSA_FRAMEWORK_VERSION:
        return (uint32_t)tfm_spm_psa_framework_version();

    case TFM_SVC_PSA_CALL:
        return (uint32_t)tfm_spm_psa_call(/* args from ctx */);

    // ... other PSA APIs

    default:
        SPMLOG_ERRMSG("Unknown SVC number!\r\n");
        return PSA_ERROR_GENERIC_ERROR;
    }
}
```

### SPM Initialization

**File**: `secure_fw/spm/core/spm_ipc.c`

**tfm_spm_init()** (Lines 397-447):
```c
void tfm_spm_init(void)
{
    // 1. Initialize connection/message pools
    spm_init_connection_space();

    // 2. Initialize partition and service lists
    UNI_LIST_INIT_NODE(PARTITION_LIST_ADDR, next);
    UNI_LIST_INIT_NODE(&services_listhead, next);

    // 3. Initialize Non-Secure context
    tfm_nspm_ctx_init();

    // 4. Load all partitions from ROM
    struct partition_t *partition;
    const struct partition_load_info_t *p_ldinf;

    p_ldinf = LOAD_INFO_PSA_ROT;  // Start with PSA RoT partitions

    while (p_ldinf) {
        // Load partition from ROM to RAM
        partition = load_a_partition_assuredly(p_ldinf);

        // Load services for this partition
        load_services_assuredly(p_ldinf, partition, &services_listhead);

        // Load IRQ configurations
        load_irqs_assuredly(p_ldinf);

        // Bind partition to hardware boundary (MPU region)
        tfm_hal_bind_boundary(partition, &partition->boundary);

        // Initialize partition component (thread, stack, etc.)
        backend_init_comp_assuredly(partition, p_ldinf->stack_size,
                                    p_ldinf->entry);

        // Move to next partition
        p_ldinf = p_ldinf->next;
    }

    // Repeat for Application RoT partitions
    p_ldinf = LOAD_INFO_APP_ROT;
    // ... (same loop as above)

    // 5. Post-initialization hook
    tfm_hal_post_partition_init_hook();

    // 6. Start the scheduler - does not return
    backend_system_run();
}
```

**File**: `secure_fw/spm/core/backend_ipc.c`

**backend_init_comp_assuredly()** (Lines 330-351):
```c
void backend_init_comp_assuredly(struct partition_t *p_pt,
                                 uint32_t service_set)
{
    const struct partition_load_info_t *p_pldi = p_pt->p_ldinf;

    // 1. Initialize context control block
    ARCH_CTXCTRL_INIT(&p_pt->ctx_ctrl,
                      LOAD_ALLOCED_STACK_ADDR(p_pldi),
                      p_pldi->stack_size);

    // 2. Watermark the stack for overflow detection
    watermark_stack(p_pt);

    // 3. Initialize thread structure
    THRD_INIT(&p_pt->thrd, &p_pt->ctx_ctrl,
              TO_THREAD_PRIORITY(PARTITION_PRIORITY(p_pldi->flags)));

    // 4. Determine partition type and initialize
    uint32_t entry_addr;

    if (IS_NS_AGENT_TZ(p_pldi)) {
        // NS Agent TZ partition - handles NS to S transitions
        entry_addr = (uint32_t)ns_agent_tz_init(p_pt);
    } else {
        // Regular secure partition
        entry_addr = (uint32_t)partition_init(p_pt);
    }

    // 5. Process partition metadata (PSA API function table, etc.)
    prv_process_metadata(p_pt);

    // 6. Start the thread (add to ready queue)
    thrd_start(&p_pt->thrd,
               POSITION_TO_ENTRY(entry_addr, thrd_fn_t),
               LOAD_ALLOCED_STACK_ADDR(p_pldi),
               p_pldi->stack_size);
}
```

**partition_init()** (Lines 257-287):
```c
static uintptr_t partition_init(struct partition_t *p_pt)
{
    // 1. Set up signals for IPC
    p_pt->signals_allowed = PSA_DOORBELL;  // Doorbell signal
    p_pt->signals_waiting = 0;

    // 2. Initialize message/reply queues
    UNI_LISI_INIT_NODE(p_pt, p_handles);
    UNI_LISI_INIT_NODE(p_pt, p_msgs);

    // 3. Return entry point based on model
    const struct partition_load_info_t *p_pldi = p_pt->p_ldinf;

    if (IS_IPC_MODEL(p_pldi)) {
        // IPC model: Direct entry to partition main
        return p_pldi->entry;
    } else {
        // SFN model: Entry to common SFN thread
        return (uintptr_t)common_sfn_thread;
    }
}
```

**ns_agent_tz_init()** (Lines 290-310):
```c
static uintptr_t ns_agent_tz_init(struct partition_t *p_pt)
{
    // 1. Register NS client ID range
    if (tfm_nspm_register_client_ids(NS_CLIENT_ID_BASE,
                                     NS_CLIENT_ID_LIMIT) != SPM_SUCCESS) {
        return 0;
    }

    // 2. Get SPM context for NS agent
    struct context_ctrl_t *ctx = &p_pt->ctx_ctrl;

    // 3. Get NS entry point from platform HAL
    uint32_t ns_entry = (uint32_t)tfm_hal_get_ns_entry_point();

    // 4. Store NS entry as parameter (r0) for ns_agent_tz_main
    ARCH_CTXCTRL_ALLOCATE_STACK(ctx, ns_entry);

    // 5. Return NS agent entry point
    return (uintptr_t)ns_agent_tz_main;
}
```

### Start Scheduler

**backend_system_run()** (Lines 353-387):
```c
void __attribute__((noreturn)) backend_system_run(void)
{
    // 1. Watermark SPM stack for overflow detection
    watermark_spm_stack((uint8_t *)SPM_THREAD_CONTEXT->sp_limit,
                        (uint8_t *)SPM_THREAD_CONTEXT->sp);

    // 2. Seal thread stacks
    arch_seal_thread_stack(SPM_THREAD_CONTEXT->sp);

    // 3. Set thread query callback
    thrd_set_query_callback(query_state);

    // 4. Start the thread scheduler
    thrd_start_scheduler(&CURRENT_THREAD);

    // 5. Activate first partition boundary (MPU)
    tfm_hal_activate_boundary(&CURRENT_THREAD->p_context_ctrl->boundary);

    // 6. Return to first thread (ns_agent_tz)
    arch_clean_stack_and_launch(CURRENT_THREAD->p_context_ctrl->sp,
                               CURRENT_THREAD->p_context_ctrl->entry);

    // Should never reach here
    tfm_core_panic();
}
```

---

## 5. TRANSITION TO NON-SECURE WORLD

### NS Agent TZ Main

**File**: `secure_fw/partitions/ns_agent_tz/ns_agent_tz_v80m.c`

**ns_agent_tz_main()** (Lines 17-58):
```assembly
__attribute__((naked)) void ns_agent_tz_main(uint32_t c_entry)
{
    __ASM volatile(
        "   .syntax unified                             \n"

        /* r0 = NS entry point (passed as parameter) */

        /* Security check: Verify stack seal pattern */
        "   ldr     r2, [sp, #-8]                       \n"  // Load seal pattern
        "   movw    r3, #0xEDA5                         \n"  // Expected: 0xFEF5EDA5
        "   movt    r3, #0xFEF5                         \n"
        "   cmp     r2, r3                              \n"
        "   bne     reent_panic1                        \n"  // Panic if mismatch

        /* Clear NS bit from entry address (make it NS) */
        "   movs    r2, #1                              \n"
        "   bics    r0, r2                              \n"  // r0 &= ~1

#if CONFIG_TFM_ENABLE_CP10CP11
        /* Clear FPU registers */
        "   vmov    d0, r2, r2                          \n"
        "   vmov    d1, r2, r2                          \n"
        "   vmov    d2, r2, r2                          \n"
        "   vmov    d3, r2, r2                          \n"
        "   vmov    d4, r2, r2                          \n"
        "   vmov    d5, r2, r2                          \n"
        "   vmov    d6, r2, r2                          \n"
        "   vmov    d7, r2, r2                          \n"

        /* Clear FPCA bit */
        "   mrs     r3, control                         \n"
        "   bics    r3, r2, r3                          \n"
        "   msr     control, r3                         \n"
#endif

        /* Clear general purpose registers */
        "   mov     r1, r2                              \n"
        "   mov     r3, r2                              \n"
        "   mov     r4, r2                              \n"
        "   mov     r5, r2                              \n"
        "   mov     r6, r2                              \n"
        "   mov     r7, r2                              \n"
        "   mov     r8, r2                              \n"
        "   mov     r9, r2                              \n"
        "   mov     r10, r2                             \n"
        "   mov     r11, r2                             \n"
        "   mov     r12, r2                             \n"
        "   mov     r14, r2                             \n"

        /* Branch to NS with state change */
        "   bxns    r0                                  \n"

        "reent_panic1:                                  \n"
        "   b       reent_panic1                        \n"
    );
}
```

**Alternative Path - FSP R_BSP_NonSecureEnter()** (bsp_security.c:146-188):
```c
void R_BSP_NonSecureEnter(void)
{
    // 1. Get NS vector table from flash
    uint32_t const *p_ns_vector_table =
        (uint32_t *)BSP_FEATURE_BSP_FLASH_NS_START;  // 0x00080000

    // 2. Get NS Reset_Handler from vector table
    void (*p_ns_reset)(void) = (void (*)(void))p_ns_vector_table[1];

    // 3. Check if NS application exists
    if ((uint32_t)p_ns_reset == BSP_PRV_FLASH_BLANK) {
        // No NS app - infinite loop
        while (1) { __NOP(); }
    }

    // 4. Set NS vector table base
    SCB_NS->VTOR = (uint32_t)p_ns_vector_table;

    // 5. Set NS Main Stack Pointer
    __TZ_set_MSP_NS(p_ns_vector_table[0]);

    // 6. Jump to NS Reset_Handler
    p_ns_reset();  // BXNS instruction
}
```

**Platform HAL NS Entry Points** (tfm_hal_platform.c:43-59):
```c
void *tfm_hal_get_ns_VTOR(void)
{
    return (void *)NS_CODE_START;  // 0x00080000
}

void *tfm_hal_get_ns_MSP(void)
{
    return (void *)*((uint32_t *)NS_CODE_START);  // First word of NS vector
}

void *tfm_hal_get_ns_entry_point(void)
{
    return (void *)*((uint32_t *)(NS_CODE_START + 4));  // NS Reset_Handler
}
```

---

## 6. NS TO S TRANSITIONS - PSA API Calls

### Veneer Function Pattern

**File**: `secure_fw/partitions/ns_agent_tz/psa_api_veneers_v80m.c`

**tfm_psa_call_veneer()** (Lines 146-180):
```assembly
__attribute__((naked, section("SFN")))
psa_status_t tfm_psa_call_veneer(psa_handle_t handle,
                                 uint32_t ctrl_param,
                                 const psa_invec *in_vec,
                                 psa_outvec *out_vec)
{
    __ASM volatile(
        "   .syntax unified                             \n"

        /* Save in_vec and out_vec to stack */
        "   push    {r2, r3}                            \n"

#if TFM_ISOLATION_LEVEL == 3
        /* Set BASEPRI to mask NS interrupts during secure execution */
        "   movs    r2, %[basepri]                      \n"
        "   msr     basepri_max, r2                     \n"
#endif

        /* Security check: Verify stack seal (detect reentrancy) */
        "   ldr     r2, [sp, #-8]                       \n"
        "   movw    r3, #0xEDA5                         \n"
        "   movt    r3, #0xFEF5                         \n"
        "   cmp     r2, r3                              \n"
        "   bne     reent_panic2                        \n"

        /* Set NS_VEC_DESC_BIT in ctrl_param to mark vectors as NS */
        "   ldr     r3, =%[ns_vec_bit]                  \n"
        "   orr     r1, r1, r3                          \n"

        /* Restore in_vec and out_vec */
        "   pop     {r2, r3}                            \n"

        /* Save registers and call actual implementation */
        "   push    {r4, lr}                            \n"
        "   bl      tfm_psa_call_pack                   \n"  // Actual PSA call
        "   pop     {r1, r2}                            \n"

        /* Clear caller context (FPU, APSR) */
        "   mov     lr, r2                              \n"
        "   bl      clear_caller_context                \n"

#if TFM_ISOLATION_LEVEL == 3
        /* Clear BASEPRI to re-enable NS interrupts */
        "   movs    r2, #0                              \n"
        "   msr     basepri, r2                         \n"
#endif

        /* Return to NS */
        "   bxns    lr                                  \n"

        "reent_panic2:                                  \n"
        "   b       reent_panic2                        \n"

        : : [basepri] "I" (BASEPRI_DISABLE_IRQ),
            [ns_vec_bit] "I" (PARAM_PACK_NS_VEC_DESC_BIT)
    );
}
```

**clear_caller_context()** (Lines 86-121):
```assembly
__attribute__((naked))
static void clear_caller_context(void)
{
    __ASM volatile(
        "   .syntax unified                             \n"

#if CONFIG_TFM_ENABLE_CP10CP11
        /* Clear FPU registers to prevent info leakage */
        "   vmov    d0, r2, r3                          \n"
        "   vmov    d1, r2, r3                          \n"
        "   vmov    d2, r2, r3                          \n"
        "   vmov    d3, r2, r3                          \n"
        "   vmov    d4, r2, r3                          \n"
        "   vmov    d5, r2, r3                          \n"
        "   vmov    d6, r2, r3                          \n"
        "   vmov    d7, r2, r3                          \n"

        /* Clear FPSCR (FPU status/control) */
        "   mov     r2, #0                              \n"
        "   vmsr    fpscr, r2                           \n"
#else
        "   mov     r2, #0                              \n"
        "   mov     r3, #0                              \n"
#endif

        /* Clear APSR (Application PSR) */
        "   msr     apsr_nzcvq, r2                      \n"

        "   bx      lr                                  \n"
    );
}
```

**Other Veneer Functions**:
- `tfm_psa_framework_version_veneer()` (Line 123)
- `tfm_psa_version_veneer()` (Line 130)
- `tfm_psa_connect_veneer()` (Line 216)
- `tfm_psa_close_veneer()` (Line 252)

All follow same security pattern:
1. Save parameters
2. Check stack seal
3. Set BASEPRI (mask NS interrupts)
4. Call implementation
5. Clear context
6. Clear BASEPRI
7. BXNS return to NS

---

## 7. SECURE WORLD PSA API PROCESSING

### SVC-Based Calls (Isolation Level > 1)

**File**: `secure_fw/spm/core/tfm_svcalls.c`

**SVC Handler for PSA APIs** (Lines 52-81):
```c
uint32_t tfm_svc_psa_call(psa_handle_t handle, uint32_t ctrl_param,
                          const psa_invec *in_vec, psa_outvec *out_vec)
{
    uint32_t exc_return;
    psa_status_t status;

    // 1. Switch to SPM boundary (Thread mode)
    exc_return = prepare_to_thread_mode_spm(ctx);

    // 2. Call actual PSA call implementation
    status = tfm_spm_client_psa_call(handle, ctrl_param, in_vec, out_vec);

    // 3. Return to caller partition
    return tfm_svc_thread_mode_spm_return(exc_return, status);
}
```

**prepare_to_thread_mode_spm()** (Lines 145-187):
```c
static uint32_t prepare_to_thread_mode_spm(uint32_t *ctx)
{
    struct partition_t *partition;
    uint32_t exc_return = ctx[7];  // Get EXC_RETURN from stack

    // 1. Get current partition
    partition = GET_CURRENT_COMPONENT();

    // 2. Check if boundary switch is needed
    if (tfm_hal_boundary_need_switch(&partition->boundary,
                                     &spm_boundary)) {
        // Switch MPU to SPM boundary
        tfm_hal_activate_boundary(&spm_boundary);
    }

    // 3. Switch stack if needed
    struct context_ctrl_t *p_ctx_ctrl = &partition->ctx_ctrl;

    if (backend_abi_entering_spm(p_ctx_ctrl, exc_return,
                                 &ctx[0], &ctx[4], &ctx[8])) {
        // Stack switch performed
    }

    // 4. Initialize SPM function context
    init_spm_func_context(ctx);

    // 5. Return modified EXC_RETURN for Thread mode
    return EXC_RETURN_THREAD_PSP;
}
```

**tfm_svc_thread_mode_spm_return()** (Lines 83-110):
```c
static uint32_t tfm_svc_thread_mode_spm_return(uint32_t exc_return,
                                               psa_status_t status)
{
    struct partition_t *partition = GET_CURRENT_COMPONENT();

    // 1. Restore partition boundary
    if (tfm_hal_boundary_need_switch(&spm_boundary,
                                     &partition->boundary)) {
        tfm_hal_activate_boundary(&partition->boundary);
    }

    // 2. Check if scheduling is needed
    uint32_t saved_exc_return = backend_abi_leaving_spm(exc_return);

    // 3. Set return value in context
    arch_set_context_return_value(saved_exc_return, status);

    // 4. Restore PSP and PSPLIM
    struct context_ctrl_t *p_ctx_ctrl = &partition->ctx_ctrl;
    arch_set_psplim(p_ctx_ctrl->sp_limit);
    __set_PSP((uint32_t)p_ctx_ctrl->sp);

    return saved_exc_return;
}
```

### Backend ABI Functions

**File**: `secure_fw/spm/core/backend_ipc.c`

**backend_abi_entering_spm()** (Lines 470-499):
```c
bool backend_abi_entering_spm(struct context_ctrl_t *p_ctx_ctrl,
                             uint32_t exc_return,
                             uint32_t *p_spm_sp_base,
                             uint32_t *p_spm_sp_limit,
                             uint32_t *p_curr_sp)
{
    struct partition_t *partition = TO_CONTAINER(p_ctx_ctrl,
                                                 struct partition_t,
                                                 ctx_ctrl);

    // 1. Check if stack switch is needed
    bool stack_switch = (partition->thrd.state != THRD_STATE_RET_TO_PSA_API);

    if (stack_switch) {
        // 2. Return SPM stack info
        *p_spm_sp_base  = (uint32_t)SPM_THREAD_CONTEXT->sp_base;
        *p_spm_sp_limit = (uint32_t)SPM_THREAD_CONTEXT->sp_limit;
        *p_curr_sp      = (uint32_t)p_ctx_ctrl->sp;
    }

    // 3. Acquire scheduler lock
    UNI_LIST_INIT_NODE(partition, p_handles);

    return stack_switch;
}
```

**backend_abi_leaving_spm()** (Lines 501-517):
```c
uint32_t backend_abi_leaving_spm(uint32_t exc_return)
{
    struct partition_t *partition = GET_CURRENT_COMPONENT();

    // 1. Handle any programming errors
    if (partition->p_handles) {
        tfm_core_panic();
    }

    // 2. Release scheduler lock
    thrd_exit_state_switch(&partition->thrd, THRD_STATE_BLOCK);

    // 3. Trigger scheduling if needed
    if (THRD_EXPECTING_SCHEDULE()) {
        arch_request_schedule();  // Set PendSV
    }

    return exc_return;
}
```

---

## 8. CONTEXT SWITCHING - PendSV Handler

### PendSV Exception

**File**: `secure_fw/spm/core/arch/tfm_arch_v8m_main.c`

**PendSV_Handler()** (Lines 99-154):
```assembly
__attribute__((naked)) void PendSV_Handler(void)
{
    __ASM volatile(
        "   .syntax unified                             \n"

        /* Check if NS was interrupted */
        "   mrs     r0, psp                             \n"
        "   mov     lr, r0                              \n"  // exc_return in lr
        "   bl      ipc_schedule                        \n"  // Get contexts

        /* ipc_schedule returns (curr_ctx, next_ctx) in r0, r1 */

        /* Check if context switch is needed */
        "   cmp     r0, r1                              \n"
        "   beq     v8m_pendsv_exit                     \n"  // Same thread

        /* ========== SAVE CURRENT CONTEXT ========== */

#if CONFIG_TFM_ENABLE_CP10CP11
        /* Save FPU registers s16-s31 */
        "   vstmdb  r0!, {s16-s31}                      \n"
#endif

        /* Save callee-saved registers r4-r11 */
        "   stmdb   r0!, {r4-r11}                       \n"

        /* Save PSP and LR to current context */
        "   mov     r4, lr                              \n"
        "   mrs     r5, psp                             \n"
        "   stmdb   r0!, {r4, r5}                       \n"

        /* ========== RESTORE NEXT CONTEXT ========== */

        /* Load PSP and LR from next context */
        "   ldmia   r1!, {r4, r5}                       \n"
        "   mov     lr, r4                              \n"
        "   msr     psp, r5                             \n"

        /* Restore callee-saved registers */
        "   ldmia   r1!, {r4-r11}                       \n"

#if CONFIG_TFM_ENABLE_CP10CP11
        /* Restore FPU registers */
        "   vldmia  r1!, {s16-s31}                      \n"
#endif

        /* ========== UPDATE STACK POINTERS ========== */

        /* Set PSPLIM for new thread */
        "   ldr     r0, [r1]                            \n"  // Load sp_limit
        "   msr     psplim, r0                          \n"

        /* Enable interrupts */
        "   cpsie   i                                   \n"

        "v8m_pendsv_exit:                               \n"
        "   bx      lr                                  \n"  // Return
    );
}
```

### Scheduler

**File**: `secure_fw/spm/core/backend_ipc.c`

**ipc_schedule()** (Lines 519-646):
```c
void ipc_schedule(uint32_t exc_return,
                 struct context_ctrl_t **pp_curr_ctx,
                 struct context_ctrl_t **pp_next_ctx)
{
    struct partition_t *p_curr, *p_next;
    struct context_ctrl_t *p_curr_ctx, *p_next_ctx;

    // 1. Get current thread
    p_curr = GET_CURRENT_COMPONENT();

    // 2. Update current thread's SP from PSP
    p_curr_ctx = &p_curr->ctx_ctrl;
    p_curr_ctx->sp = (uint32_t)__get_PSP();

    // 3. Get next thread to run
    p_next = (struct partition_t *)thrd_next();

    // 4. Check if context switch is needed
    if (p_curr == p_next) {
        *pp_curr_ctx = p_curr_ctx;
        *pp_next_ctx = p_curr_ctx;
        return;  // No switch
    }

    // 5. Check if boundary switch is needed
    p_next_ctx = &p_next->ctx_ctrl;

    if (tfm_hal_boundary_need_switch(&p_curr_ctx->boundary,
                                     &p_next_ctx->boundary)) {
        // Switch MPU boundary
        tfm_hal_activate_boundary(&p_next_ctx->boundary);
    }

    // 6. Update current thread
    CURRENT_THREAD = &p_next->thrd;

    // 7. Return contexts for assembly to switch
    *pp_curr_ctx = p_curr_ctx;
    *pp_next_ctx = p_next_ctx;
}
```

---

## 9. ARCHITECTURE-SPECIFIC CONFIGURATION

### Exception Priorities

**File**: `secure_fw/spm/core/arch/tfm_arch_v8m_main.c`

**tfm_arch_set_secure_exception_priorities()** (Lines 225-250):
```c
void tfm_arch_set_secure_exception_priorities(void)
{
    // 1. Enable AIRCR.PRIS to prioritize secure exceptions
    SCB->AIRCR = (0x05FA << SCB_AIRCR_VECTKEY_Pos) |
                 SCB_AIRCR_PRIS_Msk |
                 (SCB->AIRCR & 0xFFFF);

    // 2. Set fault priorities < 0x80 (higher than NS max)
    NVIC_SetPriority(SecureFault_IRQn, 0x00);   // Highest
    NVIC_SetPriority(MemoryManagement_IRQn, 0x00);
    NVIC_SetPriority(BusFault_IRQn, 0x00);
    NVIC_SetPriority(SVCall_IRQn, 0x00);

    // 3. Set PendSV to lowest priority (0xFF) for scheduling
    NVIC_SetPriority(PendSV_IRQn, 0xFF);
}
```

### FPU Configuration

**tfm_arch_config_extensions()** (Lines 288-376):
```c
void tfm_arch_config_extensions(uintptr_t *p_spm_boundary)
{
#if CONFIG_TFM_ENABLE_CP10CP11
    // 1. Enable FPU for Secure and Non-Secure
    SCB->CPACR |= (0x3U << 20U) | (0x3U << 22U);  // CP10, CP11 Full Access
    SCB->NSACR |= SCB_NSACR_CP10_Msk | SCB_NSACR_CP11_Msk;

    // 2. Configure lazy stacking
#if CONFIG_TFM_LAZY_STACKING_SPE
    FPU->FPCCR |= FPU_FPCCR_LSPEN_Msk;   // Enable lazy stacking
#else
    FPU->FPCCR &= ~FPU_FPCCR_LSPEN_Msk;  // Disable lazy stacking
#endif

    // 3. Set FPU security attributes
    FPU->FPCCR |= FPU_FPCCR_TS_Msk;          // Treat FP regs as Secure
    FPU->FPCCR |= FPU_FPCCR_CLRONRETS_Msk;   // Clear on return to S
    FPU->FPCCR |= FPU_FPCCR_CLRONRET_Msk;    // Clear on exception return
    FPU->FPCCR |= FPU_FPCCR_LSPENS_Msk;      // Lazy stacking for S

    // 4. Prevent NS from disabling FPU power
    FPU->FPCCR &= ~FPU_FPCCR_ASPEN_Msk;
#endif

#if defined(__ARM_ARCH_8_1M_MAIN__)
    // Enable Data Independent Timing (DIT) on ARMv8.1-M
    __set_CONTROL(__get_CONTROL() | CONTROL_DIT_Msk);
#endif
}
```

---

## COMPLETE EXECUTION FLOW DIAGRAM

```
┌────────────────────────────────────────────────────────────┐
│                    HARDWARE RESET                          │
└────────────────────┬───────────────────────────────────────┘
                     │
                     ↓
┌────────────────────────────────────────────────────────────┐
│  Reset_Handler (startup_ra6m4.c:149)                       │
│    • Set PSP, MSPLIM, PSPLIM                               │
│    • Stack seal (0xFEF5EDA5)                               │
│    • SystemInit()                                          │
│    • __PROGRAM_START() → main()                            │
└────────────────────┬───────────────────────────────────────┘
                     │
                     ↓
┌────────────────────────────────────────────────────────────┐
│  main() (secure_fw/spm/core/main.c:95)                     │
│    1. tfm_arch_config_branch_protection()                  │
│    2. tfm_arch_set_msplim()                                │
│    3. fih_delay_init()                                     │
│    4. tfm_core_init() ──────────────────┐                  │
└────────────────────┬────────────────────┴──────────────────┘
                     │                    │
                     │                    ↓
                     │      ┌─────────────────────────────────┐
                     │      │  tfm_core_init()                │
                     │      │    • tfm_hal_set_up_static_     │
                     │      │      boundaries() [MPU]         │
                     │      │    • tfm_hal_platform_init()    │
                     │      │    • R_BSP_SecurityInit() [SAU] │
                     │      │    • tfm_plat_otp_init()        │
                     │      │    • tfm_arch_config_extensions│
                     │      │      () [FPU/MVE]               │
                     │      └─────────────────────────────────┘
                     │
                     ↓
┌────────────────────────────────────────────────────────────┐
│    5. tfm_arch_set_secure_exception_priorities()           │
│       • AIRCR.PRIS = 1                                     │
│       • Faults < 0x80, PendSV = 0xFF                       │
└────────────────────┬───────────────────────────────────────┘
                     │
                     ↓
┌────────────────────────────────────────────────────────────┐
│    6. BACKEND_SPM_INIT() → SVC #TFM_SVC_SPM_INIT           │
└────────────────────┬───────────────────────────────────────┘
                     │
                     ↓
┌────────────────────────────────────────────────────────────┐
│  SVC_Handler → spm_svc_handler (tfm_svcalls.c:203)        │
│    • tfm_spm_init() ───────────────────┐                   │
└────────────────────┬────────────────────┴──────────────────┘
                     │                    │
                     │                    ↓
                     │      ┌─────────────────────────────────┐
                     │      │  tfm_spm_init() (spm_ipc.c:397) │
                     │      │  Loop for each partition:       │
                     │      │    • load_a_partition_assuredly│
                     │      │    • load_services_assuredly   │
                     │      │    • load_irqs_assuredly       │
                     │      │    • tfm_hal_bind_boundary()   │
                     │      │    • backend_init_comp_        │
                     │      │      assuredly()               │
                     │      │      ├→ partition_init() OR    │
                     │      │      └→ ns_agent_tz_init()     │
                     │      │    • thrd_start()              │
                     │      │                                │
                     │      │  backend_system_run() ────┐    │
                     │      └───────────────────────────┴────┘
                     │                                  │
                     │                                  ↓
                     │            ┌──────────────────────────┐
                     │            │  • thrd_start_scheduler()│
                     │            │  • tfm_hal_activate_     │
                     │            │    boundary()            │
                     │            │  • arch_clean_stack_and_ │
                     │            │    launch()              │
                     │            └──────────────────────────┘
                     │
                     ↓
┌────────────────────────────────────────────────────────────┐
│  ns_agent_tz_main() (ns_agent_tz_v80m.c:17)               │
│    • Check stack seal                                      │
│    • Clear NS bit from entry address                       │
│    • Clear FPU registers (d0-d7)                           │
│    • Clear general registers (r0-r12, r14)                 │
│    • BXNS to NS entry point ──────────────────┐            │
└───────────────────────────────────────────────┴────────────┘
                                                │
                                                ↓
                    ┌───────────────────────────────────────┐
                    │    NON-SECURE WORLD RUNNING           │
                    │  • FreeRTOS scheduler active          │
                    │  • Application tasks executing        │
                    └───────────────────┬───────────────────┘
                                        │
                                        │ NS app calls
                                        │ psa_call()
                                        ↓
                    ┌───────────────────────────────────────┐
                    │  tfm_psa_call_veneer() [SG]           │
                    │  (psa_api_veneers_v80m.c:146)         │
                    │    • Save in_vec, out_vec             │
                    │    • Set BASEPRI (mask NS IRQ)        │
                    │    • Check stack seal                 │
                    │    • Set NS_VEC_DESC_BIT              │
                    │    • tfm_psa_call_pack() ────┐        │
                    └──────────────────────────────┴────────┘
                                                   │
                                                   ↓
                    ┌────────────────────────────────────────┐
                    │  PSA API Processing (tfm_svcalls.c)    │
                    │    • prepare_to_thread_mode_spm()      │
                    │      ├→ tfm_hal_activate_boundary()    │
                    │      └→ backend_abi_entering_spm()     │
                    │    • tfm_spm_client_psa_call()         │
                    │      ├→ backend_messaging()            │
                    │      ├→ backend_assert_signal()        │
                    │      └→ Set PendSV for scheduling      │
                    │    • tfm_svc_thread_mode_spm_return()  │
                    │      └→ backend_abi_leaving_spm()      │
                    └──────────────────┬─────────────────────┘
                                       │
                                       ↓ PendSV set
                    ┌────────────────────────────────────────┐
                    │  PendSV_Handler (tfm_arch_v8m_main.c) │
                    │    • ipc_schedule() ────────┐          │
                    │      ├→ thrd_next()         │          │
                    │      ├→ tfm_hal_activate_   │          │
                    │      │   boundary() [MPU]   │          │
                    │      └→ Update CURRENT_     │          │
                    │         THREAD              │          │
                    │                             │          │
                    │    • Save current context   │          │
                    │      ├→ FPU s16-s31         │          │
                    │      ├→ r4-r11              │          │
                    │      └→ PSP, LR             │          │
                    │                             │          │
                    │    • Restore next context   │          │
                    │      ├→ PSP, LR             │          │
                    │      ├→ r4-r11              │          │
                    │      ├→ FPU s16-s31         │          │
                    │      └→ PSPLIM              │          │
                    │                             │          │
                    │    • BX lr (return)         │          │
                    └─────────────────────────────┴──────────┘
                                       │
                                       ↓
                    ┌────────────────────────────────────────┐
                    │  Secure Partition Thread               │
                    │    • psa_wait(signals)                 │
                    │    • psa_get(msg_handle)               │
                    │    • psa_read()/psa_write()            │
                    │    • [Process request]                 │
                    │    • psa_reply(handle, status)         │
                    │      └→ Schedule back to caller        │
                    └────────────────────────────────────────┘
                                       │
                                       ↓
                    ┌────────────────────────────────────────┐
                    │  Return to NS                          │
                    │    • clear_caller_context()            │
                    │      ├→ Clear FPU d0-d7                │
                    │      └→ Clear APSR                     │
                    │    • Clear BASEPRI                     │
                    │    • BXNS lr                           │
                    └────────────────────────────────────────┘
                                       │
                                       ↓
                    ┌────────────────────────────────────────┐
                    │  Back to NS Application                │
                    │    • psa_call() returns                │
                    │    • FreeRTOS continues                │
                    └────────────────────────────────────────┘
```

---

## KEY SECURITY MECHANISMS

### 1. Stack Seal Pattern
- **Value**: `0xFEF5EDA5`
- **Location**: Top of secure stack
- **Purpose**: Detect reentrancy attacks
- **Check**: Before every NS→S transition

### 2. BASEPRI Masking (Isolation Level 3)
- **Set**: On veneer entry
- **Value**: `BASEPRI_DISABLE_IRQ`
- **Purpose**: Prevent NS interrupt preemption during S execution
- **Clear**: On veneer exit

### 3. NS_VEC_DESC_BIT
- **Set**: In `ctrl_param` of PSA calls
- **Purpose**: Mark `in_vec`/`out_vec` as NS pointers
- **Validation**: SPM validates NS memory access

### 4. Register Clearing
- **FPU**: d0-d7 cleared on world transitions
- **GPR**: r0-r12, r14 cleared when entering NS
- **APSR**: Cleared when returning to NS
- **Purpose**: Prevent information leakage

### 5. MPU/SAU Boundaries
- **MPU**: Code/data isolation between partitions
- **SAU**: Secure/Non-Secure memory attribution
- **Dynamic**: Switched on context switch via `tfm_hal_activate_boundary()`

---

## FILE REFERENCE SUMMARY

| Component | File | Key Functions |
|-----------|------|---------------|
| **Boot** | `platform/.../startup_ra6m4.c` | Reset_Handler, Vector Table |
| **Main** | `secure_fw/spm/core/main.c` | main, tfm_core_init |
| **HAL Isolation** | `platform/.../tfm_hal_isolation.c` | tfm_hal_set_up_static_boundaries |
| **HAL Platform** | `platform/.../tfm_hal_platform.c` | tfm_hal_get_ns_entry_point |
| **SAU/TZ** | `platform/.../fsp/.../bsp_security.c` | R_BSP_SecurityInit |
| **SPM Init** | `secure_fw/spm/core/spm_ipc.c` | tfm_spm_init, backend_system_run |
| **SVC Handler** | `secure_fw/spm/core/tfm_svcalls.c` | spm_svc_handler |
| **Backend** | `secure_fw/spm/core/backend_ipc.c` | backend_init_comp_assuredly, ipc_schedule |
| **NS Agent** | `secure_fw/partitions/ns_agent_tz/ns_agent_tz_v80m.c` | ns_agent_tz_main |
| **Veneers** | `secure_fw/partitions/ns_agent_tz/psa_api_veneers_v80m.c` | tfm_psa_*_veneer |
| **Architecture** | `secure_fw/spm/core/arch/tfm_arch_v8m_main.c` | PendSV_Handler, SVC_Handler |
| **Target Config** | `platform/.../target_cfg.c` | sau_and_idau_cfg |

---

This complete trace shows every step from hardware reset through secure world initialization, partition loading, NS transition, and service invocation with full security mechanisms.
