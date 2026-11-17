@echo off
rem AIPF launcher - obey host PowerShell execution policy.
powershell.exe -NoLogo -NoProfile -File "%~dp0aipf.ps1" %*
exit /b %ERRORLEVEL%
