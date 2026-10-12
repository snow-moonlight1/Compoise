; Compoise per-user installer. Built by .github/workflows/release.yml:
;   makensis /DVERSION=1.0.0 /DSRC_DIR=<bundle> /DOUT_FILE=<setup.exe> /DARCH=x64 compoise.nsi
; Installs to %LOCALAPPDATA%\Programs\Compoise without administrator rights.
; User data stays in %APPDATA%\Compoise\Compoise and is not removed on uninstall.
Unicode true
SetCompressor /SOLID lzma
RequestExecutionLevel user

!include "MUI2.nsh"

!ifndef VERSION
  !error "VERSION is required"
!endif
!ifndef SRC_DIR
  !error "SRC_DIR is required"
!endif
!ifndef OUT_FILE
  !define OUT_FILE "compoise-setup.exe"
!endif
!ifndef ARCH
  !define ARCH "x64"
!endif

!define APP_NAME "Compoise"
!define APP_EXE "compoise.exe"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Compoise"

Name "${APP_NAME}"
OutFile "${OUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\Compoise"
InstallDirRegKey HKCU "Software\Compoise" "InstallDir"
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "Compoise"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "Compoise installer (${ARCH})"
VIAddVersionKey "LegalCopyright" "Compoise contributors, GPL-3.0-only"

!define MUI_ICON "..\runner\resources\app_icon.ico"
!define MUI_UNICON "..\runner\resources\app_icon.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "..\..\LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "English"

Section "Install"
  ; Close a running copy so its files can be replaced.
  nsExec::Exec 'taskkill /IM ${APP_EXE} /F'
  SetOutPath "$INSTDIR"
  File /r "${SRC_DIR}\*.*"
  WriteUninstaller "$INSTDIR\uninstall.exe"
  CreateShortCut "$SMPROGRAMS\Compoise.lnk" "$INSTDIR\${APP_EXE}"
  CreateShortCut "$DESKTOP\Compoise.lnk" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKCU "Software\Compoise" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "Compoise"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "Compoise contributors"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  nsExec::Exec 'taskkill /IM ${APP_EXE} /F'
  Delete "$SMPROGRAMS\Compoise.lnk"
  Delete "$DESKTOP\Compoise.lnk"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKCU "${UNINST_KEY}"
  DeleteRegKey HKCU "Software\Compoise"
SectionEnd
