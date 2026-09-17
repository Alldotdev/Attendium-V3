# Attendium — Deployment & Packaging Guide

## 1. Windows Packaging Overview

Attendium is compiled into a standalone 64-bit native Windows executable and packaged using an automated PowerShell release script and Inno Setup installer.

### Packaging Pipeline
1. Static analysis & full test suite execution.
2. Production bundle compilation: `flutter build windows --release`.
3. Asset bundling (SQLite runtime DLLs, visual icons, templates).
4. Installer creation (Inno Setup / NSIS script).
5. Output validation.

---

## 2. Release Scripts

### Build Script (`scripts/build/build_windows.ps1`)
```powershell
Write-Host "Compiling Attendium Windows Release..."
flutter build windows --release
```

### Clean Setup Verification
1. Launch executable from clean Windows environment.
2. Verify SQLite database initializes at `%APPDATA%\Attendium\attendium.db`.
3. Verify WAL and SHM files are created properly.
4. Verify user onboarding and default academic terms.
