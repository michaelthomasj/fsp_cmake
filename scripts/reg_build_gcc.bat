@echo off
rem  Regression suites (tf-m-tests tests_reg), GNUARM. RA6M5 by default.
rem
rem    reg_build_gcc.bat <spe-build-dir> <ns-build-dir> [part] [irq] [level] [backend]
rem    reg_build_gcc.bat C:\b\m5gflih  C:\b\m5gflihns  ra6m5 flih 1 SFN
rem    reg_build_gcc.bat C:\b\m5gl2    C:\b\m5gl2ns    ra6m5 flih 2 SFN
rem    reg_build_gcc.bat C:\b\m5gl3    C:\b\m5gl3ns    ra6m5 flih 3 IPC
rem
rem  This script did not exist until 2026-10-13 - the GNUARM regression chain had only ever
rem  been configured by hand, and the configuration lived nowhere but C:\b\m5gflih's cache.
rem  The defaults below are that cache, verbatim, so a rebuilt tree reproduces the runs the
rem  decision log cites. DECISIONS D084 is the lesson being applied.
rem
rem  ISOLATION LEVEL AND BACKEND are the last two arguments, defaulting to the shipping
rem  configuration (1 / SFN). They exist because the regression suite had NEVER been run above
rem  isolation 1 - every tests_reg build in C:\b is L1/SFN, and every L3 build is PSA Arch,
rem  which is a different test body. Two things therefore had no coverage at all:
rem
rem    - isolation 2, which has never been built or run on this port (DECISIONS D015)
rem    - the MMIO MPU-region path. tests_reg is the ONLY test body that declares mmio_region
rem      (tfm_secure_client_service, tfm_flih_test_service, tfm_slih_test_service), and at
rem      L1 no MPU region is created from a declaration. So the code that programs peripheral
rem      regions - tfm_hal_isolation_v8m.c:496 at L2, :664 at L3 - has never executed here.
rem      That is how RA8M2's tfm_peripheral_std_uart carried RA6M5's SCI0 base for the life
rem      of the port without anything noticing.
rem
rem  THE BACKEND IS NOT INDEPENDENT OF THE LEVEL, and getting this wrong produces a confusing
rem  failure rather than a clean one. config/set_config.cmake:35 reads:
rem
rem      if((DEFINED TFM_ISOLATION_LEVEL AND TFM_ISOLATION_LEVEL GREATER 1) OR
rem         (CONFIG_TFM_SPM_BACKEND STREQUAL "IPC") OR ...)
rem          include(config/tfm_ipc_config_default.cmake)
rem
rem  so isolation 2 or 3 sets CONFIG_TFM_SPM_BACKEND_IPC=ON on its own, whatever string was
rem  passed for CONFIG_TFM_SPM_BACKEND. Pass level 2 with SFN and the two halves disagree:
rem  tests_reg sees CONFIG_TFM_SPM_BACKEND_IPC and turns on TEST_S_IPC / TEST_NS_IPC
rem  (tests_reg/test/config/config.cmake:88-95), which pull in TFM_SP_IPC_SERVICE_TEST and
rem  TFM_SP_IPC_CLIENT_TEST, and then the manifest tool rejects them against the SFN string:
rem
rem      SFN backend does not support IPC Partitions:
rem      ['TFM_SP_IPC_SERVICE_TEST', 'TFM_SP_IPC_CLIENT_TEST']
rem      CMake Error at tools/CMakeLists.txt:188: Manifest tool failed to generate files!
rem
rem  set_config.cmake's own comment anticipates this - "if a pair of invalid settings are
rem  passed via command line, it will be captured later via config check" - but the thing that
rem  catches it is the manifest generator, not check_config.cmake, so the message names test
rem  partitions and says nothing about the isolation level that enabled them.
rem
rem  This script therefore FORCES IPC above level 1 rather than letting you pass the broken
rem  pair. Everything else really is automatic: platform/CMakeLists.txt:125 defines
rem  CONFIG_TFM_ENABLE_MEMORY_PROTECT for TFM_ISOLATION_LEVEL > 1, the two configs that would
rem  block it are already off here (PSA_FRAMEWORK_HAS_MM_IOVEC, CONFIG_TFM_STACK_WATERMARKS),
rem  and PLATFORM_HAS_ISOLATION_L3_SUPPORT is ON for both parts.
rem
rem  Note the IPC backend is larger than SFN, which eats into the slot headroom discussed
rem  below - the level is not the only thing that grew when you raised it.
rem
rem  EXPECTED REGION COUNT on a Cortex-M33 (PXN needs armv8.1-m.main, so M33 always takes the
rem  combined-code branch):
rem      L2   5 static + 1 per MMIO region per ARoT partition, allocated permanently
rem      L3   5 static + 1 private data + the MMIO regions of the partition being scheduled
rem  tests_reg contributes one ARoT MMIO region via the FLIH or SLIH service - the secure
rem  client service is PSA-RoT, so its MMIO costs nothing (the L2 path guards on !privileged).
rem  So L2 should land on 6 and L3 on 7 of the 8 regions. tfm_hal_platform.c logs what the
rem  hardware actually reports; read it rather than trusting this comment.
rem
rem  RA8M2 WILL NOT FIT and the script does not stop you trying. tfm_s is 293,564 B against a
rem  294,400 B slot - 670 B spare after the imgtool TLVs (DECISIONS D057, corrected by D087) -
rem  at MinSizeRel / isolation 1 / SFN. Isolation 3 cost +972 B of secure text on RA6E1
rem  (DECISIONS D008), and the IPC backend is larger than SFN. Expect the signing step to
rem  fail, or the link. Growing the slot is a layout revision, not a tweak. Use ra6m5, which
rem  has 1,693 B spare.
rem
rem  IRQ ARGUMENT. FLIH and SLIH are mutually exclusive in tf-m-tests: enabling both fails
rem  configure. 'flih' (the default) sets TEST_NS_FLIH_IRQ, 'slih' sets TEST_NS_SLIH_IRQ,
rem  'none' sets neither. They need a secure timer, which on RA is r_agt WITH a real Interrupt
rem  Priority - Disabled emits no vector entry at all. DECISIONS D061, D101.
rem
rem  MinSizeRel IS NOT OPTIONAL. Debug does not fit on GNUARM on either part: ~414 KB against
rem  a 293 KB secure region. DECISIONS D055, D056.
rem
rem  TFM_SPM_LOG_LEVEL is set because TFM_SPM_DEBUG_TRACE is ON in both platform configs and
rem  leaving the level at its MinSizeRel default stops configure with "INVALID CONFIG:
rem  TFM_SPM_DEBUG_TRACE AND TFM_SPM_LOG_LEVEL = ..._SILENCE". It is also what makes the MPU
rem  inventory in tfm_hal_platform.c visible - SPMLOG_INFMSGVAL compiles to nothing below it.
rem
rem  Build directories must be SHORT, under C:\b - a deep path makes the Mbed TLS overlay
rem  clone fail with "Filename too long" on 3rdparty/everest/...
rem
rem  Quote %GCC_BIN% in every test. The default path contains "(x86)" and an unquoted
rem  "if not exist %GCC_BIN%\..." closes the block at the first paren - the body is then
rem  skipped and the script exits 0 having done nothing. DECISIONS D057.

