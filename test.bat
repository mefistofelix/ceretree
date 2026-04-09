@echo off
setlocal

call "%~dp0build.bat"
if errorlevel 1 exit /b 1

set "EXE=%~dp0bin\ceretree.exe"
set "BUN_EXE=%~dp0build_cache\toolchains\bun-windows-x64\bun.exe"
set "ROOT=%~dp0"
set "TESTS_DIR=%~dp0tests_cache"
set "REQUEST_FILE=%TESTS_DIR%\request.json"
set "RESPONSE_FILE=%TESTS_DIR%\response.json"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

if not exist "%TESTS_DIR%" mkdir "%TESTS_DIR%"

>"%REQUEST_FILE%" echo {"jsonrpc":"2.0","id":1,"method":"system.describe"}
"%EXE%" <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); if (data.result.name !== 'ceretree') process.exit(1); if (!data.result.languages.includes('go')) process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1

>"%REQUEST_FILE%" echo {"jsonrpc":"2.0","id":2,"method":"roots.add","params":{"paths":["%ROOT:/=\%"]}}
"%EXE%" <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); if (!Array.isArray(data.result.roots) || data.result.roots.length < 1) process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1

>"%REQUEST_FILE%" echo {"jsonrpc":"2.0","id":3,"method":"query","params":{"language":"go","query":"(package_identifier) @name","roots":["%ROOT:/=\%"],"include":"src/main.go"}}
"%EXE%" <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); if (!Array.isArray(data.result.matches) || data.result.matches.length < 1) process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1
