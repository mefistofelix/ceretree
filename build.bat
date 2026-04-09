@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "GO_VERSION=1.26.2"
set "ZIG_VERSION=0.15.2"
set "BUN_VERSION=bun-v1.3.11"
set "MSVC_VERSION=14.44.17.14"
set "SDK_VERSION=10.0.22621.7"
set "TARGET_TRIPLE=x86_64-pc-windows-msvc"

set "DOWNLOADS_DIR=%ROOT%\build_cache\downloads"
set "TOOLCHAINS_DIR=%ROOT%\build_cache\toolchains"
set "GO_DIR=%TOOLCHAINS_DIR%\go"
set "GO_EXE=%GO_DIR%\bin\go.exe"
set "GOFMT_EXE=%GO_DIR%\bin\gofmt.exe"
set "GO_ZIP=%DOWNLOADS_DIR%\go%GO_VERSION%.windows-amd64.zip"
set "ZIG_DIR=%TOOLCHAINS_DIR%\zig-x86_64-windows-%ZIG_VERSION%"
set "ZIG_EXE=%ZIG_DIR%\zig.exe"
set "ZIG_ZIP=%DOWNLOADS_DIR%\zig-x86_64-windows-%ZIG_VERSION%.zip"
set "BUN_DIR=%TOOLCHAINS_DIR%\bun-windows-x64"
set "BUN_EXE=%BUN_DIR%\bun.exe"
set "BUN_ZIP=%DOWNLOADS_DIR%\bun-windows-x64.zip"
set "MSVCUP_DIR=%ROOT%\build_cache\tools\msvcup"
set "MSVCUP_EXE=%MSVCUP_DIR%\msvcup.exe"
set "MSVCUP_ZIP=%DOWNLOADS_DIR%\msvcup-x86_64-windows.zip"
set "MSVC_INSTALL_DIR=%ROOT%\build_cache\msvc"
set "RUSTUP_HOME=%ROOT%\build_cache\rustup"
set "CARGO_HOME=%ROOT%\build_cache\cargo"
set "RUSTUP_INIT=%DOWNLOADS_DIR%\rustup-init.exe"
set "TREE_SITTER_EXE=%ROOT%\build_cache\tools\tree-sitter-cli\bin\tree-sitter.exe"
set "WRAPPER_DIR=%ROOT%\build_cache\tool_wrappers"
set "GRAMMAR_ROOT=%ROOT%\build_cache\grammars"
set "GENERATED_DIR=%ROOT%\build_cache\generated"
set "OBJ_DIR=%GENERATED_DIR%\obj"
set "INC_DIR=%GENERATED_DIR%\include"
set "SRC_DIR=%GENERATED_DIR%\src"
set "LIB_DIR=%GENERATED_DIR%\lib"
set "LIB_FILE=%LIB_DIR%\ceretree_grammars.a"
set "OBJECTS="

for %%D in ("%DOWNLOADS_DIR%" "%TOOLCHAINS_DIR%" "%ROOT%\bin" "%ROOT%\build_cache\gopath" "%ROOT%\build_cache\gocache" "%ROOT%\build_cache\tools" "%MSVCUP_DIR%" "%RUSTUP_HOME%" "%CARGO_HOME%" "%WRAPPER_DIR%" "%GRAMMAR_ROOT%" "%OBJ_DIR%" "%INC_DIR%" "%SRC_DIR%" "%LIB_DIR%") do (
  if not exist "%%~D" mkdir "%%~D"
)

if not exist "%GO_EXE%" (
  curl.exe -fsSL "https://go.dev/dl/go%GO_VERSION%.windows-amd64.zip" -o "%GO_ZIP%" || goto :fail
  if exist "%GO_DIR%" rmdir /s /q "%GO_DIR%"
  tar.exe -xf "%GO_ZIP%" -C "%TOOLCHAINS_DIR%" || goto :fail
)

if not exist "%ZIG_EXE%" (
  curl.exe -fsSL "https://ziglang.org/download/%ZIG_VERSION%/zig-x86_64-windows-%ZIG_VERSION%.zip" -o "%ZIG_ZIP%" || goto :fail
  if exist "%ZIG_DIR%" rmdir /s /q "%ZIG_DIR%"
  tar.exe -xf "%ZIG_ZIP%" -C "%TOOLCHAINS_DIR%" || goto :fail
)

