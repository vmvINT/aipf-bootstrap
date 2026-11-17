@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0aipf.ps1" %*
exit /b %ERRORLEVEL%