if "%GCC_BIN%"==""    set GCC_BIN=C:\Program Files (x86)\Arm GNU Toolchain arm-none-eabi\13.2 Rel1\bin
if "%TFM_SRC%"==""    set TFM_SRC=C:\Users\Michael\Documents\GitHub\trusted-firmware-m
if "%TFM_TESTS%"==""  set TFM_TESTS=C:\Users\Michael\Documents\GitHub\tf-m-tests
if "%FSP_CMAKE%"==""  set FSP_CMAKE=C:/Users/Michael/Documents/GitHub/fsp_cmake

set PATH=%GCC_BIN%;%PATH%
set TFM_SRC_FWD=%TFM_SRC:\=/%
set GCC_BIN_FWD=%GCC_BIN:\=/%

set SPE=%1
set NS=%2
set PART=%3
set IRQ=%4
set LEVEL=%5
set BACKEND=%6
if "%PART%"==""    set PART=ra6m5
if "%IRQ%"==""     set IRQ=flih
if "%LEVEL%"==""   set LEVEL=1
if "%BACKEND%"=="" set BACKEND=SFN

rem  Above isolation 1 the backend is not a free choice - see the header. Force it rather than
rem  letting set_config.cmake and the manifest tool disagree 90 seconds into a configure.
if not "%LEVEL%"=="1" (
  if /i not "%BACKEND%"=="IPC" (
    echo [reg_build_gcc] isolation %LEVEL% implies the IPC backend ^(set_config.cmake:35^); overriding %BACKEND% -^> IPC
    set BACKEND=IPC
  )
)

