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
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); if (data.result.name === 'ceretree' && data.result.languages.includes('go')) process.exit(0); process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1

>"%REQUEST_FILE%" echo {"jsonrpc":"2.0","id":2,"method":"roots.add","params":{"paths":["%JSON_ROOT%"]}}
"%EXE%" <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); if (Array.isArray(data.result.roots) && data.result.roots.length >= 1) process.exit(0); process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1

>"%REQUEST_FILE%" echo {"jsonrpc":"2.0","id":3,"method":"query","params":{"language":"go","query":"(package_identifier) @name","roots":["%JSON_ROOT%"],"include":"src/main.go"}}
"%EXE%" <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); if (Array.isArray(data.result.matches) && data.result.matches.length >= 1) process.exit(0); process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1

>"%REQUEST_FILE%" echo {"jsonrpc":"2.0","id":4,"method":"index.status"}
"%EXE%" <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); if (Array.isArray(data.result.roots) && data.result.roots.length >= 1 && data.result.last_query == null) process.exit(1); process.exit(0);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1

>"%REQUEST_FILE%" echo {"jsonrpc":"2.0","id":5,"method":"symbols.overview","params":{"language":"go","roots":["%JSON_ROOT%"],"include":"src/main.go","max_symbols":20}}
"%EXE%" <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); if (Array.isArray(data.result.files) && data.result.files.length >= 1 && Array.isArray(data.result.files[0].symbols) && data.result.files[0].symbols.length >= 1) process.exit(0); process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1

>"%REQUEST_FILE%" echo {"jsonrpc":"2.0","id":6,"method":"symbols.find","params":{"language":"go","name":"handle_query","kinds":["function"],"roots":["%JSON_ROOT%"],"include":"src/main.go"}}
"%EXE%" <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); const symbols = data.result.files.flatMap(file => file.symbols); if (symbols.some(symbol => symbol.name === 'handle_query')) process.exit(0); process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1

>"%REQUEST_FILE%" echo {"jsonrpc":"2.0","id":61,"method":"symbols.find","params":{"language":"go","kinds":["function"],"roots":["%JSON_ROOT%"],"include":"src/main.go","limit":1,"offset":1}}
"%EXE%" <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); if (data.result.summary.limit === 1 && data.result.summary.offset === 1 && data.result.summary.files_returned <= 1) process.exit(0); process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1

>"%REQUEST_FILE%" echo {"jsonrpc":"2.0","id":7,"method":"calls.find","params":{"language":"go","callee":"invalid_params","roots":["%JSON_ROOT%"],"include":"src/main.go"}}
"%EXE%" <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); const calls = data.result.files.flatMap(file => file.calls); if (calls.some(call => call.callee === 'invalid_params')) process.exit(0); process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1

>"%REQUEST_FILE%" echo {"jsonrpc":"2.0","id":71,"method":"calls.find","params":{"language":"go","roots":["%JSON_ROOT%"],"include":"src/main.go","limit":1}}
"%EXE%" <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); if (data.result.summary.limit === 1 && data.result.summary.files_returned <= 1) process.exit(0); process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1

>"%REQUEST_FILE%" echo {"jsonrpc":"2.0","id":8,"method":"query.common","params":{"language":"go","preset":"functions.by_name","name":"handle_query","roots":["%JSON_ROOT%"],"include":"src/main.go"}}
"%EXE%" <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); const symbols = data.result.files.flatMap(file => file.symbols); if (symbols.some(symbol => symbol.name === 'handle_query')) process.exit(0); process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1

>"%REQUEST_FILE%" echo {"jsonrpc":"2.0","id":81,"method":"query","params":{"language":"go","query":"(identifier) @name","roots":["%JSON_ROOT%"],"include":"src/main.go","limit":1}}
"%EXE%" <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); if (data.result.summary.limit === 1 && data.result.summary.files_returned <= 1) process.exit(0); process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1