if not exist "%BUN_EXE%" (
  gh release download "%BUN_VERSION%" -R oven-sh/bun -p "bun-windows-x64.zip" -D "%DOWNLOADS_DIR%" --clobber || goto :fail
  if exist "%BUN_DIR%" rmdir /s /q "%BUN_DIR%"
  tar.exe -xf "%BUN_ZIP%" -C "%TOOLCHAINS_DIR%" || goto :fail
)

if not exist "%MSVCUP_EXE%" (
  gh release download v2026_03_02 -R marler8997/msvcup -p "msvcup-x86_64-windows.zip" -D "%DOWNLOADS_DIR%" --clobber || goto :fail
  tar.exe -xf "%MSVCUP_ZIP%" -C "%MSVCUP_DIR%" || goto :fail
)

if not exist "%MSVC_INSTALL_DIR%\vcvars-x64.bat" (
  "%MSVCUP_EXE%" install --manifest-update-off "%MSVC_INSTALL_DIR%" autoenv msvc-%MSVC_VERSION% sdk-%SDK_VERSION% || goto :fail
)

set "PATH=%GO_DIR%\bin;%BUN_DIR%;%CARGO_HOME%\bin;%PATH%"
set "RUSTUP_HOME=%RUSTUP_HOME%"
set "CARGO_HOME=%CARGO_HOME%"
call "%MSVC_INSTALL_DIR%\vcvars-x64.bat" || goto :fail

if not exist "%CARGO_HOME%\bin\rustup.exe" (
  curl.exe -fsSL "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe" -o "%RUSTUP_INIT%" || goto :fail
  "%RUSTUP_INIT%" -y --profile minimal --default-toolchain none --no-modify-path || goto :fail
)

rustup run stable-%TARGET_TRIPLE% rustc -vV >nul 2>nul
if errorlevel 1 (
  rustup toolchain uninstall stable-%TARGET_TRIPLE% >nul 2>nul
  rustup toolchain install stable-%TARGET_TRIPLE% --profile minimal || goto :fail
)
rustup default stable-%TARGET_TRIPLE% || goto :fail

if not exist "%TREE_SITTER_EXE%" cargo install --locked --no-default-features tree-sitter-cli --root "%ROOT%\build_cache\tools\tree-sitter-cli" || goto :fail

>"%WRAPPER_DIR%\zig-cc.cmd" (
  echo @echo off
  echo "%ZIG_EXE%" cc -target x86_64-windows-gnu %%*
)
>"%WRAPPER_DIR%\zig-cxx.cmd" (
  echo @echo off
  echo "%ZIG_EXE%" c++ -target x86_64-windows-gnu %%*
)

set "CC=%WRAPPER_DIR%\zig-cc.cmd"
set "CXX=%WRAPPER_DIR%\zig-cxx.cmd"
set "CGO_ENABLED=1"

if exist "%OBJ_DIR%" del /q "%OBJ_DIR%\*" >nul 2>nul
if exist "%LIB_FILE%" del /q "%LIB_FILE%" >nul 2>nul

>"%INC_DIR%\ceretree_grammars.h" (
  echo typedef struct TSLanguage TSLanguage;
  echo const TSLanguage *ceretree_language^(const char *name^);
)

>"%SRC_DIR%\ceretree_grammars.c" (
  echo #include ^<string.h^>
  echo #include "ceretree_grammars.h"
)

for /f "usebackq tokens=1-5 delims=|" %%A in ("%ROOT%\GRAMMARS.txt") do (
  call :prepare_grammar "%%~A" "%%~B" "%%~C" "%%~D" "%%~E" || goto :fail
)

>>"%SRC_DIR%\ceretree_grammars.c" echo const TSLanguage *ceretree_language^(const char *name^) {
for /f "usebackq tokens=1 delims=|" %%A in ("%ROOT%\GRAMMARS.txt") do (
  >>"%SRC_DIR%\ceretree_grammars.c" echo   if ^(strcmp^(name, "%%~A"^) == 0^) return tree_sitter_%%~A^(^);
)
>>"%SRC_DIR%\ceretree_grammars.c" echo   return 0;
>>"%SRC_DIR%\ceretree_grammars.c" echo }

