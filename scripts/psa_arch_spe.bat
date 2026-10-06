@echo off
rem  PSA Arch SPE, GCC. RA6M5 by default; pass a third argument for another part.
rem
rem    psa_arch_spe.bat <build-dir> <TEST_PSA_API>
rem    psa_arch_spe.bat C:\b\m5cry CRYPTO
rem
rem  Builds BL2 + the secure image and installs api_ns\ for the NS build to consume. One SPE
rem  serves all three suites - profile_large enables crypto, ITS, PS, attestation and platform,
rem  which is what they need - so the suite argument only affects the PSA_API_TEST_* defines.
rem
rem  The outer wrapper needs CMAKE_C_COMPILER itself: it forces cross compilation and skips the
rem  compiler search. TFM_SPM_DEBUG_TRACE=OFF is required at isolation 3 with the IPC backend.
rem
rem  Override any of the paths by setting the variable before calling.

if "%GCC_BIN%"==""    set GCC_BIN=C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin
if "%TFM_SRC%"==""    set TFM_SRC=C:/Users/Michael/Documents/GitHub/trusted-firmware-m
if "%TFM_TESTS%"==""  set TFM_TESTS=C:\Users\Michael\Documents\GitHub\tf-m-tests
if "%PSA_TESTS%"==""  set PSA_TESTS=C:/Users/Michael/Documents/GitHub/psa-arch-tests
if "%FSP_CMAKE%"==""  set FSP_CMAKE=C:/Users/Michael/Documents/GitHub/fsp_cmake

set BUILD=%1
set SUITE=%2
set PART=%3
if "%PART%"=="" set PART=ra6m5

rem  Per-part project directory prefix and the RTT option name. RA6M5's generated projects are
rem  ra6m5_gcc_{secure,mcuboot,nonsecure}; RA8M2's are ra8m2_gcc_{CPU0_secure,mcuboot,
rem  CPU0_nonsecure} because that part is dual-core and RASC names the partitions CPU0_*.
if /i "%PART%"=="ra8m2" (
  set S_DIR=ra8m2_gcc_CPU0_secure
  set BL_DIR=ra8m2_gcc_mcuboot
  set NS_DIR=ra8m2_gcc_CPU0_nonsecure
  set RTT_OPT=RA8M2_RTT_BLOCKING
) else (
  set S_DIR=ra6m5_gcc_secure
  set BL_DIR=ra6m5_gcc_mcuboot
  set NS_DIR=ra6m5_gcc_nonsecure
  set RTT_OPT=RA6M5_RTT_BLOCKING
)
if "%BUILD%"=="" echo usage: %~nx0 ^<build-dir^> ^<TEST_PSA_API^> [part] & exit /b 2
if "%SUITE%"=="" echo usage: %~nx0 ^<build-dir^> ^<TEST_PSA_API^> [part] & exit /b 2

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
    -DCMAKE_C_COMPILER="%GCC_BIN%/arm-none-eabi-gcc.exe" ^
    -DCONFIG_TFM_SOURCE_PATH=%TFM_SRC% ^
    -DTFM_TOOLCHAIN_FILE=%TFM_SRC%/toolchain_GNUARM.cmake ^
    -DTFM_PLATFORM=renesas/%PART% ^
    -DFSP_S_APP_DIR=%FSP_CMAKE%/%S_DIR% ^
    -DFSP_BL2_APP_DIR=%FSP_CMAKE%/%BL_DIR% ^
    -DFSP_NS_APP_DIR=%FSP_CMAKE%/%NS_DIR% ^
    -DTEST_PSA_API=%SUITE% ^
    -DTFM_PROFILE=profile_large ^
    -DTFM_ISOLATION_LEVEL=3 ^
    -DCONFIG_TFM_SPM_BACKEND=IPC ^
    -DTFM_SPM_DEBUG_TRACE=OFF ^
    -DMCUBOOT_LOG_LEVEL=INFO ^
    -DTFM_SPM_LOG_LEVEL=TFM_SPM_LOG_LEVEL_DEBUG ^
    -DTFM_PARTITION_LOG_LEVEL=TFM_PARTITION_LOG_LEVEL_INFO ^
    -DCONFIG_TFM_HALT_ON_CORE_PANIC=ON ^
    -D%RTT_OPT%=ON ^
    -DPSA_ARCH_TESTS_PATH=%PSA_TESTS% ^
    -DPSA_API_TEST_TARGET=renesas_ra
  if errorlevel 1 exit /b 1
)

cmake --build %BUILD% -- install
exit /b %ERRORLEVEL%
