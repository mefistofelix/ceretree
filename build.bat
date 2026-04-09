@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "GO_VERSION=1.26.2"
set "ZIG_VERSION=0.15.2"
set "BUN_VERSION=bun-v1.3.11"
set "TREE_SITTER_VERSION=v0.26.8"

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
set "TREE_SITTER_EXE=%ROOT%\build_cache\tools\tree-sitter-cli\bin\tree-sitter.exe"
set "TREE_SITTER_ZIP=%DOWNLOADS_DIR%\tree-sitter-cli-windows-x64.zip"
set "WRAPPER_DIR=%ROOT%\build_cache\tool_wrappers"
set "GRAMMAR_ROOT=%ROOT%\build_cache\grammars"
set "GRAMMAR_STATE_DIR=%ROOT%\build_cache\grammar_state"
set "GENERATED_DIR=%ROOT%\build_cache\generated"
set "OBJ_DIR=%GENERATED_DIR%\obj"
set "INC_DIR=%GENERATED_DIR%\include"
set "SRC_DIR=%GENERATED_DIR%\src"
set "LIB_DIR=%GENERATED_DIR%\lib"
set "LIB_FILE=%LIB_DIR%\ceretree_grammars.a"
set "OBJECTS="
set "TARGET_NAME="
set "TARGET_CC="
set "TARGET_CXX="
set "TARGET_GOOS="
set "TARGET_GOARCH="
set "TARGET_OUTPUT="
set "TARGET_CGO_LDFLAGS="