"%BUN_EXE%" -e "const fs = require('node:fs'); const body = '{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"system.describe\"}'; fs.writeFileSync(process.argv[1], Buffer.concat([Buffer.from([0xEF,0xBB,0xBF]), Buffer.from(body, 'utf8')]));" "%REQUEST_FILE%"
"%EXE%" <"%REQUEST_FILE%" >"%RESPONSE_FILE%"
"%BUN_EXE%" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); if (data.id === 11 && data.result.name === 'ceretree') process.exit(0); process.exit(1);" "%RESPONSE_FILE%"
if errorlevel 1 exit /b 1

"%BUN_EXE%" -e "const fs = require('node:fs'); const path = require('node:path'); const root = process.argv[1]; const exe = process.argv[2]; const testsDir = process.argv[3]; const jsonRoot = process.argv[4]; const curlBin = process.platform === 'win32' ? 'curl.exe' : 'curl'; const socketPath = path.join(testsDir, 'ceretree-http.sock'); try { fs.rmSync(socketPath, { force: true }); } catch {} const request1 = JSON.stringify({ jsonrpc: '2.0', id: 21, method: 'system.describe' }); const request2 = JSON.stringify({ jsonrpc: '2.0', id: 22, method: 'symbols.overview', params: { language: 'go', roots: [jsonRoot], include: 'src/main.go', max_symbols: 5 } }); const server = Bun.spawn([exe, '--server', 'unix://' + socketPath], { cwd: root, stdout: 'ignore', stderr: 'pipe' }); let response1 = ''; for (let i = 0; i < 50; i += 1) { const curl = Bun.spawnSync([curlBin, '--silent', '--show-error', '--unix-socket', socketPath, '-H', 'content-type: application/json', '-X', 'POST', '--data-binary', request1, 'http://localhost/rpc']); if (curl.exitCode === 0) { response1 = Buffer.from(curl.stdout).toString('utf8'); break; } Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100); } if (response1.length === 0) { server.kill(); process.exit(1); } const parsed1 = JSON.parse(response1); const curl2 = Bun.spawnSync([curlBin, '--silent', '--show-error', '--unix-socket', socketPath, '-H', 'content-type: application/json', '-X', 'POST', '--data-binary', request2, 'http://localhost/rpc']); server.kill(); try { fs.rmSync(socketPath, { force: true }); } catch {} if (curl2.exitCode === 0) { const parsed2 = JSON.parse(Buffer.from(curl2.stdout).toString('utf8')); if (parsed1.result.server_mode.active === true && parsed1.result.server_mode.target.indexOf('unix://') === 0 && parsed1.result.server_mode.transports.includes('http+unix-socket') === true && Array.isArray(parsed2.result.files) && parsed2.result.files.length >= 1) process.exit(0); } process.exit(1);" "%ROOT%" "%EXE%" "%TESTS_DIR%" "%JSON_ROOT%"
if errorlevel 1 exit /b 1

"%BUN_EXE%" -e "const root = process.argv[1]; const exe = process.argv[2]; const curlBin = process.platform === 'win32' ? 'curl.exe' : 'curl'; const port = String(28000 + Math.floor(Math.random() * 10000)); const target = 'tcp://127.0.0.1:' + port; const server = Bun.spawn([exe, '--server', target], { cwd: root, stdout: 'ignore', stderr: 'pipe' }); const request = JSON.stringify({ jsonrpc: '2.0', id: 31, method: 'index.status' }); let response = ''; for (let i = 0; i < 50; i += 1) { const curl = Bun.spawnSync([curlBin, '--silent', '--show-error', '-H', 'content-type: application/json', '-X', 'POST', '--data-binary', request, 'http://127.0.0.1:' + port + '/rpc']); if (curl.exitCode === 0) { response = Buffer.from(curl.stdout).toString('utf8'); break; } Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100); } server.kill(); if (response.length === 0) process.exit(1); const parsed = JSON.parse(response); if (Array.isArray(parsed.result.roots)) process.exit(0); process.exit(1);" "%ROOT%" "%EXE%"
if errorlevel 1 exit /b 1
