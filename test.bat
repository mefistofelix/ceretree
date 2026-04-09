@echo off
setlocal

call "%~dp0build.bat"
if errorlevel 1 exit /b 1

set "EXE=%~dp0bin\ceretree.exe"
set "BUN_EXE=%~dp0build_cache\toolchains\bun-windows-x64\bun.exe"
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

for /f "usebackq delims=" %%A in (`"%EXE%" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"system.describe\"}"`) do set DESCRIBE_JSON=%%A
"%BUN_EXE%" -e "const data = JSON.parse(process.argv[1]); if (data.result.name !== 'ceretree') process.exit(1); if (!data.result.languages.includes('go')) process.exit(1);" "%DESCRIBE_JSON%"
if errorlevel 1 exit /b 1

for /f "usebackq delims=" %%A in (`"%EXE%" "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"roots.add\",\"params\":{\"paths\":[\"%ROOT%\"]}}"`) do set ADD_JSON=%%A
"%BUN_EXE%" -e "const data = JSON.parse(process.argv[1]); if (!Array.isArray(data.result.roots) || data.result.roots.length < 1) process.exit(1);" "%ADD_JSON%"
if errorlevel 1 exit /b 1

for /f "usebackq delims=" %%A in (`"%EXE%" "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"query\",\"params\":{\"language\":\"go\",\"query\":\"(package_identifier) @name\",\"roots\":[\"%ROOT%\"],\"include\":\"src/main.go\"}}"`) do set QUERY_JSON=%%A
"%BUN_EXE%" -e "const data = JSON.parse(process.argv[1]); if (!Array.isArray(data.result.matches) || data.result.matches.length < 1) process.exit(1);" "%QUERY_JSON%"
if errorlevel 1 exit /b 1