rem  Per-part project directory prefix. Mirrors reg_build_iar.bat - keep them in step.
if /i "%PART%"=="ra8m2" (
  set S_DIR=ra8m2_gcc_CPU0_secure
  set BL_DIR=ra8m2_gcc_mcuboot
  set NS_DIR=ra8m2_gcc_CPU0_nonsecure
) else (
  set S_DIR=ra6m5_gcc_secure
  set BL_DIR=ra6m5_gcc_mcuboot
  set NS_DIR=ra6m5_gcc_nonsecure
)

set IRQ_ARGS=
if /i "%IRQ%"=="flih" set IRQ_ARGS=-DTEST_NS_FLIH_IRQ=ON
if /i "%IRQ%"=="slih" set IRQ_ARGS=-DTEST_NS_SLIH_IRQ=ON

if "%SPE%"=="" echo usage: %~nx0 ^<spe-build-dir^> ^<ns-build-dir^> [part] [flih^|slih^|none] [level] [SFN^|IPC] & exit /b 2
if "%NS%"==""  echo usage: %~nx0 ^<spe-build-dir^> ^<ns-build-dir^> [part] [flih^|slih^|none] [level] [SFN^|IPC] & exit /b 2

echo [reg_build_gcc] part=%PART% irq=%IRQ% isolation=%LEVEL% backend=%BACKEND%

if not exist "%SPE%\CMakeCache.txt" (
  cmake -S %TFM_TESTS%\tests_reg\spe -B %SPE% -GNinja ^
    -DCMAKE_BUILD_TYPE=MinSizeRel ^
    -DCMAKE_C_COMPILER="%GCC_BIN_FWD%/arm-none-eabi-gcc.exe" ^
    -DCONFIG_TFM_SOURCE_PATH=%TFM_SRC_FWD% ^
    -DTFM_TOOLCHAIN_FILE=%TFM_SRC_FWD%/toolchain_GNUARM.cmake ^
    -DTFM_PLATFORM=renesas/%PART% ^
    -DFSP_S_APP_DIR=%FSP_CMAKE%/%S_DIR% ^
    -DFSP_BL2_APP_DIR=%FSP_CMAKE%/%BL_DIR% ^
    -DFSP_NS_APP_DIR=%FSP_CMAKE%/%NS_DIR% ^
    -DTEST_S=ON ^
    -DTEST_NS=ON ^
    %IRQ_ARGS% ^
    -DTFM_ISOLATION_LEVEL=%LEVEL% ^
    -DCONFIG_TFM_SPM_BACKEND=%BACKEND% ^
    -DMCUBOOT_LOG_LEVEL=INFO ^
    -DTFM_SPM_LOG_LEVEL=TFM_SPM_LOG_LEVEL_DEBUG
  if errorlevel 1 exit /b 1
)
rem  'install' produces api_ns\, which the NS build consumes. It also runs the OFS brick guard
rem  on bl2 and tfm_s - read its output, do not just check the exit code.
cmake --build %SPE% -- install
if errorlevel 1 exit /b 1

if not exist "%NS%\CMakeCache.txt" (
  cmake -S %TFM_TESTS%\tests_reg -B %NS% -GNinja ^
    -DCONFIG_SPE_PATH=%SPE:\=/%/api_ns ^
    -DTFM_TOOLCHAIN_FILE=%SPE:\=/%/api_ns/cmake/toolchain_ns_GNUARM.cmake ^
    %IRQ_ARGS%
  if errorlevel 1 exit /b 1
)
cmake --build %NS%
exit /b %ERRORLEVEL%
