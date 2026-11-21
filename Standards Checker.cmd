@echo off
rem Runs the Standards Checker in a console window and waits, so the results stay on screen.
rem Used by the Home Launcher. Any arguments are passed on, e.g.  "Standards Checker.cmd" -Tool "TV-*" -FailuresOnly
setlocal
title Standards Checker
where pwsh >nul 2>nul
if %errorlevel%==0 (set "PSEXE=pwsh") else (set "PSEXE=powershell")
%PSEXE% -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Standards-Checker.ps1" %*
echo.
if not defined NO_PAUSE pause
