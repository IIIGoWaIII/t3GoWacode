@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "UPSTREAM_URL=https://github.com/pingdotgg/t3code.git"
set "BRANCH=main"
set "LOGFILE=%TEMP%\t3sync.log"

echo ============================================
echo  T3 Code fork sync: upstream + local fix
echo  Branch: %BRANCH%
echo  Log: %LOGFILE%
echo ============================================
echo.

echo === sync started %date% %time% === > "%LOGFILE%"
echo cwd: %CD% >> "%LOGFILE%"

rem --- 1. add upstream remote if missing ---
echo [1/6] upstream remote...
echo === [1/6] upstream remote === >> "%LOGFILE%"
git remote get-url upstream >nul 2>nul
if not errorlevel 1 goto remote_ok
git remote add upstream %UPSTREAM_URL%
if errorlevel 1 goto fail
echo        added upstream (%UPSTREAM_URL%)
echo added upstream: %UPSTREAM_URL% >> "%LOGFILE%"
goto remote_done
:remote_ok
echo        upstream already configured.
echo upstream already configured >> "%LOGFILE%"
:remote_done

rem --- 2. fetch upstream ---
echo [2/6] fetching upstream/%BRANCH%...
echo === [2/6] fetch === >> "%LOGFILE%"
git fetch upstream %BRANCH% >> "%LOGFILE%" 2>&1
if errorlevel 1 goto fail

rem --- 3. verify clean tree ---
echo [3/6] checking working tree...
echo === [3/6] working tree check === >> "%LOGFILE%"
set "DIRTY="
for /f "delims=" %%L in ('git status --porcelain') do (
  echo        NOT clean: %%L
  echo NOT clean: %%L >> "%LOGFILE%"
  set "DIRTY=1"
)
if defined DIRTY (
  echo ERROR: uncommitted changes. Commit or stash them before syncing.
  goto fail
)
echo        working tree is clean.
echo working tree is clean >> "%LOGFILE%"

rem --- 4. rebase onto upstream ---
echo [4/6] rebasing %BRANCH% onto upstream/%BRANCH%...
echo === [4/6] rebase === >> "%LOGFILE%"
git rebase upstream/%BRANCH% >> "%LOGFILE%" 2>&1
if errorlevel 1 goto conflict

rem --- 5. push to fork ---
echo [5/6] pushing to origin %BRANCH% (--force-with-lease)...
echo === [5/6] push === >> "%LOGFILE%"
git push --force-with-lease origin %BRANCH% >> "%LOGFILE%" 2>&1
if errorlevel 1 goto fail

rem --- 6. install + dev ---
echo [6/6] installing deps and starting shared dev server...
echo === [6/6] install === >> "%LOGFILE%"
set "PATH=%~dp0node_modules\.bin;%PATH%"
call vp i >> "%LOGFILE%" 2>&1
if errorlevel 1 goto fail

rem --- local patch guard: apps/web/vite.config.ts loopback binding (see opencode_agent.html) ---
findstr /C:"Bind both loopbacks" "%~dp0apps\web\vite.config.ts" >nul 2>nul
if errorlevel 1 (
  echo.
  echo WARNING: the local apps/web/vite.config.ts loopback patch is missing.
  echo          Without it the shared tailnet URL 502s and phones see a blank page.
  echo          Have a coding agent restore it - see opencode_agent.html section
  echo          "Vite loopback binding fix".
  echo.
  echo WARNING: vite.config.ts loopback patch missing >> "%LOGFILE%"
)

echo.
echo        Starting dev server (shared on tailnet).
echo        On your phone: open the "pairingUrl:" line printed below (or scan its QR).
echo        Fresh phone link any time:  node apps/server/src/bin.ts pair
echo === [6/6] starting dev server (vp run dev --share) === >> "%LOGFILE%"
call vp run dev --share
echo dev server exited with code %errorlevel% >> "%LOGFILE%"
if errorlevel 1 goto fail

echo.
echo Sync complete.
echo === sync complete %date% %time% === >> "%LOGFILE%"
pause
exit /b 0

:conflict
echo === REBASE CONFLICT %date% %time% === >> "%LOGFILE%"
echo.
echo ============================================================
echo  REBASE CONFLICTS - the rebase is paused mid-way.
echo
echo  The custom OpenCodeAdapter task-lifecycle fix must be
echo  preserved on top of upstream code.
echo
echo  1. Open opencode_agent.html in a browser (this folder).
echo  2. Point a coding agent at that file and at the conflict.
echo  3. After resolving:  git add .
echo                       git rebase --continue
echo  4. Re-run this script to finish the sync.
echo ============================================================
pause
exit /b 1

:fail
echo === FAILURE %date% %time% === >> "%LOGFILE%"
echo.
echo ERROR: sync failed (see message above).
echo Log: %LOGFILE%
pause
exit /b 1