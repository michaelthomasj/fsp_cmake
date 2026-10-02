@echo off
rem  RA6M5 PSA Arch SPE, IAR.
rem
rem    psa_arch_spe_iar.bat <build-dir> <TEST_PSA_API>
rem    psa_arch_spe_iar.bat C:\b\m5icry CRYPTO
rem
rem  Builds BL2 + the secure image and installs api_ns\ for the NS build to consume. One SPE
rem  serves all three suites - profile_large enables crypto, ITS, PS, attestation and platform,
rem  which is what they need - so the suite argument only affects the PSA_API_TEST_* defines.
rem
rem  Four things here that the GCC build does not need (DECISIONS D046):
rem    - IAR on PATH: toolchain_IARARM.cmake names "iccarm" with no path.
rem    - CMAKE_ASM_COMPILER_ARCHITECTURE_ID: CMake 4.1's IAR-ASM module cannot detect it, and
rem      fails on the RE-configure, after the first configure has already succeeded.
rem    - The outer wrapper needs CMAKE_C_COMPILER itself; it forces cross compilation and
rem      skips the compiler search.
rem    - TFM_SPM_DEBUG_TRACE=OFF: required at isolation 3 with the IPC backend.
rem
rem  Override any of the paths by setting the variable before calling.

if "%IAR_BIN%"==""    set IAR_BIN=C:\iar\ewarmc-10.10.2\arm\bin
if "%TFM_SRC%"==""    set TFM_SRC=C:/Users/Michael/Documents/GitHub/trusted-firmware-m
if "%TFM_TESTS%"==""  set TFM_TESTS=C:\Users\Michael\Documents\GitHub\tf-m-tests
if "%PSA_TESTS%"==""  set PSA_TESTS=C:/Users/Michael/Documents/GitHub/psa-arch-tests
if "%FSP_CMAKE%"==""  set FSP_CMAKE=C:/Users/Michael/Documents/GitHub/fsp_cmake

set PATH=%IAR_BIN%;%PATH%

set BUILD=%1
set SUITE=%2
if "%BUILD%"=="" echo usage: %~nx0 ^<build-dir^> ^<TEST_PSA_API^> & exit /b 2
if "%SUITE%"=="" echo usage: %~nx0 ^<build-dir^> ^<TEST_PSA_API^> & exit /b 2

rem  LOGGING IS ON DELIBERATELY in these four options, and they are stated here rather than
rem  left to the defaults so a fresh tree matches an old one. Until 2026-10-02 they existed
rem  only as hand-set cache entries in C:\b\m5cry, so a rebuilt-from-scratch SPE was quietly
rem  a different image - 3,785 B less secure text and 5,960 B less BL2 text. DECISIONS D084.
rem
rem  They cost space: see README.md "Freeing space in the secure image". The PSA Arch builds
rem  can afford it; the regression builds CANNOT - the secure slot has 1,984 B spare on RA6M5
rem  and 960 B on RA8M2, against 3,785 B for the secure-side logging alone. That is why this
rem  is set per-script and not in the platform config.cmake.

if not exist "%BUILD%\CMakeCache.txt" (
  cmake -S %TFM_TESTS%\tests_psa_arch\spe -B %BUILD% -GNinja ^
    -DCMAKE_C_COMPILER=%IAR_BIN:\=/%/iccarm.exe ^
    -DCMAKE_ASM_COMPILER_ARCHITECTURE_ID=ARM ^
    -DCONFIG_TFM_SOURCE_PATH=%TFM_SRC% ^
    -DTFM_TOOLCHAIN_FILE=%TFM_SRC%/toolchain_IARARM.cmake ^
    -DTFM_PLATFORM=renesas/ra6m5 ^
    -DFSP_S_APP_DIR=%FSP_CMAKE%/ra6m5_iar_secure ^
    -DFSP_BL2_APP_DIR=%FSP_CMAKE%/ra6m5_iar_mcuboot ^
    -DFSP_NS_APP_DIR=%FSP_CMAKE%/ra6m5_iar_nonsecure ^
    -DTEST_PSA_API=%SUITE% ^
    -DTFM_PROFILE=profile_large ^
    -DTFM_ISOLATION_LEVEL=3 ^
    -DCONFIG_TFM_SPM_BACKEND=IPC ^
    -DTFM_SPM_DEBUG_TRACE=OFF ^
    -DMCUBOOT_LOG_LEVEL=INFO ^
    -DTFM_SPM_LOG_LEVEL=TFM_SPM_LOG_LEVEL_DEBUG ^
    -DTFM_PARTITION_LOG_LEVEL=TFM_PARTITION_LOG_LEVEL_INFO ^
    -DCONFIG_TFM_HALT_ON_CORE_PANIC=ON ^
    -DRA6M5_RTT_BLOCKING=ON ^
    -DPSA_ARCH_TESTS_PATH=%PSA_TESTS% ^
    -DPSA_API_TEST_TARGET=renesas_ra
  if errorlevel 1 exit /b 1
)

cmake --build %BUILD% -- install
exit /b %ERRORLEVEL%
