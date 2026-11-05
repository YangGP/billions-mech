@echo off
setlocal
pushd "%~dp0" || exit /b 1
where godot >nul 2>nul
if errorlevel 1 (
    echo [Billions Mech] Godot was not found in PATH.
    popd
    exit /b 1
)
if not exist ".godot" mkdir ".godot"
call godot --path "%~dp0." --log-file "%~dp0.godot\run.log" %*
set "MECH_EXIT_CODE=%ERRORLEVEL%"
popd
endlocal & exit /b %MECH_EXIT_CODE%
