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
rem Source checkouts need an editor import to refresh global script classes.
rem A stale class cache otherwise fails to resolve newly added Resource types.
set "MECH_EXIT_CODE=1"
call godot --headless --path "%~dp0." --import --log-file "%~dp0.godot\import.log" >nul 2>&1
if errorlevel 1 goto import_failed
if not exist ".godot\import.log" goto import_failed
rem Godot can exit zero even when the editor reports script parse errors.
findstr /L /C:"SCRIPT ERROR:" ".godot\import.log" >nul
if not errorlevel 1 goto import_failed
call godot --path "%~dp0." --log-file "%~dp0.godot\run.log" %*
set "MECH_EXIT_CODE=%ERRORLEVEL%"
goto finish

:import_failed
echo [Billions Mech] Project import failed. See .godot\import.log.
if exist ".godot\import.log" type ".godot\import.log"

:finish
popd
endlocal & exit /b %MECH_EXIT_CODE%
