; Inno Setup script for VN Pathfinder 2.0. Build it with tool\package_windows.ps1,
; which builds the app first and passes in the version.
; https://jrsoftware.org/isinfo.php

#define AppName      "VN Pathfinder"
#define AppExeName   "vn_pathfinder.exe"
#define AppPublisher "NikoCloud"
#define AppURL       "https://github.com/NikoCloud/vn-pathfinder-flutter"
#ifndef AppVersion
  #define AppVersion "2.0.0"
#endif

[Setup]
; Not 1.0's AppId: 2.0 is a separate install, so the two can sit side by side.
AppId={{7D1E4C52-9B3A-4E86-A1F7-2C6B0D8E5F13}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
DefaultDirName={autopf}\{#AppName} 2
DefaultGroupName={#AppName}
AllowNoIcons=yes
LicenseFile=..\LICENSE
OutputDir=..\dist
OutputBaseFilename=VN-Pathfinder-{#AppVersion}-windows-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2/ultra
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayIcon={app}\{#AppExeName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\dist\app\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\LICENSE";    DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md";  DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}";           Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";     Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
