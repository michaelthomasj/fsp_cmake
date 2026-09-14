# TrustZone + FreeRTOS Requirements

## Issue Summary

The non-secure project (`FSP_Project_ra6m4_ns`) with FreeRTOS **fails to link** with undefined TrustZone context management functions:

```
undefined reference to `TZ_StoreContext_S'
undefined reference to `TZ_LoadContext_S'
undefined reference to `TZ_AllocModuleContext_S'
undefined reference to `TZ_InitContextSystem_S'
undefined reference to `TZ_FreeModuleContext_S'
```

## Root Cause

**FreeRTOS in the non-secure world requires TrustZone context switching support from the secure world.**

When FreeRTOS runs in the non-secure world (RA6M4 TrustZone configuration), the Renesas FSP FreeRTOS port (`rm_freertos_port/port.c`) calls TrustZone context management functions during task switching to:
1. Save/restore secure context when switching tasks
2. Allocate/free secure memory for task contexts
3. Initialize the secure context management system

These functions MUST be implemented in the **secure project** and exported via NSC (Non-Secure Callable) veneers in the SmartBundle.

## Current Status

### Secure Project (`FSP_Project_ra6m4_s`)
- ✅ Built successfully
- ✅ Generates SmartBundle (FSP_Project_ra6m4_s.sbd)
- ❌ **Does NOT include FreeRTOS TrustZone context functions**
- Current SmartBundle only contains: `template_nonsecure_callable` (empty template)

### Non-Secure Project (`FSP_Project_ra6m4_ns`)
- ✅ Modular build system working
- ✅ All FSP modules compile (BSP, ADC, ICU, FreeRTOS)
- ✅ SmartBundle dependency tracking configured
- ✅ RASC extracts secure.o automatically
- ❌ **Linker fails - secure.o missing required TZ functions**

## Solutions

### Option 1: Add FreeRTOS to Secure Project (Recommended for Production)

**Pros**:
- Full TrustZone + FreeRTOS support
- Secure tasks can run alongside non-secure tasks
- Proper context isolation between worlds
- Production-ready configuration

**Cons**:
- More complex secure project
- Higher secure world memory usage
- Requires FreeRTOS configuration in both worlds

**Steps**:
1. Open `FSP_Project_ra6m4_s` in RASC
2. Add FreeRTOS module to secure project
3. Configure FreeRTOS with TrustZone support enabled
4. Add at least one secure thread (can be minimal/idle)
5. Regenerate project with RASC
6. Rebuild secure project → generates SmartBundle with TZ functions
7. Rebuild non-secure project → should link successfully

### Option 2: Add Standalone TZ Context Module to Secure Project

**Pros**:
- Lightweight - no FreeRTOS overhead in secure world
- Simpler secure project
- Lower secure memory footprint
- Suitable for applications that only need FreeRTOS in non-secure world

**Cons**:
- Requires manual implementation or finding reference code
- Less common configuration
- May need custom RASC configuration

**Required Implementation**:

Create `tz_context.c` in secure project with these NSC functions:

```c
#include "tz_context.h"
#include <string.h>

// TrustZone context management for non-secure FreeRTOS
// This is a minimal implementation - adjust memory sizing as needed

#define TZ_CONTEXT_MAX_MODULES  8
#define TZ_CONTEXT_STACK_SIZE   256

typedef struct {
    uint32_t sp_limit;
    uint32_t sp;
    uint8_t  stack[TZ_CONTEXT_STACK_SIZE];
} TZ_ContextInfo_t;

static TZ_ContextInfo_t tz_contexts[TZ_CONTEXT_MAX_MODULES];
static uint32_t tz_context_initialized = 0;

__attribute__((cmse_nonsecure_entry))
uint32_t TZ_InitContextSystem_S(void) {
    if (tz_context_initialized) {
        return 1;
    }

    memset(tz_contexts, 0, sizeof(tz_contexts));
    tz_context_initialized = 1;
    return 1;
}

__attribute__((cmse_nonsecure_entry))
TZ_MemoryId_t TZ_AllocModuleContext_S(TZ_ModuleId_t module) {
    if (!tz_context_initialized || module >= TZ_CONTEXT_MAX_MODULES) {
        return 0;
    }

    TZ_ContextInfo_t *ctx = &tz_contexts[module];
    ctx->sp_limit = (uint32_t)ctx->stack;
    ctx->sp = (uint32_t)(ctx->stack + TZ_CONTEXT_STACK_SIZE);

    return module + 1;
}

