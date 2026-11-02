@echo off
chcp 65001 >nul
setlocal
pushd "%~dp0" || exit /b 1

where godot >nul 2>nul
if errorlevel 1 (
    echo [Billions Mech] 鏈壘鍒?godot 鍛戒护锛岃纭 Godot 宸插姞鍏?PATH銆?    pause
    popd
    exit /b 1
)

rem 鍏佽閫忎紶鍙傛暟锛屼緥濡傦細run.bat --headless --quit-after 60
godot --path . %*
set "EXIT_CODE=%ERRORLEVEL%"

popd
if not "%EXIT_CODE%"=="0" pause
endlocal & exit /b %EXIT_CODE%