for %%D in ("%DOWNLOADS_DIR%" "%TOOLCHAINS_DIR%" "%ROOT%\bin" "%ROOT%\build_cache\gopath" "%ROOT%\build_cache\gocache" "%ROOT%\build_cache\tools" "%WRAPPER_DIR%" "%GRAMMAR_ROOT%" "%GRAMMAR_STATE_DIR%" "%OBJ_DIR%" "%INC_DIR%" "%SRC_DIR%" "%LIB_DIR%") do (
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

if not exist "%TREE_SITTER_EXE%" (
  gh release download "%TREE_SITTER_VERSION%" -R tree-sitter/tree-sitter -p "tree-sitter-cli-windows-x64.zip" -D "%DOWNLOADS_DIR%" --clobber || goto :fail
  if exist "%ROOT%\build_cache\tools\tree-sitter-cli" rmdir /s /q "%ROOT%\build_cache\tools\tree-sitter-cli"
  mkdir "%ROOT%\build_cache\tools\tree-sitter-cli\bin" || goto :fail
  tar.exe -xf "%TREE_SITTER_ZIP%" -C "%ROOT%\build_cache\tools\tree-sitter-cli\bin" || goto :fail
)

set "PATH=%GO_DIR%\bin;%BUN_DIR%;%PATH%"

>"%WRAPPER_DIR%\zig-cc-windows.cmd" (
  echo @echo off
  echo "%ZIG_EXE%" cc -target x86_64-windows-gnu %%*
)
>"%WRAPPER_DIR%\zig-cxx-windows.cmd" (
  echo @echo off
  echo "%ZIG_EXE%" c++ -target x86_64-windows-gnu %%*
)
>"%WRAPPER_DIR%\zig-cc-linux.cmd" (
  echo @echo off
  echo "%ZIG_EXE%" cc -target x86_64-linux-musl %%*
)
>"%WRAPPER_DIR%\zig-cxx-linux.cmd" (
  echo @echo off
  echo "%ZIG_EXE%" c++ -target x86_64-linux-musl %%*
)

set "CGO_ENABLED=1"

>"%INC_DIR%\ceretree_grammars.h" (
  echo typedef struct TSLanguage TSLanguage;
  echo const TSLanguage *ceretree_language^(const char *name^);
)

>"%SRC_DIR%\ceretree_grammars.c" (
  echo #include ^<string.h^>
  echo #include "ceretree_grammars.h"
)

for /f "usebackq tokens=1-5 delims=|" %%A in ("%ROOT%\src\GRAMMARS.txt") do (
  call :prepare_grammar "%%~A" "%%~B" "%%~C" "%%~D" "%%~E" || goto :fail
)

>>"%SRC_DIR%\ceretree_grammars.c" echo const TSLanguage *ceretree_language^(const char *name^) {
for /f "usebackq tokens=1 delims=|" %%A in ("%ROOT%\src\GRAMMARS.txt") do (
  >>"%SRC_DIR%\ceretree_grammars.c" echo   if ^(strcmp^(name, "%%~A"^) == 0^) return tree_sitter_%%~A^(^);
)
>>"%SRC_DIR%\ceretree_grammars.c" echo   return 0;
>>"%SRC_DIR%\ceretree_grammars.c" echo }

"%GOFMT_EXE%" -w "%ROOT%\src\main.go" || goto :fail

call :build_target windows "%WRAPPER_DIR%\zig-cc-windows.cmd" "%WRAPPER_DIR%\zig-cxx-windows.cmd" windows amd64 "%ROOT%\bin\ceretree.exe" "%LIB_FILE%" || goto :fail
call :build_target linux "%WRAPPER_DIR%\zig-cc-linux.cmd" "%WRAPPER_DIR%\zig-cxx-linux.cmd" linux amd64 "%ROOT%\bin\ceretree" "%LIB_FILE% -static" || goto :fail
exit /b 0

:build_target
set "TARGET_NAME=%~1"
set "TARGET_CC=%~2"
set "TARGET_CXX=%~3"
set "TARGET_GOOS=%~4"
set "TARGET_GOARCH=%~5"
set "TARGET_OUTPUT=%~6"
set "TARGET_CGO_LDFLAGS=%~7"
set "OBJECTS="

if exist "%OBJ_DIR%" del /q "%OBJ_DIR%\*" >nul 2>nul
if exist "%LIB_FILE%" del /q "%LIB_FILE%" >nul 2>nul

call "%TARGET_CC%" -c -O2 "-I%INC_DIR%" "%SRC_DIR%\ceretree_grammars.c" "-o%OBJ_DIR%\ceretree_grammars.o" || exit /b 1
set "OBJECTS=%OBJECTS% "%OBJ_DIR%\ceretree_grammars.o""

for /f "usebackq tokens=1-5 delims=|" %%A in ("%ROOT%\src\GRAMMARS.txt") do (
  call :compile_grammar_objects "%%~A" "%%~D" || exit /b 1
)

"%ZIG_EXE%" ar rcs "%LIB_FILE%" %OBJECTS% || exit /b 1

set "CC=%TARGET_CC%"
set "CXX=%TARGET_CXX%"
set "GOOS=%TARGET_GOOS%"
set "GOARCH=%TARGET_GOARCH%"
set "CGO_CFLAGS=-I%INC_DIR%"
set "CGO_LDFLAGS=%TARGET_CGO_LDFLAGS%"

"%GO_EXE%" build -o "%TARGET_OUTPUT%" ./src || exit /b 1
exit /b 0

:compile_grammar_objects
set "LANGUAGE=%~1"
set "LOCATION=%~2"
set "GRAMMAR_DIR=%GRAMMAR_ROOT%\%LANGUAGE%\repo"
if not "%LOCATION%"=="." set "GRAMMAR_DIR=%GRAMMAR_DIR%\%LOCATION%"

call "%TARGET_CC%" -c -O2 "-I%GRAMMAR_DIR%\src" "%GRAMMAR_DIR%\src\parser.c" "-o%OBJ_DIR%\%LANGUAGE%_parser.o" || exit /b 1
set "OBJECTS=%OBJECTS% "%OBJ_DIR%\%LANGUAGE%_parser.o""

if exist "%GRAMMAR_DIR%\src\scanner.c" (
  call "%TARGET_CC%" -c -O2 "-I%GRAMMAR_DIR%\src" "%GRAMMAR_DIR%\src\scanner.c" "-o%OBJ_DIR%\%LANGUAGE%_scanner.o" || exit /b 1
  set "OBJECTS=%OBJECTS% "%OBJ_DIR%\%LANGUAGE%_scanner.o""
)

if exist "%GRAMMAR_DIR%\src\scanner.cc" (
  call "%TARGET_CXX%" -c -O2 "-I%GRAMMAR_DIR%\src" "%GRAMMAR_DIR%\src\scanner.cc" "-o%OBJ_DIR%\%LANGUAGE%_scanner_cc.o" || exit /b 1
  set "OBJECTS=%OBJECTS% "%OBJ_DIR%\%LANGUAGE%_scanner_cc.o""
)

exit /b 0

:prepare_grammar
set "LANGUAGE=%~1"
set "REPO=%~2"
set "REVISION=%~3"
set "LOCATION=%~4"
set "NEEDS_BUN=%~5"
set "REPO_DIR=%GRAMMAR_ROOT%\%LANGUAGE%\repo"
set "STATE_DIR=%GRAMMAR_STATE_DIR%\%LANGUAGE%"
set "FETCH_STAMP=%STATE_DIR%\fetch.txt"
set "ROOT_BUN_STAMP=%STATE_DIR%\root_bun.txt"
set "GRAMMAR_BUN_STAMP=%STATE_DIR%\grammar_bun.txt"
set "GENERATE_STAMP=%STATE_DIR%\generate.txt"
set "ARCHIVE_ZIP=%DOWNLOADS_DIR%\grammar_%LANGUAGE%.zip"
set "ARCHIVE_TMP=%GRAMMAR_ROOT%\%LANGUAGE%\archive_tmp"
set "REPO_SLUG="
set "RESOLVED_REVISION=%REVISION%"
set "DEFAULT_BRANCH="

if not exist "%STATE_DIR%" mkdir "%STATE_DIR%" || exit /b 1

set "REPO_SLUG=%REPO:https://github.com/=%"
if "%REPO_SLUG:~-1%"=="/" set "REPO_SLUG=%REPO_SLUG:~0,-1%"
if "%REVISION%"=="HEAD" (
  for /f "usebackq delims=" %%A in (`gh api "repos/!REPO_SLUG!" --jq ".default_branch"`) do set "DEFAULT_BRANCH=%%A"
  if not defined DEFAULT_BRANCH exit /b 1
  for /f "usebackq delims=" %%A in (`gh api "repos/!REPO_SLUG!/commits/!DEFAULT_BRANCH!" --jq ".sha"`) do set "RESOLVED_REVISION=%%A"
) else (
  for /f "usebackq delims=" %%A in (`gh api "repos/!REPO_SLUG!/commits/!REVISION!" --jq ".sha"`) do set "RESOLVED_REVISION=%%A"
)
if not defined RESOLVED_REVISION exit /b 1

if not exist "%FETCH_STAMP%" goto :fetch_repo
set /p FETCH_VALUE=<"%FETCH_STAMP%"
if not "!FETCH_VALUE!"=="!RESOLVED_REVISION!" goto :fetch_repo
if not exist "%REPO_DIR%" goto :fetch_repo
goto :fetch_done

:fetch_repo
if exist "%ARCHIVE_TMP%" rmdir /s /q "%ARCHIVE_TMP%"
mkdir "%ARCHIVE_TMP%" || exit /b 1
curl.exe -fsSL "https://github.com/%REPO_SLUG%/archive/%RESOLVED_REVISION%.zip" -o "%ARCHIVE_ZIP%" || exit /b 1
tar.exe -xf "%ARCHIVE_ZIP%" -C "%ARCHIVE_TMP%" || exit /b 1
if exist "%REPO_DIR%" rmdir /s /q "%REPO_DIR%"
for /d %%D in ("%ARCHIVE_TMP%\*") do (
  move "%%~fD" "%REPO_DIR%" >nul || exit /b 1
  goto :fetch_finish
)
exit /b 1

:fetch_finish
if exist "%ARCHIVE_TMP%" rmdir /s /q "%ARCHIVE_TMP%"
>"%FETCH_STAMP%" echo !RESOLVED_REVISION!

:fetch_done

set "GRAMMAR_DIR=%REPO_DIR%"
if not "%LOCATION%"=="." set "GRAMMAR_DIR=%REPO_DIR%\%LOCATION%"
set "GENERATE_KEY=!RESOLVED_REVISION!^|%TREE_SITTER_VERSION%^|%LOCATION%^|%NEEDS_BUN%"

set "DO_GRAMMAR_BUN="
if "%NEEDS_BUN%"=="1" if exist "%GRAMMAR_DIR%\package.json" set "DO_GRAMMAR_BUN=1"
if defined DO_GRAMMAR_BUN if exist "%GRAMMAR_BUN_STAMP%" (
  set /p GRAMMAR_BUN_VALUE=<"%GRAMMAR_BUN_STAMP%"
  if "!GRAMMAR_BUN_VALUE!"=="!GENERATE_KEY!" set "DO_GRAMMAR_BUN="
)
if defined DO_GRAMMAR_BUN (
  pushd "%GRAMMAR_DIR%" || exit /b 1
  "%BUN_EXE%" install --ignore-scripts || exit /b 1
  popd
  >"%GRAMMAR_BUN_STAMP%" <nul set /p "=!GENERATE_KEY!"
)

set "DO_ROOT_BUN="
if "%NEEDS_BUN%"=="1" if exist "%REPO_DIR%\package.json" set "DO_ROOT_BUN=1"
if defined DO_ROOT_BUN if exist "%ROOT_BUN_STAMP%" (
  set /p ROOT_BUN_VALUE=<"%ROOT_BUN_STAMP%"
  if "!ROOT_BUN_VALUE!"=="!GENERATE_KEY!" set "DO_ROOT_BUN="
)
if defined DO_ROOT_BUN (
  pushd "%REPO_DIR%" || exit /b 1
  "%BUN_EXE%" install --ignore-scripts || exit /b 1
  popd
  >"%ROOT_BUN_STAMP%" <nul set /p "=!GENERATE_KEY!"
)

set "DO_GENERATE=1"
if exist "%GENERATE_STAMP%" if exist "%GRAMMAR_DIR%\src\parser.c" (
  set /p GENERATE_VALUE=<"%GENERATE_STAMP%"
  if "!GENERATE_VALUE!"=="!GENERATE_KEY!" set "DO_GENERATE="
)
if defined DO_GENERATE (
  pushd "%GRAMMAR_DIR%" || exit /b 1
  "%TREE_SITTER_EXE%" generate --js-runtime bun || exit /b 1
  popd
  >"%GENERATE_STAMP%" <nul set /p "=!GENERATE_KEY!"
)

if not exist "%GRAMMAR_DIR%\src\parser.c" exit /b 1

>>"%SRC_DIR%\ceretree_grammars.c" echo extern const TSLanguage *tree_sitter_%LANGUAGE%^(void^);

exit /b 0

:fail
exit /b 1
