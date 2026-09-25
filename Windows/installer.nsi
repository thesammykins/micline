Unicode True
!include "MUI2.nsh"
!include "x64.nsh"
Name "MicLine Windows Test"
OutFile "dist\MicLine-Windows-x64-Setup.exe"
InstallDir "$LOCALAPPDATA\Programs\MicLine"
RequestExecutionLevel user
SetCompressor /SOLID lzma
!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "..\LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "This build requires Windows 11 x64."
    Abort
  ${EndIf}
FunctionEnd

Section "MicLine" Main
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  File /r "dist\MicLine\*"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateShortcut "$SMPROGRAMS\MicLine.lnk" "$INSTDIR\MicLine.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\MicLineWindowsTest" "DisplayName" "MicLine Windows Test"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\MicLineWindowsTest" "DisplayVersion" "0.1.0-test"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\MicLineWindowsTest" "UninstallString" '$"$INSTDIR\Uninstall.exe$"'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\MicLineWindowsTest" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\MicLineWindowsTest" "NoRepair" 1
SectionEnd

Section "Uninstall"
  SetShellVarContext current
  Delete "$SMPROGRAMS\MicLine.lnk"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\MicLineWindowsTest"
  ; Remove only installed payload names. Never recursively delete a user directory.
  !include "dist\uninstall-files.nsh"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
SectionEnd
