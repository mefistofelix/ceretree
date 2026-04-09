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
set "BUILD_MODE=windows"
set "TARGET_NAME="
set "TARGET_CC="
set "TARGET_CXX="
set "TARGET_GOOS="
set "TARGET_GOARCH="
set "TARGET_OUTPUT="
set "TARGET_EXTRA_LDFLAGS="
set "TARGET_OBJ_DIR="
set "TARGET_LIB_FILE="

if /i "%~1"=="windows" set "BUILD_MODE=windows"
if /i "%~1"=="linux" set "BUILD_MODE=linux"
if /i "%~1"=="all" set "BUILD_MODE=all"
if not "%~1"=="" if /i not "%~1"=="windows" if /i not "%~1"=="linux" if /i not "%~1"=="all" exit /b 1

echo [ceretree] build mode: %BUILD_MODE%

for %%D in ("%DOWNLOADS_DIR%" "%TOOLCHAINS_DIR%" "%ROOT%\bin" "%ROOT%\build_cache\gopath" "%ROOT%\build_cache\gocache" "%ROOT%\build_cache\tools" "%WRAPPER_DIR%" "%GRAMMAR_ROOT%" "%GRAMMAR_STATE_DIR%" "%OBJ_DIR%" "%INC_DIR%" "%SRC_DIR%" "%LIB_DIR%") do (
  if not exist "%%~D" mkdir "%%~D"
)

if not exist "%GO_EXE%" (
  echo [ceretree] bootstrap go %GO_VERSION%
  curl.exe -fsSL "https://go.dev/dl/go%GO_VERSION%.windows-amd64.zip" -o "%GO_ZIP%" || goto :fail
  if exist "%GO_DIR%" rmdir /s /q "%GO_DIR%"
  tar.exe -xf "%GO_ZIP%" -C "%TOOLCHAINS_DIR%" || goto :fail
)

if not exist "%ZIG_EXE%" (
  echo [ceretree] bootstrap zig %ZIG_VERSION%
  curl.exe -fsSL "https://ziglang.org/download/%ZIG_VERSION%/zig-x86_64-windows-%ZIG_VERSION%.zip" -o "%ZIG_ZIP%" || goto :fail
  if exist "%ZIG_DIR%" rmdir /s /q "%ZIG_DIR%"
  tar.exe -xf "%ZIG_ZIP%" -C "%TOOLCHAINS_DIR%" || goto :fail
)

if not exist "%BUN_EXE%" (
  echo [ceretree] bootstrap bun %BUN_VERSION%
  curl.exe -fsSL "https://github.com/oven-sh/bun/releases/download/%BUN_VERSION%/bun-windows-x64.zip" -o "%BUN_ZIP%" || goto :fail
  if exist "%BUN_DIR%" rmdir /s /q "%BUN_DIR%"
  tar.exe -xf "%BUN_ZIP%" -C "%TOOLCHAINS_DIR%" || goto :fail
)

