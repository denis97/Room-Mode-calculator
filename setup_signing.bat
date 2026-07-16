@echo off
setlocal enabledelayedexpansion

echo === ModeMap Signing Keystore Setup (Windows) ===
echo.
echo This script generates a signing keystore for Play Store releases.
echo You will be prompted for a password (keep it secure!)
echo.

REM Check if keytool is available
where keytool >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: keytool not found. Make sure you have:
    echo - Java JDK installed, OR
    echo - Flutter SDK installed (includes JDK)
    echo.
    echo Add keytool to your PATH or run from a directory containing keytool.exe
    pause
    exit /b 1
)

echo Generating keystore...
keytool -genkey -v -keystore upload-keystore.jks ^
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload ^
  -dname "CN=denodes, OU=ModeMap, O=denodes, L=, ST=, C="

if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Keystore generation failed
    pause
    exit /b 1
)

echo.
echo === SUCCESS ===
echo Keystore generated: upload-keystore.jks
echo.
echo Next steps:
echo.
echo 1. Create android/key.properties with your password:
echo.
echo    storeFile=upload-keystore.jks
echo    storePassword=YOUR_PASSWORD_HERE
echo    keyAlias=upload
echo    keyPassword=YOUR_PASSWORD_HERE
echo.
echo 2. Base64 encode the keystore for GitHub Secrets.
echo    Run this PowerShell command:
echo.
echo    [Convert]::ToBase64String([IO.File]::ReadAllBytes('upload-keystore.jks')) ^| Set-Clipboard
echo.
echo    (This copies the base64 to your clipboard)
echo.
echo 3. Add to GitHub Secrets (Settings ^> Secrets and variables ^> Actions):
echo.
echo    - UPLOAD_KEYSTORE_BASE64: (paste from clipboard)
echo    - KEYSTORE_PASSWORD: (your password)
echo    - KEY_ALIAS: upload
echo    - KEY_PASSWORD: (your password)
echo.
pause
