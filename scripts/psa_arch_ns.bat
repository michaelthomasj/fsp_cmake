@echo off
rem  RA6M5 PSA Arch non-secure app, GCC or IAR.
rem
rem    psa_arch_ns.bat <build-dir> <spe-api_ns-dir> <TEST_PSA_API> [iar]
rem    psa_arch_ns.bat C:\b\m5att  C:\b\m5cry\api_ns  INITIAL_ATTESTATION
rem    psa_arch_ns.bat C:\b\m5iatt C:\b\m5icry\api_ns INITIAL_ATTESTATION iar
rem
rem  Suites: CRYPTO, INITIAL_ATTESTATION, STORAGE (runs ITS and PS), PROTECTED_STORAGE,
rem  INTERNAL_TRUSTED_STORAGE.
rem
rem  MSVC is needed for BOTH toolchains: the api-tests build compiles a host tool
rem  (TargetConfigGen) with cl.exe. Without it, configure fails on a missing stdio.h.
rem
rem  The "iar" argument adds what the IAR NS build needs (DECISIONS D046):
rem    - TFM_TOOLCHAIN_FILE pointing at the SPE's exported toolchain_ns_IARARM.cmake, or the
rem      build silently selects GNUARM and fails looking for script/fsp.ld in an IAR project;
rem    - TOOLCHAIN=INHERIT, or psa-arch-tests compiles with arm-none-eabi-gcc while being
rem      handed IAR flags;
rem    - IAR on PATH, and the ASM architecture id CMake cannot detect.

if "%IAR_BIN%"==""    set IAR_BIN=C:\iar\ewarm-10.10.2\arm\bin
if "%MSVC_VARS%"==""  set MSVC_VARS=C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat
if "%TFM_TESTS%"==""  set TFM_TESTS=C:\Users\Michael\Documents\GitHub\tf-m-tests
if "%PSA_TESTS%"==""  set PSA_TESTS=C:\Users\Michael\Documents\GitHub\psa-arch-tests

set BUILD=%1
set SPE=%2
set SUITE=%3
set TC=%4
if "%SUITE%"=="" echo usage: %~nx0 ^<build-dir^> ^<spe-api_ns-dir^> ^<TEST_PSA_API^> [iar] & exit /b 2

call "%MSVC_VARS%" >nul

set TC_ARGS=
if /i "%TC%"=="iar" (
  set PATH=%IAR_BIN%;%PATH%
  set TC_ARGS=-DTFM_TOOLCHAIN_FILE=%SPE:\=/%/cmake/toolchain_ns_IARARM.cmake -DTOOLCHAIN=INHERIT -DCMAKE_ASM_COMPILER_ARCHITECTURE_ID=ARM
)

if not exist "%BUILD%\CMakeCache.txt" (
  cmake -S %TFM_TESTS%\tests_psa_arch -B %BUILD% -GNinja ^
    -DCMAKE_BUILD_TYPE=MinSizeRel ^
    -DCONFIG_SPE_PATH=%SPE% ^
    %TC_ARGS% ^
    -DTEST_PSA_API=%SUITE% ^
    -DTFM_PROFILE=profile_large ^
    -DTFM_ISOLATION_LEVEL=3 ^
    -DCONFIG_TFM_SPM_BACKEND=IPC ^
    -DPSA_ARCH_TESTS_PATH=%PSA_TESTS% ^
    -DPSA_API_TEST_TARGET=renesas_ra
  if errorlevel 1 exit /b 1
)

cmake --build %BUILD%
exit /b %ERRORLEVEL%
