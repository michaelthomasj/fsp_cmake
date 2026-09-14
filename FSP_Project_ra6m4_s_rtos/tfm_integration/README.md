# TF-M Integration for FSP Secure Project

This directory contains files for integrating the RASC-generated FSP secure project with TF-M (Trusted Firmware-M).

## Usage

When building TF-M, set `FSP_S_APP_DIR` to point to this project:

```bash
cmake -DTFM_PLATFORM=renesas/ra6m4 \
      -DFSP_S_APP_DIR=C:/path/to/FSP_Project_ra6m4_s_rtos \
      ...
```

## Files

- `bsp_init_stub.c` - Stub implementations for FSP BSP symbols that TF-M doesn't use
  (TF-M has its own startup code, so FSP's linker init structures are stubbed)

## How It Works

Unlike BL2 and NS projects which are separate executables, the secure project's FSP
sources are compiled into TF-M's `platform_s` library. The TF-M platform CMake files
(`fsp_bsp.cmake`, `fsp_uart.cmake`, `fsp_flash.cmake`) pull sources directly from
this RASC project when `FSP_S_APP_DIR` is set.

This allows you to:
1. Configure the secure project in RASC (pins, clocks, peripherals)
2. Generate code with RASC
3. Build TF-M which pulls the FSP sources from this project

## Modules Used by TF-M Secure Side

- BSP (Board Support Package) - Clock, GPIO, security configuration
- Flash HP - Required by TF-M for secure storage
- SCI UART - Console output

## Notes

- The secure project's linker script (`fsp_gen.ld`) is NOT used - TF-M generates its own
- The secure project's startup code is NOT used - TF-M has its own startup
- OFS (Option-Setting Flash) regions from this project are NOT used - use `FSP_BL2_APP_DIR` for OFS