if not exist "%TREE_SITTER_EXE%" (
  echo [ceretree] bootstrap tree-sitter-cli %TREE_SITTER_VERSION%
  curl.exe -fsSL "https://github.com/tree-sitter/tree-sitter/releases/download/%TREE_SITTER_VERSION%/tree-sitter-cli-windows-x64.zip" -o "%TREE_SITTER_ZIP%" || goto :fail
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

if /i "%BUILD_MODE%"=="windows" call :build_target windows "%WRAPPER_DIR%\zig-cc-windows.cmd" "%WRAPPER_DIR%\zig-cxx-windows.cmd" windows amd64 "%ROOT%\bin\ceretree.exe" "" || goto :fail
if /i "%BUILD_MODE%"=="linux" call :build_target linux "%WRAPPER_DIR%\zig-cc-linux.cmd" "%WRAPPER_DIR%\zig-cxx-linux.cmd" linux amd64 "%ROOT%\bin\ceretree" "-static" || goto :fail
if /i "%BUILD_MODE%"=="all" call :build_target windows "%WRAPPER_DIR%\zig-cc-windows.cmd" "%WRAPPER_DIR%\zig-cxx-windows.cmd" windows amd64 "%ROOT%\bin\ceretree.exe" "" || goto :fail
if /i "%BUILD_MODE%"=="all" call :build_target linux "%WRAPPER_DIR%\zig-cc-linux.cmd" "%WRAPPER_DIR%\zig-cxx-linux.cmd" linux amd64 "%ROOT%\bin\ceretree" "-static" || goto :fail
exit /b 0

:build_target
set "TARGET_NAME=%~1"
set "TARGET_CC=%~2"
set "TARGET_CXX=%~3"
set "TARGET_GOOS=%~4"
set "TARGET_GOARCH=%~5"
set "TARGET_OUTPUT=%~6"
set "TARGET_EXTRA_LDFLAGS=%~7"
set "TARGET_OBJ_DIR=%OBJ_DIR%\%TARGET_NAME%"
set "TARGET_LIB_FILE=%LIB_DIR%\ceretree_grammars_%TARGET_NAME%.a"
set "OBJECTS="

echo [ceretree] target %TARGET_NAME% start

if not exist "%TARGET_OBJ_DIR%" mkdir "%TARGET_OBJ_DIR%" || exit /b 1

call "%TARGET_CC%" -c -O2 "-I%INC_DIR%" "%SRC_DIR%\ceretree_grammars.c" "-o%TARGET_OBJ_DIR%\ceretree_grammars.o" || exit /b 1
set "OBJECTS=%OBJECTS% "%TARGET_OBJ_DIR%\ceretree_grammars.o""

for /f "usebackq tokens=1-5 delims=|" %%A in ("%ROOT%\src\GRAMMARS.txt") do (
  call :compile_grammar_objects "%%~A" "%%~D" || exit /b 1
)

"%ZIG_EXE%" ar rcs "%TARGET_LIB_FILE%" %OBJECTS% || exit /b 1

set "CC=%TARGET_CC%"
set "CXX=%TARGET_CXX%"
set "GOOS=%TARGET_GOOS%"
set "GOARCH=%TARGET_GOARCH%"
set "CGO_CFLAGS=-I%INC_DIR%"
set "CGO_LDFLAGS=%TARGET_LIB_FILE% %TARGET_EXTRA_LDFLAGS%"

"%GO_EXE%" build -o "%TARGET_OUTPUT%" ./src || exit /b 1
echo [ceretree] target %TARGET_NAME% done
exit /b 0

:compile_grammar_objects
set "LANGUAGE=%~1"
set "LOCATION=%~2"
set "GRAMMAR_DIR=%GRAMMAR_ROOT%\%LANGUAGE%\repo"
set "STATE_DIR=%GRAMMAR_STATE_DIR%\%LANGUAGE%"
set "GENERATE_STAMP=%STATE_DIR%\generate.txt"
set "GRAMMAR_KEY="
set "OBJECT_KEY="
set "PARSER_OBJ=%TARGET_OBJ_DIR%\%LANGUAGE%_parser.o"
set "PARSER_STAMP=%TARGET_OBJ_DIR%\%LANGUAGE%_parser.stamp"
set "SCANNER_OBJ=%TARGET_OBJ_DIR%\%LANGUAGE%_scanner.o"
set "SCANNER_STAMP=%TARGET_OBJ_DIR%\%LANGUAGE%_scanner.stamp"
set "SCANNER_CC_OBJ=%TARGET_OBJ_DIR%\%LANGUAGE%_scanner_cc.o"
set "SCANNER_CC_STAMP=%TARGET_OBJ_DIR%\%LANGUAGE%_scanner_cc.stamp"
if not "%LOCATION%"=="." set "GRAMMAR_DIR=%GRAMMAR_DIR%\%LOCATION%"

if not exist "%GENERATE_STAMP%" exit /b 1
set /p GRAMMAR_KEY=<"%GENERATE_STAMP%"
set "OBJECT_KEY=%TARGET_NAME%^|%ZIG_VERSION%^|!GRAMMAR_KEY!"

set "DO_PARSER=1"
if exist "%PARSER_STAMP%" if exist "%PARSER_OBJ%" (
  set /p PARSER_VALUE=<"%PARSER_STAMP%"
  if "!PARSER_VALUE!"=="!OBJECT_KEY!" set "DO_PARSER="
)
if defined DO_PARSER (
  echo [ceretree] %TARGET_NAME% compile %LANGUAGE% parser.c
  call "%TARGET_CC%" -c -O2 "-I%GRAMMAR_DIR%\src" "%GRAMMAR_DIR%\src\parser.c" "-o%PARSER_OBJ%" || exit /b 1
  >"%PARSER_STAMP%" <nul set /p "=!OBJECT_KEY!"
)
set "OBJECTS=%OBJECTS% "%PARSER_OBJ%""

if exist "%GRAMMAR_DIR%\src\scanner.c" (
  set "DO_SCANNER=1"
  if exist "%SCANNER_STAMP%" if exist "%SCANNER_OBJ%" (
    set /p SCANNER_VALUE=<"%SCANNER_STAMP%"
    if "!SCANNER_VALUE!"=="!OBJECT_KEY!" set "DO_SCANNER="
  )
  if defined DO_SCANNER (
    echo [ceretree] %TARGET_NAME% compile %LANGUAGE% scanner.c
    call "%TARGET_CC%" -c -O2 "-I%GRAMMAR_DIR%\src" "%GRAMMAR_DIR%\src\scanner.c" "-o%SCANNER_OBJ%" || exit /b 1
    >"%SCANNER_STAMP%" <nul set /p "=!OBJECT_KEY!"
  )
  set "OBJECTS=%OBJECTS% "%SCANNER_OBJ%""
)
if not exist "%GRAMMAR_DIR%\src\scanner.c" (
  if exist "%SCANNER_OBJ%" del /q "%SCANNER_OBJ%" >nul 2>nul
  if exist "%SCANNER_STAMP%" del /q "%SCANNER_STAMP%" >nul 2>nul
)

if exist "%GRAMMAR_DIR%\src\scanner.cc" (
  set "DO_SCANNER_CC=1"
  if exist "%SCANNER_CC_STAMP%" if exist "%SCANNER_CC_OBJ%" (
    set /p SCANNER_CC_VALUE=<"%SCANNER_CC_STAMP%"
    if "!SCANNER_CC_VALUE!"=="!OBJECT_KEY!" set "DO_SCANNER_CC="
  )
  if defined DO_SCANNER_CC (
    echo [ceretree] %TARGET_NAME% compile %LANGUAGE% scanner.cc
    call "%TARGET_CXX%" -c -O2 "-I%GRAMMAR_DIR%\src" "%GRAMMAR_DIR%\src\scanner.cc" "-o%SCANNER_CC_OBJ%" || exit /b 1
    >"%SCANNER_CC_STAMP%" <nul set /p "=!OBJECT_KEY!"
  )
  set "OBJECTS=%OBJECTS% "%SCANNER_CC_OBJ%""
)
if not exist "%GRAMMAR_DIR%\src\scanner.cc" (
  if exist "%SCANNER_CC_OBJ%" del /q "%SCANNER_CC_OBJ%" >nul 2>nul
  if exist "%SCANNER_CC_STAMP%" del /q "%SCANNER_CC_STAMP%" >nul 2>nul
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

if not exist "%STATE_DIR%" mkdir "%STATE_DIR%" || exit /b 1

set "REPO_SLUG=%REPO:https://github.com/=%"
if "%REPO_SLUG:~-1%"=="/" set "REPO_SLUG=%REPO_SLUG:~0,-1%"
echo [ceretree] grammar %LANGUAGE% resolve ref
if "%REVISION%"=="HEAD" (
  set "RESOLVED_REVISION="
  for /f "usebackq tokens=1" %%A in (`git ls-remote "!REPO!" HEAD`) do (
    if not defined RESOLVED_REVISION set "RESOLVED_REVISION=%%A"
  )
) else (
  set "RESOLVED_REVISION="
  for /f "usebackq tokens=1" %%A in (`git ls-remote "!REPO!" "!REVISION!"`) do (
    if not defined RESOLVED_REVISION set "RESOLVED_REVISION=%%A"
  )
  if not defined RESOLVED_REVISION set "RESOLVED_REVISION=%REVISION%"
)
if not defined RESOLVED_REVISION exit /b 1

if not exist "%FETCH_STAMP%" goto :fetch_repo
set /p FETCH_VALUE=<"%FETCH_STAMP%"
if not "!FETCH_VALUE!"=="!RESOLVED_REVISION!" goto :fetch_repo
if not exist "%REPO_DIR%" goto :fetch_repo
goto :fetch_done

:fetch_repo
echo [ceretree] grammar %LANGUAGE% download snapshot
if exist "%ARCHIVE_TMP%" rmdir /s /q "%ARCHIVE_TMP%"
mkdir "%ARCHIVE_TMP%" || exit /b 1
curl.exe -fsSL "https://codeload.github.com/%REPO_SLUG%/zip/%RESOLVED_REVISION%" -o "%ARCHIVE_ZIP%" || exit /b 1
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
  echo [ceretree] grammar %LANGUAGE% bun install ^(subdir^)
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
  echo [ceretree] grammar %LANGUAGE% bun install ^(repo root^)
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
  echo [ceretree] grammar %LANGUAGE% tree-sitter generate
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
