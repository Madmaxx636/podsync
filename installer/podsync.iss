; Inno Setup script for the PodSync Windows installer.
; Built by .github/workflows/windows.yml:  ISCC /DAppVersion=0.1.0 installer\podsync.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6F2B0A0E-3C0B-4D54-8E55-5BDB0E6A7C21}
AppName=PodSync
AppVersion={#AppVersion}
AppPublisher=PodSync
; Installs for the current user only, into %LOCALAPPDATA%\Programs, so it needs no admin rights
; (work PCs often do not give them). The setup offers "for all users" if you do have them.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\PodSync
DefaultGroupName=PodSync
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\podsync.exe
UninstallDisplayName=PodSync
OutputDir=..
OutputBaseFilename=PodSync-Setup-x64
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
CloseApplications=yes
VersionInfoVersion={#AppVersion}
VersionInfoDescription=PodSync setup

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "..\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\PodSync"; Filename: "{app}\podsync.exe"
Name: "{autodesktop}\PodSync"; Filename: "{app}\podsync.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\podsync.exe"; Description: "Start PodSync"; Flags: nowait postinstall skipifsilent

; Your library, settings and downloads live outside the install folder, so uninstalling keeps them.
