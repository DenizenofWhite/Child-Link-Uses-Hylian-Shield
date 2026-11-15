@echo off
rem Child Link Uses Hylian Shield: opens the installer window. PowerShell is started with NO console at all
rem (CreateNoWindow), so no black window stays open behind the installer. This little launcher closes by itself.
set "CLHS_INSTALLER=%~dp0Installer.ps1"
powershell.exe -NoProfile -Command "$p = New-Object System.Diagnostics.ProcessStartInfo 'powershell.exe'; $p.Arguments = '-NoProfile -ExecutionPolicy Bypass -STA -File \"' + $env:CLHS_INSTALLER + '\"'; $p.UseShellExecute = $false; $p.CreateNoWindow = $true; [void][System.Diagnostics.Process]::Start($p)"