__attribute__((cmse_nonsecure_entry))
uint32_t TZ_FreeModuleContext_S(TZ_MemoryId_t id) {
    if (!tz_context_initialized || id == 0 || id > TZ_CONTEXT_MAX_MODULES) {
        return 0;
    }

    TZ_ContextInfo_t *ctx = &tz_contexts[id - 1];
    memset(ctx, 0, sizeof(TZ_ContextInfo_t));

    return 1;
}

__attribute__((cmse_nonsecure_entry))
uint32_t TZ_LoadContext_S(TZ_MemoryId_t id) {
    if (!tz_context_initialized || id == 0 || id > TZ_CONTEXT_MAX_MODULES) {
        return 0;
    }

    // Implementation depends on what secure state needs to be restored
    // For minimal implementation with no secure tasks, this can be a no-op

    return 1;
}

__attribute__((cmse_nonsecure_entry))
uint32_t TZ_StoreContext_S(TZ_MemoryId_t id) {
    if (!tz_context_initialized || id == 0 || id > TZ_CONTEXT_MAX_MODULES) {
        return 0;
    }

    // Implementation depends on what secure state needs to be saved
    // For minimal implementation with no secure tasks, this can be a no-op

    return 1;
}
```

**Integration Steps**:
1. Add `tz_context.c` to secure project `src/` directory
2. Add to `CMakeLists.txt` application sources
3. Rebuild secure project → generates SmartBundle with TZ functions
4. Rebuild non-secure project → should link successfully

### Option 3: Remove FreeRTOS from Non-Secure Project

**Pros**:
- Simple - no TZ context requirements
- Secure project can remain simple
- Works with current setup

**Cons**:
- ❌ Defeats the purpose - user explicitly added FreeRTOS to non-secure project
- No RTOS capabilities in non-secure world
- Not a real solution

## CMSIS TrustZone Context API Reference

The required functions are defined in CMSIS:
- Header: `ra/arm/CMSIS_6/CMSIS/Core/Include/tz_context.h`
- Specification: [ARM CMSIS TrustZone Documentation](https://arm-software.github.io/CMSIS_6/latest/Core/group__trustzone__functions.html)

### Required Functions

| Function | Purpose |
|----------|---------|
| `TZ_InitContextSystem_S` | Initialize secure context memory system |
| `TZ_AllocModuleContext_S` | Allocate memory for module context |
| `TZ_FreeModuleContext_S` | Free allocated context memory |
| `TZ_LoadContext_S` | Load secure context when switching to task |
| `TZ_StoreContext_S` | Store secure context when switching from task |

All must be marked with `__attribute__((cmse_nonsecure_entry))` to create NSC veneers.

## Recommendation

For **development/testing**: Use Option 2 (standalone TZ context module) - simpler and faster.

For **production**: Use Option 1 (FreeRTOS in both worlds) - proper implementation with full support.

## Next Steps

1. **Decide** which option to implement based on project requirements
2. **Update** secure project with TZ context support
3. **Rebuild** secure project to generate updated SmartBundle
4. **Rebuild** non-secure project - should link successfully
5. **Test** TrustZone context switching with actual FreeRTOS tasks

## Related Files

### Secure Project
- `FSP_Project_ra6m4_s/` - Secure TrustZone project
- `FSP_Project_ra6m4_s/build/FSP_Project_ra6m4_s.sbd` - SmartBundle output

### Non-Secure Project
- `FSP_Project_ra6m4_ns/` - Non-secure project with FreeRTOS
- `FSP_Project_ra6m4_ns/cmake/modules/fsp_freertos.cmake` - FreeRTOS module requiring TZ functions
- `FSP_Project_ra6m4_ns/ra/fsp/src/rm_freertos_port/port.c:436` - Calls `TZ_StoreContext_S`
- `FSP_Project_ra6m4_ns/ra/fsp/src/rm_freertos_port/port.c:660` - Calls `TZ_LoadContext_S`
- `FSP_Project_ra6m4_ns/ra/fsp/src/rm_freertos_port/port.c:946` - Calls `TZ_AllocModuleContext_S`
- `FSP_Project_ra6m4_ns/ra/fsp/src/rm_freertos_port/port.c:970` - Calls `TZ_FreeModuleContext_S`
- `FSP_Project_ra6m4_ns/ra/fsp/src/rm_freertos_port/port.c:984` - Calls `TZ_InitContextSystem_S`

---

**Document Status**: Active Issue
**Created**: 2025-10-28
**Last Updated**: 2025-10-28
