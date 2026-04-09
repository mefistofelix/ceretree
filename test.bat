@echo off
setlocal

set "EXE=%~dp0bin\ceretree.exe"
set "BUN_EXE=%~dp0build_cache\toolchains\bun-windows-x64\bun.exe"
set "ROOT=%~dp0"
set "JSON_ROOT=%~dp0"
set "TESTS_DIR=%~dp0tests_cache"
set "REQUEST_FILE=%TESTS_DIR%\request.json"
set "RESPONSE_FILE=%TESTS_DIR%\response.json"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
if "%JSON_ROOT:~-1%"=="\" set "JSON_ROOT=%JSON_ROOT:~0,-1%"
set "JSON_ROOT=%JSON_ROOT:\=/%"

if not exist "%EXE%" exit /b 1
if not exist "%BUN_EXE%" exit /b 1

if not exist "%TESTS_DIR%" mkdir "%TESTS_DIR%"

>"%REQUEST_FILE%" echo {"jsonrpc":"2.0","id":1,"method":"system.describe"}
"%EXE%" <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); if (data.result.name !== 'ceretree') process.exit(1); if (!data.result.languages.includes('go')) process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1

>"%REQUEST_FILE%" echo {"jsonrpc":"2.0","id":2,"method":"roots.add","params":{"paths":["%JSON_ROOT%"]}}
"%EXE%" <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); if (!Array.isArray(data.result.roots) || data.result.roots.length < 1) process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1

>"%REQUEST_FILE%" echo {"jsonrpc":"2.0","id":3,"method":"query","params":{"language":"go","query":"(package_identifier) @name","roots":["%JSON_ROOT%"],"include":"src/main.go"}}
"%EXE%" <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); if (!Array.isArray(data.result.matches) || data.result.matches.length < 1) process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1

>"%REQUEST_FILE%" echo {"jsonrpc":"2.0","id":4,"method":"index.status"}
"%EXE%" <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); if (!Array.isArray(data.result.roots) || data.result.roots.length < 1) process.exit(1); if (!data.result.last_query) process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1

>"%REQUEST_FILE%" echo {"jsonrpc":"2.0","id":5,"method":"symbols.overview","params":{"language":"go","roots":["%JSON_ROOT%"],"include":"src/main.go","max_symbols":20}}
"%EXE%" <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); if (!Array.isArray(data.result.files) || data.result.files.length < 1) process.exit(1); if (!Array.isArray(data.result.files[0].symbols) || data.result.files[0].symbols.length < 1) process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1

>"%REQUEST_FILE%" (
  echo {"jsonrpc":"2.0","id":6,"method":"system.describe"}
  echo {"jsonrpc":"2.0","id":7,"method":"symbols.overview","params":{"language":"go","roots":["%JSON_ROOT%"],"include":"src/main.go","max_symbols":5}}
)
"%EXE%" --server <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const lines = fs.readFileSync(process.argv[1], 'utf8').trim().split(/\r?\n/).filter(Boolean); if (lines.length !== 2) process.exit(1); const first = JSON.parse(lines[0]); const second = JSON.parse(lines[1]); if (!first.result.server_mode.active) process.exit(1); if (!Array.isArray(second.result.files) || second.result.files.length < 1) process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1