call "%WRAPPER_DIR%\zig-cc.cmd" -c -O2 "-I%INC_DIR%" "%SRC_DIR%\ceretree_grammars.c" "-o%OBJ_DIR%\ceretree_grammars.o" || goto :fail
set "OBJECTS=%OBJECTS% "%OBJ_DIR%\ceretree_grammars.o""

"%ZIG_EXE%" ar rcs "%LIB_FILE%" %OBJECTS% || goto :fail

"%GOFMT_EXE%" -w "%ROOT%\src\main.go" || goto :fail

set "CGO_CFLAGS=-I%INC_DIR%"
set "CGO_LDFLAGS=%LIB_FILE%"

"%GO_EXE%" build -o "%ROOT%\bin\ceretree.exe" ./src || goto :fail
exit /b 0

:prepare_grammar
set "LANGUAGE=%~1"
set "REPO=%~2"
set "REVISION=%~3"
set "LOCATION=%~4"
set "NEEDS_BUN=%~5"
set "REPO_DIR=%GRAMMAR_ROOT%\%LANGUAGE%\repo"

if not exist "%REPO_DIR%\.git" (
  if exist "%REPO_DIR%" rmdir /s /q "%REPO_DIR%"
  git clone --filter=blob:none --no-checkout "%REPO%" "%REPO_DIR%" || exit /b 1
)

git -C "%REPO_DIR%" fetch --depth 1 origin "%REVISION%" || exit /b 1
git -C "%REPO_DIR%" checkout --force FETCH_HEAD || exit /b 1

set "GRAMMAR_DIR=%REPO_DIR%"
if not "%LOCATION%"=="." set "GRAMMAR_DIR=%REPO_DIR%\%LOCATION%"

if "%NEEDS_BUN%"=="1" if exist "%GRAMMAR_DIR%\package.json" (
  pushd "%GRAMMAR_DIR%" || exit /b 1
  "%BUN_EXE%" install --ignore-scripts || exit /b 1
  popd
)

if "%NEEDS_BUN%"=="1" if exist "%REPO_DIR%\package.json" (
  pushd "%REPO_DIR%" || exit /b 1
  "%BUN_EXE%" install --ignore-scripts || exit /b 1
  popd
)

pushd "%GRAMMAR_DIR%" || exit /b 1
"%TREE_SITTER_EXE%" generate --js-runtime bun || exit /b 1
popd

if not exist "%GRAMMAR_DIR%\src\parser.c" exit /b 1

>>"%SRC_DIR%\ceretree_grammars.c" echo extern const TSLanguage *tree_sitter_%LANGUAGE%^(void^);

call "%WRAPPER_DIR%\zig-cc.cmd" -c -O2 "-I%GRAMMAR_DIR%\src" "%GRAMMAR_DIR%\src\parser.c" "-o%OBJ_DIR%\%LANGUAGE%_parser.o" || exit /b 1
set "OBJECTS=%OBJECTS% "%OBJ_DIR%\%LANGUAGE%_parser.o""

if exist "%GRAMMAR_DIR%\src\scanner.c" (
  call "%WRAPPER_DIR%\zig-cc.cmd" -c -O2 "-I%GRAMMAR_DIR%\src" "%GRAMMAR_DIR%\src\scanner.c" "-o%OBJ_DIR%\%LANGUAGE%_scanner.o" || exit /b 1
  set "OBJECTS=%OBJECTS% "%OBJ_DIR%\%LANGUAGE%_scanner.o""
)

if exist "%GRAMMAR_DIR%\src\scanner.cc" (
  call "%WRAPPER_DIR%\zig-cxx.cmd" -c -O2 "-I%GRAMMAR_DIR%\src" "%GRAMMAR_DIR%\src\scanner.cc" "-o%OBJ_DIR%\%LANGUAGE%_scanner_cc.o" || exit /b 1
  set "OBJECTS=%OBJECTS% "%OBJ_DIR%\%LANGUAGE%_scanner_cc.o""
)

exit /b 0

:fail
exit /b 1
