@echo off
REM deploy/setup.cmd (#673) - cmd.exe entry point: forwards to setup.ps1,
REM which forwards to setup.sh via Git Bash/WSL (cmd cannot run either).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
