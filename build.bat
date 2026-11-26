@echo off
setlocal
cd /d "%~dp0"
if errorlevel 1 goto :BUILD_FAILED

echo [BUILD] Project137 ATM Turbo external VGA adapter test

if not exist "tools\sjasmplus.exe" (
  echo [ERROR] tools\sjasmplus.exe not found.
  echo [INFO] Copy sjasmplus.exe from Project132 tools folder.
  goto :BUILD_FAILED
)

del /q "vga_test.TRD" 2>nul
del /q "vga_test.lst" 2>nul
del /q "vga_test.map" 2>nul

tools\sjasmplus.exe --dirbol --lst=vga_test.lst --sym=vga_test.map vga_test.asm
if errorlevel 1 goto :BUILD_FAILED
if not exist "vga_test.TRD" goto :BUILD_FAILED

echo.
echo [SUCCESS] vga_test.TRD created.
echo [OUTPUT] %CD%\vga_test.TRD
echo [LIST]   %CD%\vga_test.lst
echo [SYMBOLS] %CD%\vga_test.map
echo [LOG]    spectrum_out.txt (emulator port EF logger)
echo.
pause
exit /b 0

:BUILD_FAILED
echo.
echo [ERROR] Build failed. Do not run an older vga_test.TRD.
pause
exit /b 1
