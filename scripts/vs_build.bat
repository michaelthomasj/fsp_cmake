@echo off
rem  Build a CMake tree inside a Visual Studio developer environment.
rem
rem    vs_build.bat                 print the environment and exit (self-check)
rem    vs_build.bat <build-dir>     build it
rem    vs_build.bat C:\b\m5att
rem
rem  REQUIRED FOR EVERY PSA ARCH BUILD, and for nothing else. The psa-arch-tests build
rem  generates targetConfigGen.c and compiles it with cl.exe as a HOST tool, to emit the
rem  target database. cl.exe needs INCLUDE and LIB, which only vcvars sets. Without it the
rem  build dies at:
rem
rem      targetConfigGen.c(1): fatal error C1083:
rem          Cannot open include file: 'stdio.h': No such file or directory
rem
rem  That message invites a hunt through the MSVC installation, and the installation is
rem  fine: stdio.h is a UCRT header shipped with the WINDOWS SDK and has never been part of
rem  the MSVC toolset, so its absence from VC\Tools\MSVC\<ver>\include is normal. The
rem  failure is purely that INCLUDE was unset. DECISIONS D083.
rem
rem  The ordinary TF-M builds (app_build_*.bat, the tf-m-tests regression and the FLIH/SLIH
rem  trees) do NOT need this - they are cross-compiles with no host-tool step.
rem
rem  vcvars64 prints "'vswhere.exe' is not recognized" on this machine. That is cosmetic -
rem  it falls back to the registry and still sets the SDK paths - which is why this script
rem  checks the RESULT rather than the exit code.

setlocal

if "%VS_VCVARS%"=="" set VS_VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat

if not exist "%VS_VCVARS%" (
  echo vs_build: not found: "%VS_VCVARS%"
  echo vs_build: set VS_VCVARS to your vcvars64.bat if Visual Studio is elsewhere.
  exit /b 1
)

call "%VS_VCVARS%" >nul 2>&1

rem  Check the SDK half arrived. The MSVC half alone still fails on stdio.h, which is the
rem  confusing case this script exists to prevent.
rem
rem  Two batch traps in this one line, both hit while writing it:
rem    - %INCLUDE% must be QUOTED. It contains "(x86)", and bare parentheses end the
rem      enclosing block with "\Microsoft was unexpected at this time."
rem    - findstr is called by FULL PATH. A Git Bash or MSYS PATH shadows find and findstr
rem      with the Unix tools, and this script is often launched from such a shell.
echo "%INCLUDE%" | "%SystemRoot%\System32\findstr.exe" /i /c:"Windows Kits" >nul
if errorlevel 1 (
  echo vs_build: vcvars ran but INCLUDE has no Windows Kits entry, so cl.exe will not
  echo vs_build: find stdio.h. Check a Windows SDK is installed beside the Build Tools.
  echo vs_build: INCLUDE="%INCLUDE%"
  exit /b 1
)

if "%~1"=="" (
  echo vs_build: environment OK - Windows SDK is on INCLUDE.
  echo vs_build: INCLUDE="%INCLUDE%"
  echo vs_build: LIB="%LIB%"
  echo vs_build: pass a build directory to build it.
  exit /b 0
)

rem  IAR trees additionally need iccarm and friends on PATH. Harmless for the GCC ones.
rem  Note ewarmc, not ewarm - the stale-path bug in commit bf3d88f, which was still frozen
rem  into the IAR psa-arch trees' CMakeCache and CMakeFiles until 2026-10-02. DECISIONS D083.
if "%IAR_BIN%"=="" set IAR_BIN=C:\iar\ewarmc-10.10.2\arm\bin
if exist "%IAR_BIN%" set PATH=%IAR_BIN%;%PATH%

cmake --build "%~1"
exit /b %ERRORLEVEL%
